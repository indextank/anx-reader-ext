const blockTags = new Set([
    'article', 'aside', 'audio', 'blockquote', 'caption',
    'details', 'dialog', 'div', 'dl', 'dt', 'dd',
    'figure', 'footer', 'form', 'figcaption',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hgroup', 'hr', 'li',
    'main', 'math', 'nav', 'ol', 'p', 'pre', 'section', 'tr',
])

function rangeIsEmpty(range) {
    return range.collapsed || range.toString().trim() === ''
}

// CJK closing quotes/brackets are included so a sentence keeps its closing
// marks instead of leaving them stranded at the start of the next sentence.
const quoteChars = new Set(['"', "'", '“', '”', '‘', '’', '」', '』', '）', '》', '】'])
// Only closing marks may trail a terminator; opening quotes must stay with
// the sentence they introduce.
const closingQuoteChars = new Set(['"', '”', '’', '」', '』', '）', '》', '】'])

const isLocalLink = href => {
    if (!href) return false
    const trimmed = href.trim()
    if (!trimmed) return false
    if (trimmed.startsWith('#')) return true
    return !/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(trimmed)
}

const shouldSkipTextNode = node => {
    const parent = node.parentElement
    if (!parent) return false
    const anchor = parent.closest('a')
    if (!anchor) return false
    return isLocalLink(anchor.getAttribute('href'))
}

const getRangeText = range => {
    const fragment = range.cloneContents()
    // A <br> separates text nodes but contributes no text of its own, which
    // would join adjacent lines into one word ("endstart"). Replace it with
    // a space in the cloned fragment so line breaks survive extraction.
    for (const br of fragment.querySelectorAll('br')) {
        br.replaceWith(br.ownerDocument.createTextNode(' '))
    }
    const walker = document.createTreeWalker(fragment, NodeFilter.SHOW_TEXT)
    let text = ''
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (shouldSkipTextNode(node)) continue
        text += node.textContent ?? ''
    }
    return text
}

const findBlockAncestor = node => {
    let el = node.parentElement
    while (el && !blockTags.has(el.tagName?.toLowerCase?.())) {
        el = el.parentElement
    }
    return el ?? node.ownerDocument?.body ?? null
}

const NODE_ELEMENT = 1
const NODE_TEXT = 3

// Ordered character layout of the sentence [range], built with exactly the same
// extraction rules as getRangeText(): text inside a local link is not part of
// the sentence text and a <br> contributes one synthetic space.
//
// Every entry maps a span of the extracted sentence text back to the DOM node
// it came from, so a character offset can be converted into a DOM point when
// only the spoken part of the sentence has to be highlighted. Entries:
//   { kind: 'text', node, offset, start, end } -> range is
//       [node, offset + (char - start)] .. [node, offset + (char - start)]
//   { kind: 'br', start, end }                 -> one space, no glyph to paint
const getTextSegments = range => {
    const segments = []
    const root = range?.commonAncestorContainer
    const doc = root?.ownerDocument
    if (!root || !doc) return segments
    const walkerRoot = root.nodeType === NODE_ELEMENT ? root : root.parentElement ?? doc.body
    if (!walkerRoot) return segments
    const walker = doc.createTreeWalker(
        walkerRoot, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT)
    let offset = 0
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (node.nodeType === NODE_TEXT) {
            if (shouldSkipTextNode(node)) continue
            let start = 0
            let end = node.data.length
            if (node === range.startContainer) start = range.startOffset
            if (node === range.endContainer) end = range.endOffset
            if (start >= end) continue
            if (node !== range.startContainer && node !== range.endContainer
                && !range.intersectsNode(node)) continue
            segments.push({
                kind: 'text', node, offset: start,
                start: offset, end: offset + (end - start),
            })
            offset += end - start
        }
        // <br> separates text nodes but renders as a line break; the extraction
        // replaces it with one space (see getRangeText), so the character map
        // must reserve exactly one slot for it. EPUB sections may be parsed as
        // XML, where `tagName` keeps the source case (`br`).
        else if ((node.nodeName || '').toLowerCase() === 'br') {
            if (!range.intersectsNode(node)) continue
            segments.push({ kind: 'br', start: offset, end: offset + 1 })
            offset += 1
        }
    }
    return segments
}

// Normalize the spoken spans coming from the playback pipeline. Values are
// UTF-16 offsets into the extracted sentence text; anything invalid is dropped
// so a malformed bridge payload can never corrupt the highlight.
export const normalizeSpokenRanges = ranges => {
    if (!Array.isArray(ranges)) return []
    const normalized = []
    for (const range of ranges) {
        if (!range || typeof range !== 'object') continue
        const start = Number(range.start)
        const end = Number(range.end)
        if (!Number.isFinite(start) || !Number.isFinite(end)) continue
        const from = Math.max(0, Math.trunc(start))
        const to = Math.max(from, Math.trunc(end))
        if (to > from) normalized.push({ start: from, end: to })
    }
    return normalized.sort((a, b) => a.start - b.start)
}

const isSentenceTerminator = (char, nextChar) => {
    if (char === '.') {
        if (!nextChar) return true
        if (quoteChars.has(nextChar)) return true
        if (/\s/.test(nextChar)) return true
        return false
    }
    return char === '!' || char === '?' || char === '。' || char === '！' || char === '？'
}

const advancePastQuotes = (text, index) => {
    let end = index
    while (end < text.length && closingQuoteChars.has(text[end])) end++
    return end
}

function* getBlocks(doc) {
    const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
    let startNode = null
    let startOffset = 0
    let currentBlock = null
    let lastNode = null
    let lastOffset = 0

    const flushRange = () => {
        if (!startNode || !lastNode) return null
        const range = doc.createRange()
        range.setStart(startNode, startOffset)
        range.setEnd(lastNode, lastOffset)
        startNode = null
        startOffset = 0
        currentBlock = null
        lastNode = null
        lastOffset = 0
        if (rangeIsEmpty(range)) return null
        return range
    }

    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (!node.textContent) continue
        if (shouldSkipTextNode(node)) continue

        const block = findBlockAncestor(node)

        if (!startNode) {
            startNode = node
            startOffset = 0
            currentBlock = block
        } else if (block !== currentBlock) {
            const range = flushRange()
            if (range) yield range
            startNode = node
            startOffset = 0
            currentBlock = block
        }

        const text = node.textContent
        let index = 0
        while (index < text.length) {
            const char = text[index]
            const nextChar = text[index + 1]
            if (isSentenceTerminator(char, nextChar)) {
                const endOffset = advancePastQuotes(text, index + 1)
                const range = doc.createRange()
                range.setStart(startNode, startOffset)
                range.setEnd(node, endOffset)
                if (!rangeIsEmpty(range)) yield range
                startNode = node
                startOffset = endOffset
                lastNode = node
                lastOffset = endOffset
                index = endOffset
                continue
            }
            index += 1
        }

        lastNode = node
        lastOffset = text.length

        if (startNode === node && startOffset === text.length) {
            startNode = null
            startOffset = 0
            currentBlock = null
        }
    }

    const remaining = flushRange()
    if (remaining) yield remaining
}

class ListIterator {
    #arr = []
    #iter
    #index = -1
    #f
    constructor(iter, f = x => x) {
        this.#iter = iter
        this.#f = f
    }
    current() {
        if (this.#arr[this.#index]) return this.#f(this.#arr[this.#index])
    }
    first() {
        const newIndex = 0
        if (this.#arr[newIndex]) {
            this.#index = newIndex
            return this.#f(this.#arr[newIndex])
        }
    }
    last() {
        for (const value of this.#iter) this.#arr.push(value)
        const newIndex = this.#arr.length - 1
        if (this.#arr[newIndex]) {
            this.#index = newIndex
            return this.#f(this.#arr[newIndex])
        }
    }
    prev() {
        const newIndex = this.#index - 1
        if (this.#arr[newIndex]) {
            this.#index = newIndex
            return this.#f(this.#arr[newIndex])
        }
    }
    next() {
        const newIndex = this.#index + 1
        if (this.#arr[newIndex]) {
            this.#index = newIndex
            return this.#f(this.#arr[newIndex])
        }
        while (true) {
            const { done, value } = this.#iter.next()
            if (done) break
            this.#arr.push(value)
            if (this.#arr[newIndex]) {
                this.#index = newIndex
                return this.#f(this.#arr[newIndex])
            }
        }
    }
    #ensure(index) {
        while (this.#arr[index] == null) {
            const { done, value } = this.#iter.next()
            if (done) break
            this.#arr.push(value)
            if (this.#arr.length - 1 >= index) break
        }
        return this.#arr[index]
    }
    prepare() {
        const newIndex = this.#index + 1
        if (this.#arr[newIndex]) return this.#f(this.#arr[newIndex])
        while (true) {
            const { done, value } = this.#iter.next()
            if (done) break
            this.#arr.push(value)
            if (this.#arr[newIndex]) return this.#f(this.#arr[newIndex])
        }
    }
    peek(count = 1, offset = 1) {
        if (count <= 0) return []
        const startIndex = Math.max(this.#index + offset, 0)
        const results = []
        const endIndex = startIndex + count
        for (let idx = startIndex; idx < endIndex; idx++) {
            const value = this.#arr[idx] ?? this.#ensure(idx)
            if (!value) break
            results.push(this.#f(value))
        }
        return results
    }
    // Raw current entry (before the mapper is applied); for the TTS list this
    // is the live Range of the current sentence.
    currentEntry() {
        return this.#arr[this.#index]
    }
    // Mapped end of the current entry, see `TTS` where the mapper returns
    // `[text, range]`.
    currentRange() {
        return this.current()?.[1] ?? null
    }
    // Entry at [index] (pull from the underlying generator as needed) WITHOUT
    // moving the iterator. Used to look a sentence up by CFI while the playback
    // pipeline keeps its own iterator position. Returns the mapped entry, i.e.
    // `[text, range]` for the TTS list, or undefined past the last sentence.
    entryAt(index) {
        const value = this.#ensure(index)
        return value ? this.#f(value) : undefined
    }
    // First index whose mapped entry matches [f], without moving the iterator.
    // Entries already pulled from the generator stay cached, so a monotonically
    // advancing lookup only generates the new sentences.
    findIndex(f) {
        for (let index = 0; ; index++) {
            const value = this.#ensure(index)
            if (!value) return -1
            if (f(this.#f(value))) return index
        }
    }
    // Point the iterator at an already located [index]. Used when the reader
    // navigated away and the TTS list had to be rebuilt on a fresh document:
    // the pipeline's next advance must continue right after that sentence.
    selectIndex(index) {
        const value = this.#ensure(index)
        if (!value) return
        this.#index = index
        return this.#f(value)
    }
    find(f) {
        const index = this.#arr.findIndex(x => f(x))
        if (index > -1) {
            this.#index = index
            return this.#f(this.#arr[index])
        }
        while (true) {
            const { done, value } = this.#iter.next()
            if (done) break
            this.#arr.push(value)
            if (f(value)) {
                this.#index = this.#arr.length - 1
                return this.#f(value)
            }
        }
    }
}

export class TTS {
    #list
    #lastMark
    #getCfi
    #cfiIndex = new Map()
    constructor(doc, textWalker, highlight, getCfi) {
        this.doc = doc
        this.highlight = highlight
        this.#getCfi = getCfi
        this.#list = new ListIterator(getBlocks(doc), range => {
            return [getRangeText(range), range]
        })
    }

    #getText(text, getNode) {
        if (!text) return ''
        if (!getNode) return text
        const tempElement = document.createElement('div')
        tempElement.innerHTML = text
        let node = getNode(tempElement)?.previousSibling
        while (node) {
            const next = node.previousSibling ?? node.parentNode?.previousSibling
            node.parentNode.removeChild(node)
            node = next
        }
        return tempElement.textContent
    }

    #ensureCurrentEntry() {
        const current = this.#list.current()
        if (current) return current
        return this.#list.first() ?? this.#list.next()
    }

    #resultFrom(entry, { highlight = false } = {}) {
        if (!entry) return null
        const [text, range] = entry
        if (!text || !range) return null
        const plainText = this.#getText(text)
        let cfi = null
        if (highlight && this.highlight && range.cloneRange) {
            cfi = this.highlight(range.cloneRange()) ?? null
        }
        if (!cfi && this.#getCfi && range.cloneRange) {
            cfi = this.#getCfi(range.cloneRange())
        }
        return { text: plainText, cfi }
    }

    start() {
        this.#lastMark = null
        const entry = this.#list.first()
        if (!entry) return this.next()
        return this.#resultFrom(entry, { highlight: true })?.text
    }

    end() {
        this.#lastMark = null
        const entry = this.#list.last()
        if (!entry) return this.next()
        return this.#resultFrom(entry, { highlight: true })?.text
    }

    resume() {
        const entry = this.#list.current()
        if (!entry) return this.next()
        return this.#resultFrom(entry)?.text
    }

    prev(paused) {
        this.#lastMark = null
        const entry = this.#list.prev()
        if (paused && entry?.[1]) this.highlight(entry[1].cloneRange())
        return this.#resultFrom(entry)?.text
    }

    next(paused) {
        this.#lastMark = null
        const entry = this.#list.next()
        if (paused && entry?.[1]) this.highlight(entry[1].cloneRange())
        return this.#resultFrom(entry)?.text
    }

    // get next text without moving the iterator
    prepare() {
        const entry = this.#list.prepare()
        return this.#resultFrom(entry)?.text
    }

    // Live Range of the sentence that is currently being read (or is about to
    // be read). Used by the reader page-break bridge to compare the sentence
    // extent with the visible page. Callers must not mutate the returned range.
    currentEntryRange() {
        const entry = this.#ensureCurrentEntry()
        return entry?.[1] ?? null
    }

    // Number of characters, counted exactly like the text returned by
    // currentDetail() (same extraction: local links skipped, <br> counted as
    // one space), from the start of the current sentence up to a DOM point
    // that lies inside it. Used to report the page-boundary offset inside the
    // slice the Dart pipeline is reading. Returns null when the point cannot
    // be measured.
    currentEntryOffsetAt(node, offset) {
        const range = this.currentEntryRange()
        if (!range || !node) return null
        const doc = range.startContainer?.ownerDocument
        if (!doc) return null
        try {
            const prefix = doc.createRange()
            prefix.setStart(range.startContainer, range.startOffset)
            prefix.setEnd(node, offset)
            return getRangeText(prefix).length
        } catch (e) {
            console.error('currentEntryOffsetAt failed', e)
            return null
        }
    }

    // Index of the sentence whose CFI equals [cfi], looked up WITHOUT moving
    // the iterator. CFIs already computed for cached sentences are memoized, so
    // looking up the next spoken sentence only measures the newly generated
    // ones instead of re-walking the whole section every time.
    #findEntryIndexByCfi(cfi) {
        if (!cfi) return -1
        const cached = this.#cfiIndex.get(cfi)
        if (cached != null) return cached
        let index = 0
        for (;;) {
            const entry = this.#list.entryAt(index)
            if (!entry) return -1
            const range = entry[1]
            if (range?.cloneRange) {
                let candidate = null
                try {
                    candidate = this.#getCfi?.(range.cloneRange()) ?? null
                } catch (e) {
                    candidate = null
                }
                // Value is read-only data; `0` is a valid index, so use has().
                if (candidate && !this.#cfiIndex.has(candidate))
                    this.#cfiIndex.set(candidate, index)
                if (candidate === cfi) return index
            }
            index += 1
        }
    }

    // Diagnostic helper (used by the browser evidence scripts): first entry
    // CFIs and the CFI lookup result for [cfi].
    debugCfiLookup(cfi, limit = 8) {
        const entries = []
        for (let index = 0; index < limit; index++) {
            const entry = this.#list.entryAt(index)
            if (!entry) break
            let candidate = null
            let error = null
            try {
                candidate = this.#getCfi?.(entry[1].cloneRange()) ?? null
            } catch (e) {
                error = String(e)
            }
            entries.push({
                index,
                text: (entry[0] || '').slice(0, 24),
                candidate,
                error,
            })
        }
        return { cfi, found: this.#findEntryIndexByCfi(cfi), entries }
    }

    // Map sentence-relative spoken spans onto DOM ranges using exactly the same
    // text extraction as getRangeText(): local-link text is not part of the
    // sentence text, so it is not part of any painted range either; a <br>
    // occupies one character slot but has no glyph to paint.
    #spokenDomRanges(sentenceRange, spokenRanges) {
        const segments = getTextSegments(sentenceRange)
        if (!segments.length) return []
        const doc = sentenceRange.startContainer?.ownerDocument
        if (!doc) return []
        const totalLength = segments[segments.length - 1].end
        const domRanges = []
        for (const spoken of spokenRanges) {
            const start = Math.min(spoken.start, totalLength)
            const end = Math.min(spoken.end, totalLength)
            if (end <= start) continue
            for (const segment of segments) {
                const from = Math.max(start, segment.start)
                const to = Math.min(end, segment.end)
                if (to <= from) continue
                if (segment.kind !== 'text') continue
                const domRange = doc.createRange()
                const offset = segment.offset
                domRange.setStart(segment.node, offset + (from - segment.start))
                domRange.setEnd(segment.node, offset + (to - segment.start))
                if (!domRange.collapsed) domRanges.push(domRange)
            }
        }
        return domRanges
    }

    // Paint exactly the spoken spans [ranges] of the sentence identified by
    // [cfi] (UTF-16 offsets into the sentence text, annotations already
    // excluded). Never moves the iterator: the playback pipeline advances it
    // silently while prefetching, then asks for the sentence currently being
    // heard, which may be a sub-span (page-break split) of that sentence.
    //
    // Returns the first painted Range, or null when the sentence cannot be
    // resolved or nothing is paintable.
    paintSpokenRanges(cfi, ranges) {
        this.#lastMark = null
        const spokenRanges = normalizeSpokenRanges(ranges)
        if (!spokenRanges.length) return null
        const index = this.#findEntryIndexByCfi(cfi)
        if (index < 0) return null
        const entry = this.#list.entryAt(index)
        const sentenceRange = entry?.[1]
        if (!sentenceRange) return null
        const domRanges = this.#spokenDomRanges(sentenceRange, spokenRanges)
        if (!domRanges.length) return null
        // `keep: true`: the caller clears the previous selection once for the
        // whole sentence, then every spoken segment of this paint is kept.
        for (const range of domRanges) {
            this.highlight?.(range, { scroll: false, keep: true })
        }
        return domRanges[0]
    }

    // Position the iterator at the sentence identified by [cfi] without
    // painting. Used after the user navigated away and the TTS list had to be
    // rebuilt on a fresh document: pinning the iterator at the sentence being
    // read keeps the following advance going with the next sentence (no
    // skipped or duplicated sentence). Returns its detail, or null.
    locateCfi(cfi) {
        this.#lastMark = null
        const index = this.#findEntryIndexByCfi(cfi)
        if (index < 0) return null
        const entry = this.#list.selectIndex(index)
        return this.#resultFrom(entry)
    }

    from(range) {
        this.#lastMark = null
        // First sentence whose END is at or after the anchor's start, so the
        // sentence containing the anchor is read from its beginning.
        // Note: END_TO_START compares the ARGUMENT's end with THIS's start,
        // so this reads anchor.start - range_.end <= 0.
        const entry = this.#list.find(range_ =>
            range.compareBoundaryPoints(Range.END_TO_START, range_) <= 0)
        if (entry?.[1]) this.highlight(entry[1].cloneRange())
        return this.#resultFrom(entry)?.text
    }

    currentDetail() {
        const entry = this.#ensureCurrentEntry()
        return this.#resultFrom(entry)
    }

    // Paint/scroll the highlight for the sentence the iterator currently points
    // at, without moving the iterator. The playback pipeline advances the
    // iterator silently while prefetching, then calls this right before the
    // corresponding audio becomes audible, so the highlighted text and the
    // spoken progress stay in sync even when synthesis is slow.
    highlightCurrent() {
        this.#lastMark = null
        const entry = this.#ensureCurrentEntry()
        if (!entry) return null
        if (entry[1] && this.highlight) this.highlight(entry[1].cloneRange())
        return this.#resultFrom(entry)?.text ?? null
    }

    collectDetails(count = 1, { includeCurrent = false, offset = 1 } = {}) {
        if (!Number.isFinite(count) || count <= 0) return []
        const details = []
        if (includeCurrent) {
            const entry = this.#ensureCurrentEntry()
            const detail = this.#resultFrom(entry)
            if (detail) details.push(detail)
        }
        const needed = count - details.length
        if (needed <= 0) return details
        const entries = this.#list.peek(needed, offset)
        for (const entry of entries) {
            const detail = this.#resultFrom(entry)
            if (detail) details.push(detail)
        }
        return details
    }

    highlightCfi(cfi) {
        if (!cfi) return null
        const entry = this.#list.find(range => {
            const candidate = this.#getCfi?.(range.cloneRange?.())
            return candidate === cfi
        })
        if (!entry) return null
        return this.#resultFrom(entry, { highlight: true })
    }
}
