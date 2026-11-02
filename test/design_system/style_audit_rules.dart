/// 样式审计判定规则（与 style_literal_audit_test.dart 共用）。
/// JS 侧：先剥离 calc(Npx * var(--scale-factor)) 缩放写法，再剥离 var() 整体，然后判定；
/// 十六进制颜色判违规；绝对 px 仅 |n| >= 2 判违规（0 / ±1px 为结构重置或边框补偿；
/// em/rem/% 为相对单位；仅 `calc(Npx * var(--scale-factor))` 这一种随页面缩放的写法豁免，
/// 其他 calc（如 calc(100% - 16px)）内的绝对 px 仍判违规）。
final dartPatterns = <RegExp>[
  RegExp(r'\bColor\s*\(\s*0x[0-9a-fA-F]+'),
  RegExp(r'\bColors\.[A-Za-z_]'),
  RegExp(r'\bfontSize\s*:\s*-?\d'),
  RegExp(r'\bEdgeInsets(?:Directional)?\.(?:all|only|symmetric|fromLTRB)\s*\('),
  RegExp(r'\bBorderRadius\.(?:circular|vertical|horizontal|only)\s*\('),
];

final jsColorPattern =
    RegExp(r'(?:color|background(?:-color)?)\s*:\s*[\x27"]?#[0-9a-fA-F]{3,8}');
final jsPxPattern = RegExp(
    r'(?:font-size|padding|margin|border-radius)\s*:\s*[^;\n]*?(-?\d+(?:\.\d+)?)px');
final _varGroup = RegExp(r'var\(--[a-zA-Z0-9-]+(?:,[^)]*)?\)');
final _scaledCalcGroup =
    RegExp(r'calc\(\s*-?\d+(?:\.\d+)?px\s*\*\s*var\(--scale-factor\)\s*\)');

bool isJsViolation(String rawLine) {
  // 缩放 calc 内含 var(--scale-factor)，必须先于 var() 剥离，否则 var 先被折叠导致无法识别。
  final line = rawLine
      .replaceAll(_scaledCalcGroup, 'calc()')
      .replaceAll(_varGroup, 'var()');
  if (jsColorPattern.hasMatch(line)) return true;
  for (final m in jsPxPattern.allMatches(line)) {
    final n = double.tryParse(m.group(1) ?? '');
    if (n != null && n.abs() >= 2) return true;
  }
  return false;
}

bool isDartViolation(String line) => dartPatterns.any((p) => p.hasMatch(line));

/// Dart 业务算法白名单（路径用 `/` 分隔 → 理由）。
const dartBusinessAllowlist = <String, String>{
  'lib/models/tag.dart': '数据库颜色整数与 Color 互转的位掩码算法，非样式',
  'lib/utils/color/rgb.dart': 'RGB 清洗/转换算法，非样式',
};

/// JS 令牌单一来源，与 lib/theme 同等豁免。
const jsTokenSource = 'anx-tokens.js';
