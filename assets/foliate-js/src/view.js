import * as CFI from './epubcfi.js'
import { TOCProgress, SectionProgress } from './progress.js'
import { Overlayer } from './overlayer.js'
import { textWalker } from './text-walker.js'
import { Translator, TranslationMode } from './translator.js'
import { getTokens } from './anx-tokens.js'
const { TTS, normalizeSpokenRanges } = await import('./tts.js')

const SEARCH_PREFIX = 'foliate-search:'

class History extends EventTarget {
  #arr = []
  #index = -1
  pushState(x) {
    const last = this.#arr[this.#index]
    if (last === x || last?.fraction && last.fraction === x.fraction) return
    this.#arr[++this.#index] = x
    this.#arr.length = this.#index + 1
    this.dispatchEvent(new Event('index-change'))
    this.dispatchEvent(new CustomEvent('pushstate', { detail: x }))
  }
  replaceState(x) {
    const index = this.#index
    this.#arr[index] = x
  }
  back() {
    const index = this.#index
    if (index <= 0) return
    const detail = { state: this.#arr[index - 1] }
    this.#index = index - 1
    this.dispatchEvent(new CustomEvent('popstate', { detail }))
    this.dispatchEvent(new Event('index-change'))
  }
  forward() {
    const index = this.#index
    if (index >= this.#arr.length - 1) return
    const detail = { state: this.#arr[index + 1] }
    this.#index = index + 1
    this.dispatchEvent(new CustomEvent('popstate', { detail }))
    this.dispatchEvent(new Event('index-change'))
  }
  get canGoBack() {
    return this.#index > 0
  }
  get canGoForward() {
    return this.#index < this.#arr.length - 1
  }
  clear() {
    this.#arr = []
    this.#index = -1
  }
}

const languageInfo = lang => {
  if (!lang) return {}
  try {
    const canonical = Intl.getCanonicalLocales(lang)[0] ?? 'en'
    const locale = new Intl.Locale(canonical)
    const isCJK = ['zh', 'ja', 'kr'].includes(locale.language)
    const direction = (locale.getTextInfo?.() ?? locale.textInfo)?.direction
    return { canonical, locale, isCJK, direction }
  } catch (e) {
    console.warn(e)
    return {}
  }
}

export class View extends HTMLElement {
  #root = this.attachShadow({ mode: 'open' })
  #sectionProgress
  #tocProgress
  #pageProgress
  #searchResults = new Map()
  #index
  isFixedLayout = false
  lastLocation
  history = new History()
  #lastCfi = null
  #translator = new Translator()
  constructor() {
    super()
    this.history.addEventListener('popstate', ({ detail }) => {
      const resolved = this.resolveNavigation(detail.state)
      this.renderer.goTo(resolved)
    })
  }
  async open(book) {
    this.book = book
    this.language = languageInfo(book.metadata?.language)

    if (book.splitTOCHref && book.getTOCFragment) {
      const ids = book.sections.map(s => s.id)
      this.#sectionProgress = new SectionProgress(book.sections, 1500, 1600)
      const splitHref = book.splitTOCHref.bind(book)
      const getFragment = book.getTOCFragment.bind(book)
      this.#tocProgress = new TOCProgress()
      await this.#tocProgress.init({
        toc: book.toc ?? [], ids, splitHref, getFragment
      })
      this.#pageProgress = new TOCProgress()
      await this.#pageProgress.init({
        toc: book.pageList ?? [], ids, splitHref, getFragment
      })
    }

    this.isFixedLayout = this.book.rendition?.layout === 'pre-paginated'
    if (this.isFixedLayout) {
      await import('./fixed-layout.js')
      this.renderer = document.createElement('foliate-fxl')
    } else {
      await import('./paginator.js')
      this.renderer = document.createElement('foliate-paginator')
    }
    this.renderer.setAttribute('exportparts', 'head,foot,filter')
    this.renderer.addEventListener('load', e => this.#onLoad(e.detail))
    this.renderer.addEventListener('relocate', e => this.#onRelocate(e.detail))
    this.renderer.addEventListener('create-overlayer', e =>
      e.detail.attach(this.#createOverlayer(e.detail)))
    this.renderer.open(book)
    this.#root.append(this.renderer)

    if (book.sections.some(section => section.mediaOverlay)) {
      book.media.activeClass ||= '-epub-media-overlay-active'
      const activeClass = book.media.activeClass
      this.mediaOverlay = book.getMediaOverlay()
      let lastActive
      this.mediaOverlay.addEventListener('highlight', e => {
        const resolved = this.resolveNavigation(e.detail.text)
        this.renderer.goTo(resolved)
          .then(() => {
            const { doc } = this.renderer.getContents()
              .find(x => x.index = resolved.index)
            const el = resolved.anchor(doc)
            el.classList.add(activeClass)
            lastActive = new WeakRef(el)
          })
      })
      this.mediaOverlay.addEventListener('unhighlight', () => {
        lastActive?.deref()?.classList?.remove(activeClass)
      })
    }
  }
  close() {
    this.renderer?.destroy()
    this.renderer?.remove()
    this.#sectionProgress = null
    this.#tocProgress = null
    this.#pageProgress = null
    this.#searchResults = new Map()
    this.lastLocation = null
    this.history.clear()
    this.tts = null
    this.mediaOverlay = null
    this.#translator?.destroy()
  }
  goToTextStart() {
    return this.goTo(this.book.landmarks
      ?.find(m => m.type.includes('bodymatter') || m.type.includes('text'))
      ?.href ?? this.book.sections.findIndex(s => s.linear !== 'no'))
  }
  async init({ lastLocation, showTextStart }) {
    const resolved = lastLocation ? this.resolveNavigation(lastLocation) : null
    if (resolved) {
      await this.renderer.goTo(resolved)
      this.history.pushState(lastLocation)
    }
    else if (showTextStart) await this.goToTextStart()
    else {
      this.history.pushState(0)
      await this.next()
    }
  }
  #emit(name, detail, cancelable) {
    return this.dispatchEvent(new CustomEvent(name, { detail, cancelable }))
  }
  #onRelocate({ reason, range, index, fraction, size }) {
    this.#index = index
    const progress = this.#sectionProgress?.getProgress(index, fraction, size) ?? {}
    const tocItem = this.#tocProgress?.getProgress(index, range)
    const pageItem = this.#pageProgress?.getProgress(index, range)
    const cfi = this.getCFI(index, range)
    const totalPages = this.renderer.pages ? this.renderer.pages - 2 : progress.section.total
    const currentPage = this.renderer.page ?? progress.section.current
    const chapterLocation = {
      current: currentPage,
      total: totalPages
    }

    this.lastLocation = { ...progress, tocItem, pageItem, cfi, range, chapterLocation }
    if (reason === 'snap' || reason === 'page' || reason === 'scroll')
      this.history.replaceState(cfi)

    if (cfi && (!this.#lastCfi || cfi !== this.#lastCfi)) {
      this.#lastCfi = cfi
      this.#emit('relocate', this.lastLocation)
    }
  }

  #onLoad({ doc, index }) {
    // set language and dir if not already set
    doc.documentElement.lang ||= this.language.canonical ?? ''
    if (!this.language.isCJK)
      doc.documentElement.dir ||= this.language.direction ?? ''

    this.#handleLinks(doc, index)
    this.#handleClick(doc)
    this.#handleImage(doc)
    
    // Start translation observation for this document
    this.#translator.observeDocument(doc)
    
    this.#emit('load', { doc, index })
  }
  #handleLinks(doc, index) {
    const { book } = this
    const section = book.sections[index]
    for (const a of doc.querySelectorAll('a[href]'))
      a.addEventListener('click', e => {
        e.preventDefault()
        e.stopPropagation()
        const href_ = a.getAttribute('href')
        const href = section?.resolveHref?.(href_) ?? href_
        if (book?.isExternal?.(href))
          Promise.resolve(this.#emit('external-link', { a, href }, true))
            .then(x => x ? globalThis.open(href, '_blank') : null)
            .catch(e => console.error(e))
        else Promise.resolve(this.#emit('link', { a, href }, true))
          .then(x => x ? this.goTo(href) : null)
          .catch(e => console.error(e))
      })
  }

  #handleImage(doc) {
    for (const img of doc.querySelectorAll('img')) {
      // disable for a link
      if (img.closest('a[href]')) continue;

      // prevent iOS long-press image preview / callout and disable dragging/selecting
      img.style.webkitTouchCallout = 'none'       // iOS long-press callout
      img.style.webkitUserSelect = 'none'
      img.style.userSelect = 'none'
      img.style.webkitUserDrag = 'none'
      img.draggable = false
      // also block contextmenu to be safe
      img.addEventListener('contextmenu', e => { e.preventDefault(); e.stopPropagation(); }, true);
      // Check if device supports touch (mobile/tablet)
      const isTouchDevice = 'ontouchstart' in window;
 
      if (isTouchDevice) {
        // For touch devices, implement longpress
        let longPressTimer;
        let longPressTriggered = false;
        const longPressDelay = 500; // 500ms for longpress
      
        img.addEventListener('touchstart', e => {
          longPressTriggered = false;
          longPressTimer = setTimeout(() => {
            longPressTriggered = true;
            this.#emit('click-image', { img });
          }, longPressDelay);
        });
      
        img.addEventListener('touchend', e => {
          clearTimeout(longPressTimer);
          // do not prevent here so a short tap will produce a normal click that can bubble
        });
      
        img.addEventListener('touchmove', e => {
          clearTimeout(longPressTimer);
        });
      
        // intercept the synthetic click after a longpress and suppress it;
        // allow normal clicks (short taps) to bubble
        img.addEventListener('click', e => {
          if (longPressTriggered) {
            e.preventDefault();
            e.stopPropagation();
            longPressTriggered = false;
          }
        }, true);
      } else {
        // For desktop devices, keep original click behavior
        img.addEventListener('click', e => {
          e.preventDefault()
          e.stopPropagation()
          this.#emit('click-image', { img })
        })
      }
    }
  }

  #handleClick(doc) {
    // CEF/Chromium collapses an existing selection during pointerdown, before
    // `click`. The Range check below then misses and click-view would page-turn
    // / toggle chrome on the dismiss click. Latch at pointerdown (capture) —
    // same intent as mobile's "if still Range, don't emit click-view".
    let hadSelectionOnPointerDown = false
    doc.addEventListener('pointerdown', e => {
      if (typeof e.button === 'number' && e.button !== 0) return
      const sel = doc.getSelection()
      hadSelectionOnPointerDown = !!(sel && sel.type === 'Range')
    }, true)

    doc.addEventListener('click', e => {
      // Desktop: ignore right/middle click so they do not trigger page-turn zones.
      if (typeof e.button === 'number' && e.button !== 0) return

      if (window.isFootNoteOpen() && !e.currentTarget.__isFootNote) {
        window.closeFootNote()
        return
      }

      // Dismiss-selection click: clear any leftover Range and do not emit click-view.
      if (hadSelectionOnPointerDown) {
        hadSelectionOnPointerDown = false
        try {
          const sel = doc.getSelection()
          if (sel && sel.type === 'Range') sel.removeAllRanges()
        } catch (_) {}
        return
      }

      if (doc.getSelection().type === "Range")
        return

      const position = doc.position
      const scale = doc.scale
      let { clientX, clientY } = e
      
      // if the position is not null, it is fixed layout
      if (position) {
        clientX *= scale
        clientY *= scale

        const docWidth = doc.documentElement.getBoundingClientRect().width * scale
        if (position === 'right' && docWidth * 2.2 < window.innerWidth) {
          clientX += window.innerWidth * 0.5
        }
        this.#emit('click-view', { x: clientX, y: clientY })
        return
      }
      
      const iframe = doc.defaultView?.frameElement
      if (iframe) {
        const rect = iframe.getBoundingClientRect()
        clientX += rect.left
        clientY += rect.top
      }

      this.#emit('click-view', { x: clientX, y: clientY })
    })
    this.renderer.addEventListener('click', e => {
      if (typeof e.button === 'number' && e.button !== 0) return
      const { clientX, clientY } = e
      while (clientX > window.innerWidth) {
        clientX -= window.innerWidth
      }
      this.#emit('click-view', { x: clientX, y: clientY })
    })
  }
  async addAnnotation(annotation, remove) {
    const { value } = annotation
    if (value.startsWith(SEARCH_PREFIX)) {
      const cfi = value.replace(SEARCH_PREFIX, '')
      const { index, anchor } = await this.resolveNavigation(cfi)
      const obj = this.#getOverlayer(index)
      if (obj) {
        const { overlayer, doc } = obj
        if (remove) {
          overlayer.remove(value)
          return
        }
        const range = doc ? anchor(doc) : anchor
        overlayer.add(value, range, Overlayer.outline, { color: getTokens().searchOutlineColor });
      }
      return
    }
    const { index, anchor } = await this.resolveNavigation(value)
    const obj = this.#getOverlayer(index)
    if (obj) {
      const { overlayer, doc } = obj
      overlayer.remove(value)
      if (!remove) {
        const range = doc ? anchor(doc) : anchor
        const draw = (func, opts) => overlayer.add(value, range, func, opts)
        this.#emit('draw-annotation', { draw, annotation, doc, range })
      }
    }
    const label = this.#tocProgress.getProgress(index)?.label ?? ''
    return { index, label }
  }
  deleteAnnotation(annotation) {
    return this.addAnnotation(annotation, true)
  }
  #getOverlayer(index) {
    return this.renderer.getContents()
      .find(x => x.index === index && x.overlayer)
  }
  #createOverlayer({ doc, index }) {
    const overlayer = new Overlayer(doc)
    doc.addEventListener('click', e => {
      const [value, range] = overlayer.hitTest(e)
      if (value && !value.startsWith(SEARCH_PREFIX)) {
        e.preventDefault()
        e.stopPropagation()
        this.#emit('show-annotation', { value, index, range })
      }
    }, true)

    const list = this.#searchResults.get(index)
    if (list) for (const item of list) this.addAnnotation(item)

    this.#emit('create-overlay', { index })
    return overlayer
  }
  async showAnnotation(annotation) {
    const { value } = annotation
    const resolved = await this.goTo(value)
    if (resolved) {
      const { index, anchor } = resolved
      const { doc } = this.#getOverlayer(index)
      const range = anchor(doc)
      this.#emit('show-annotation', { value, index, range })
    }
  }
  getCFI(index, range) {
    const baseCFI = this.book.sections[index].cfi ?? CFI.fake.fromIndex(index)
    if (!range) return baseCFI
    return CFI.joinIndir(baseCFI, CFI.fromRange(range))
  }
  resolveCFI(cfi) {
    if (this.book.resolveCFI)
      return this.book.resolveCFI(cfi)
    else {
      const parts = CFI.parse(cfi)
      const index = CFI.fake.toIndex((parts.parent ?? parts).shift())
      const anchor = doc => CFI.toRange(doc, parts)
      return { index, anchor }
    }
  }
  resolveNavigation(target) {
    try {
      if (typeof target === 'number') return { index: target }
      if (typeof target.fraction === 'number') {
        const [index, anchor] = this.#sectionProgress.getSection(target.fraction)
        return { index, anchor }
      }
      if (CFI.isCFI.test(target)) return this.resolveCFI(target)
      return this.book.resolveHref(target)
    } catch (e) {
      console.error(e)
      console.error(`Could not resolve target ${target}`)
    }
  }
  async goTo(target) {
    const resolved = this.resolveNavigation(target)
    try {
      await this.renderer.goTo(resolved)
      this.history.pushState(target)
      return resolved
    } catch (e) {
      console.error(e)
      console.error(`Could not go to ${target}`)
    }
  }
  async goToFraction(frac) {
    const [index, anchor] = this.#sectionProgress.getSection(frac)
    await this.renderer.goTo({ index, anchor })
    this.history.pushState({ fraction: frac })
  }
  async select(target) {
    try {
      const obj = await this.resolveNavigation(target)
      await this.renderer.goTo({ ...obj, select: true })
      this.history.pushState(target)
    } catch (e) {
      console.error(e)
      console.error(`Could not go to ${target}`)
    }
  }
  deselect() {
    for (const { doc } of this.renderer.getContents())
      doc.defaultView.getSelection().removeAllRanges()
  }
  getSectionFractions() {
    const hrefList = this.#tocProgress?.ids ?? []
    return (this.#sectionProgress?.sectionFractions ?? [])
    // .map(x => x + Number.EPSILON)
      .map((fraction, index) => ({
        fraction,
        href: hrefList[index] ?? '',
        index
      }))
  }
  getProgressOf(index, range) {
    const tocItem = this.#tocProgress?.getProgress(index, range)
    const pageItem = this.#pageProgress?.getProgress(index, range)
    return { tocItem, pageItem }
  }
  async getTOCItemOf(target) {
    try {
      const { index, anchor } = await this.resolveNavigation(target)
      const doc = await this.book.sections[index].createDocument()
      const frag = anchor(doc)
      const isRange = frag instanceof Range
      const range = isRange ? frag : doc.createRange()
      if (!isRange) range.selectNodeContents(frag)
      return this.#tocProgress.getProgress(index, range)
    } catch (e) {
      console.error(e)
      console.error(`Could not get ${target}`)
    }
  }
  async prev(distance) {
    await this.renderer.prev(distance)
  }
  async next(distance) {
    await this.renderer.next(distance)
  }
  goLeft() {
    return this.book.dir === 'rtl' ? this.next() : this.prev()
  }
  goRight() {
    return this.book.dir === 'rtl' ? this.prev() : this.next()
  }
  async * #searchSection(matcher, query, index) {
    const doc = await this.book.sections[index].createDocument()
    for (const { range, excerpt } of matcher(doc, query))
      yield { cfi: this.getCFI(index, range), excerpt }
  }
  async * #searchBook(matcher, query) {
    const { sections } = this.book
    for (const [index, { createDocument }] of sections.entries()) {
      if (!createDocument) continue
      const doc = await createDocument()
      const subitems = Array.from(matcher(doc, query), ({ range, excerpt }) =>
        ({ cfi: this.getCFI(index, range), excerpt }))
      const progress = (index + 1) / sections.length
      yield { progress }
      if (subitems.length) yield { index, subitems }
    }
  }
  async * search(opts) {
    console.log('search', opts)
    this.clearSearch()
    const { searchMatcher } = await import('./search.js')
    const { query, index } = opts
    const matcher = searchMatcher(textWalker,
      { defaultLocale: this.language, ...opts })
    const iter = index != null
      ? this.#searchSection(matcher, query, index)
      : this.#searchBook(matcher, query)

    const list = []
    this.#searchResults.set(index, list)

    for await (const result of iter) {
      if (result.subitems) {
        const list = result.subitems
          .map(({ cfi }) => ({ value: SEARCH_PREFIX + cfi }))
        this.#searchResults.set(result.index, list)
        for (const item of list) this.addAnnotation(item)
        yield {
          label: this.#tocProgress.getProgress(result.index)?.label ?? '',
          subitems: result.subitems,
        }
      }
      else {
        if (result.cfi) {
          const item = { value: SEARCH_PREFIX + result.cfi }
          list.push(item)
          this.addAnnotation(item)
        }
        yield result
      }
    }
    yield 'done'
  }
  clearSearch() {
    for (const list of this.#searchResults.values())
      for (const item of list) this.deleteAnnotation(item)
    this.#searchResults.clear()
  }
  oldValue = null
  // Overlay keys currently painted for the TTS highlight, per section index.
  // Every repaint clears the previous set so a page-break split (.a -> .b) or a
  // new sentence never leaves a stale selection behind.
  #ttsHighlightValues = []
  // Section index the `tts` iterator lists its sentences in. Captured when the
  // TTS object is created: the user can navigate to another section while the
  // playback pipeline keeps advancing the iterator, and CFIs/overlays must keep
  // referring to the *reading* section, never to the page the user is looking
  // at. Painting a range into the wrong section is exactly the "fake selection
  // on the wrong page" defect.
  ttsSectionIndex = -1
  #currentSectionIndex() {
    return this.renderer?.getContents?.()[0]?.index ?? this.#index
  }
  // Create a TTS sentence list for [doc] and bind its CFIs/overlays to the
  // section [index] for the whole lifetime of that list.
  #createTts(doc, index) {
    return new TTS(
      doc,
      textWalker,
      (range, opts) => this.#paintTtsRange(range, index, opts),
      (range) => this.getCFI(index, range),
    );
  }
  // Paint one TTS range into the overlayer of the section it belongs to and
  // return the overlay key. A range whose section is not displayed is not
  // painted: `ttsHighlightSpoken` navigates back before painting.
  #paintTtsRange(range, index, { scroll = true, keep = false } = {}) {
    const obj = this.#getOverlayer(index)
    if (!obj) return null
    if (!keep) this.#clearTtsHighlight()
    const { overlayer } = obj
    const value = this.getCFI(index, range)
    overlayer.add(value, range, Overlayer.highlight, {
      color: getTokens().searchHighlightColor,
    })
    // The live Range is kept (not its rects): the debug snapshot must measure
    // it on demand, after the pull-back scroll, when the sentence page is the
    // visible one.
    this.#ttsHighlightValues.push({
      index,
      value,
      range,
      text: range.toString(),
    })
    this.oldValue = value
    if (scroll) this.renderer.scrollToAnchor(range)
    return value
  }
  #describeRects(range) {
    try {
      return Array.from(range.getClientRects?.() ?? [])
        .filter(rect => rect.width > 0 && rect.height > 0)
        .map(rect => ({
          left: rect.left, top: rect.top,
          right: rect.right, bottom: rect.bottom,
        }))
    } catch (e) {
      return []
    }
  }
  #clearTtsHighlight() {
    for (const { index, value } of this.#ttsHighlightValues) {
      this.#getOverlayer(index)?.overlayer.remove(value)
    }
    this.#ttsHighlightValues = []
    this.oldValue = null
  }
  initTTS(stop) {
    if (stop) {
      this.#clearTtsHighlight()
      return
    }
    const content = this.renderer.getContents()[0]
    if (!content) return
    const { doc, index } = content
    if (this.tts && this.tts.doc === doc) {
      this.ttsSectionIndex = index
      return
    }
    this.#clearTtsHighlight()
    this.ttsSectionIndex = index
    this.tts = this.#createTts(doc, index)
  }
  // Ensure the pipeline iterator exists without ever throwing it away: after a
  // manual page turn the bridge calls for text/CFIs must keep reading from the
  // iterator's own section instead of rebuilding it on the page the user is
  // looking at (that used to reset the reading position to the visible page).
  ensureTTS() {
    if (!this.tts) this.initTTS()
  }
  // The TTS sentence being read may continue past the visible page: the reader
  // paginates in the middle of the sentence even though the sentence is a single
  // DOM range. `ttsHighlightSpoken` is called by the playback pipeline right
  // before every engine request becomes audible. It paints exactly the spoken
  // part of the sentence at [cfi], drops the previous selection, and brings the
  // reading page back into view when the user manually paged away.
  //
  // [ranges] are sentence-relative UTF-16 offsets of the spoken segments (see
  // TtsSpokenRange in the Dart pipeline; annotations like `[12]` are excluded).
  // Returns true when the sentence page has been brought into view and painted.
  async ttsHighlightSpoken(cfi, ranges) {
    const target = typeof cfi === 'string' ? cfi : ''
    if (!target || this.isFixedLayout) return false
    const spoken = normalizeSpokenRanges(ranges)
    let resolved = null
    try {
      resolved = await this.resolveNavigation(target)
    } catch (e) {
      console.error('ttsHighlightSpoken: cannot resolve cfi', e)
      return false
    }
    if (!resolved || typeof resolved.index !== 'number'
      || typeof resolved.anchor !== 'function') return false
    const targetIndex = resolved.index
    let content = this.renderer.getContents()[0]
    let navigated = false
    if (!content || content.index !== targetIndex) {
      // The user paged to another section while playback continued: navigate
      // back to the reading sentence. Never push a history entry: the reading
      // position is authoritative and the manual page must not become a
      // navigable "random jump" target.
      if (!await this.#navigateToTtsSection(targetIndex, resolved.anchor))
        return false
      content = this.renderer.getContents()[0]
      if (!content || content.index !== targetIndex) return false
      navigated = true
    }
    if (!this.tts || this.tts.doc !== content.doc
      || this.ttsSectionIndex !== targetIndex) {
      // The renderer replaced the document (navigation away and back): rebuild
      // the sentence list for the fresh document and pin the iterator at the
      // sentence being read, so the next advance continues with the next
      // sentence instead of re-reading/skipping one.
      const rebuilt = this.#createTts(content.doc, targetIndex)
      const located = rebuilt.locateCfi(target)
      if (!located) {
        console.error('ttsHighlightSpoken: sentence not found after rebuild')
        return false
      }
      this.#clearTtsHighlight()
      this.tts = rebuilt
      this.ttsSectionIndex = targetIndex
    }
    // A freshly navigated document may not have been laid out yet: range rects
    // (and therefore the overlay) would be empty. Two frames are enough for the
    // paginator to columnize the new document.
    if (navigated) await new Promise(resolve =>
      requestAnimationFrame(() => requestAnimationFrame(resolve)))
    this.#clearTtsHighlight()
    const first = this.tts.paintSpokenRanges(target, spoken)
    if (!first) return false
    // Fire and forget: the paginator jumps synchronously for anchor scrolls, so
    // there is no animation to wait for and audio start is not delayed.
    try {
      Promise.resolve(this.renderer.scrollToAnchor(first)).catch(() => {})
    } catch (e) {
      console.error('ttsHighlightSpoken: scroll failed', e)
    }
    return true
  }
  // Navigate the renderer to [index] and position the page at the sentence
  // anchor. The paginator ignores navigation while a page-turn is in flight
  // (its #locked window, which lasts a few frames after a user page turn), so
  // wait for it instead of silently failing. Bounded: the Dart pipeline has its
  // own timeout around this call.
  async #navigateToTtsSection(index, anchor) {
    for (let attempt = 0; attempt < 6; attempt++) {
      if (this.renderer.getContents()[0]?.index === index) return true
      if (this.renderer.locked) {
        await new Promise(resolve => setTimeout(resolve, 80))
        continue
      }
      try {
        await this.renderer.goTo({ index, anchor })
      } catch (e) {
        console.error('ttsHighlightSpoken: navigation failed', e)
      }
      if (this.renderer.getContents()[0]?.index === index) return true
      await new Promise(resolve => setTimeout(resolve, 100))
    }
    return this.renderer.getContents()[0]?.index === index
  }
  // Debug snapshot of the current TTS highlight (used by the browser evidence
  // scripts; no UI depends on it).
  ttsHighlightDebug() {
    const content = this.renderer.getContents()[0]
    return {
      sectionIndex: content?.index ?? -1,
      page: this.renderer.page ?? null,
      pages: this.renderer.pages ?? null,
      locationCfi: this.lastLocation?.cfi ?? '',
      ttsSectionIndex: this.ttsSectionIndex,
      painted: this.#ttsHighlightValues.map(entry => ({
        value: entry.value,
        text: entry.text,
        rects: this.#describeRects(entry.range),
      })),
    }
  }
  // The TTS sentence currently being read may continue past the visible page:
  // the reader paginates in the middle of the sentence even though the sentence
  // is a single DOM range. This bridge reports where the visible page ends
  // inside that sentence so the Dart pipeline can turn the page as soon as the
  // last visible character has been spoken, instead of waiting for the whole
  // sentence.
  //
  // Returns null when the whole current sentence is on the current page (or
  // when the reader/TTS/page state cannot be resolved):
  //   { offset, pageEndCfi, sentenceCfi }
  // - offset: UTF-16 offset inside the current slice's text where the visible
  //   page ends (0 < offset < slice length).
  // - pageEndCfi: point CFI of the page-end boundary in the current section.
  // - sentenceCfi: CFI of the current TTS sentence (same value as
  //   ttsCurrentDetail().cfi); lets the Dart adapter detect a stale iterator.
  ttsPageBreak() {
    const tts = this.tts;
    const pageRange = this.lastLocation?.range;
    if (!tts || !pageRange || pageRange.collapsed) return null;
    // Only the reflowable paginated layout can split a sentence across pages:
    // fixed-layout pages are not split, and scrolled mode has no page boundary.
    if (this.isFixedLayout) return null;
    if (this.renderer?.getAttribute?.('flow') === 'scrolled') return null;
    // The page break is only meaningful while the user is looking at the
    // reading section: after a manual page turn away from it, the visible page
    // belongs to another document and comparing its range with the reading
    // sentence would be meaningless.
    if (this.ttsSectionIndex !== this.#currentSectionIndex()) return null;
    const sentenceRange = tts.currentEntryRange?.();
    if (!sentenceRange || sentenceRange.collapsed) return null;
    const doc = sentenceRange.startContainer?.ownerDocument;
    if (!doc || pageRange.startContainer?.ownerDocument !== doc) return null;
    try {
      const pageEndContainer = pageRange.endContainer;
      const pageEndOffset = pageRange.endOffset;
      // -1: the page ends before the sentence starts (sentence is on a later
      // page), 1: the page ends after the sentence (whole sentence visible),
      // 0: the page end lies inside the sentence or exactly on a boundary.
      if (sentenceRange.comparePoint(pageEndContainer, pageEndOffset) !== 0)
        return null;
      const atSentenceStart =
        pageEndContainer === sentenceRange.startContainer &&
        pageEndOffset === sentenceRange.startOffset;
      const atSentenceEnd =
        pageEndContainer === sentenceRange.endContainer &&
        pageEndOffset === sentenceRange.endOffset;
      if (atSentenceStart || atSentenceEnd) return null;

      // Prefer the TTS text extraction so `offset` is directly comparable with
      // the slice text the Dart pipeline synthesizes (local links are skipped
      // and <br> counts as one space there). Fall back to the plain DOM Range
      // text when an older TTS object has no extraction helper.
      let offset = null;
      if (typeof tts.currentEntryOffsetAt === 'function')
        offset = tts.currentEntryOffsetAt(pageEndContainer, pageEndOffset);
      else {
        const visiblePartOfSentence = doc.createRange();
        visiblePartOfSentence.setStart(
          sentenceRange.startContainer, sentenceRange.startOffset);
        visiblePartOfSentence.setEnd(pageEndContainer, pageEndOffset);
        offset = visiblePartOfSentence.toString().length;
      }
      if (!(offset > 0)) return null;

      const pageEndRange = doc.createRange();
      pageEndRange.setStart(pageEndContainer, pageEndOffset);
      pageEndRange.collapse(true);
      const pageEndCfi = this.getCFI(this.ttsSectionIndex, pageEndRange);
      const sentenceCfi = this.getCFI(
        this.ttsSectionIndex, sentenceRange.cloneRange());
      return { offset, pageEndCfi, sentenceCfi };
    } catch (e) {
      // Different documents (stale lastLocation from another section), detached
      // ranges, etc.: no reliable page break.
      console.error('ttsPageBreak failed', e);
      return null;
    }
  }
  // Turn exactly one paginated page using the normal renderer page-turn path
  // (same animation as a user page turn) WITHOUT moving the TTS sentence
  // iterator. Resolves to true when the renderer call completed.
  async ttsTurnPage() {
    if (!this.tts) return false;
    try {
      await this.next();
      return true;
    } catch (e) {
      console.error('ttsTurnPage failed', e);
      return false;
    }
  }
  startMediaOverlay() {
    const { index } = this.renderer.getContents()[0]
    return this.mediaOverlay.start(index)
  }
  
  // Translation control methods
  setTranslationMode(mode) {
    this.#translator.setTranslationMode(mode)
  }
  
  getTranslationMode() {
    return this.#translator.getTranslationMode()
  }
  
  clearTranslations() {
    this.#translator.clearTranslations()
  }
}

customElements.define('foliate-view', View)
