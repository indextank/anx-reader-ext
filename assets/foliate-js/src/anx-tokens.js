// Dart 侧 changeStyle({..., tokens}) 注入的阅读器 chrome 令牌（单一来源）。
// 默认值 = 改造前 foliate 内的硬编码值；宿主未注入时（debug.html 独立运行）行为不变。
export const DEFAULT_TOKENS = {
  chromeRadiusXs: 2,
  chromeRadiusSm: 4,
  codeBlockRadius: 6,
  inlineCodeRadius: 3,
  overlayFontSize: 24,
  searchOutlineColor: '#39c5bbaa',
  searchHighlightColor: '#39c5bc83',
}

const CSS_VARS = [
  ['chromeRadiusXs', '--anx-chrome-radius-xs', 'px'],
  ['chromeRadiusSm', '--anx-chrome-radius-sm', 'px'],
  ['codeBlockRadius', '--anx-code-block-radius', 'px'],
  ['inlineCodeRadius', '--anx-inline-code-radius', 'px'],
  ['overlayFontSize', '--anx-overlay-font-size', 'px'],
  ['searchOutlineColor', '--anx-search-outline-color', ''],
  ['searchHighlightColor', '--anx-search-highlight-color', ''],
]

// 过滤 null/undefined，避免产出 `nullpx` 使属性退到 initial 而非 var() 回退值。
const compact = tokens =>
  Object.fromEntries(Object.entries(tokens ?? {}).filter(([, v]) => v != null))

export const getTokens = () => ({ ...DEFAULT_TOKENS, ...compact(globalThis.__anxTokens) })

export const applyTokens = tokens => {
  const merged = { ...DEFAULT_TOKENS, ...compact(tokens) }
  // 保留全局是为了 debug 控制台可预置（debug.html 独立运行时可手动 window.__anxTokens = {...}）。
  globalThis.__anxTokens = merged
  const root = globalThis.document?.documentElement
  if (root) for (const [key, cssVar, unit] of CSS_VARS)
    root.style.setProperty(cssVar, `${merged[key]}${unit}`)
  return merged
}

export const tokensToRootCSS = tokens => {
  const merged = { ...DEFAULT_TOKENS, ...compact(tokens) }
  return `:root{${CSS_VARS.map(([key, cssVar, unit]) => `${cssVar}:${merged[key]}${unit}`).join(';')}}`
}
