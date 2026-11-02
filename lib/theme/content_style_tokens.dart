import 'package:flutter/material.dart';

class ReaderStyleTokens {
  const ReaderStyleTokens();

  double get fontSize => 1.4;
  double get fontWeight => 400;
  double get lineHeight => 1.8;
  double get letterSpacing => 0;
  double get wordSpacing => 0;
  double get paragraphSpacing => 1;
  double get sideMargin => 6;
  double get topMargin => 90;
  double get bottomMargin => 50;
  double get indent => 0;
  int get maxColumnCount => 0;
  double get headingFontSize => 1;
  double get columnThreshold => 720;
  String get fontFamily => 'Arial';
  String get backgroundColor => 'FFFBFBF3';
  String get textColor => 'FF343434';
  double get infoMargin => 20;
  double get infoFontSize => 10;

  // 阅读器 chrome（值与 foliate 现状一致，仅集中定义）。
  // 注意：两个 search 颜色是 CSS #RRGGBBAA 格式，直接注入 foliate，勿按 ARGB 解析；
  // backgroundColor/textColor 是既有 ARGB 无 # 格式，用途不同。
  double get chromeRadiusXs => 2;
  double get chromeRadiusSm => 4;
  double get codeBlockRadius => 6;
  double get inlineCodeRadius => 3;
  double get overlayFontSize => 24;
  String get searchOutlineColor => '#39c5bbaa';
  String get searchHighlightColor => '#39c5bc83';
}

/// 分享卡配色对：文字色 + 背景色。
@immutable
class SharePalette {
  const SharePalette({required this.text, required this.background});
  final Color text;
  final Color background;
}

class ShareStyleTokens {
  const ShareStyleTokens();

  double get outputWidth => 500;
  double get cornerRadius => 8;
  double get bodyFontSize => 18;
  double get accentFontSize => 38;
  double get captionFontSize => 16;
  double get cardPadding => 24;
  double get listSpacing => 8;
  double get pillRadius => 8;
  Color get imageOverlay => const Color(0xFFFFFFFF);
  Color get imageScrim => const Color(0x73000000);

  /// 用户可选的六组预设（与改造前逐一相同）。
  static const palettes = <SharePalette>[
    SharePalette(text: Color(0xFF000000), background: Color(0xFFFFFFFF)),
    SharePalette(text: Color(0xFFF6D995), background: Color(0xFF302C1C)),
    SharePalette(text: Color(0xFF000000), background: Color(0xFFFFECB3)),
    SharePalette(text: Color(0xFFFFFFFF), background: Color(0xFF37474F)),
    SharePalette(text: Color(0xFF000000), background: Color(0xFFFCE4EC)),
    SharePalette(text: Color(0xFFFFFFFF), background: Color(0xFF1A237E)),
  ];
}

class AppContentStyleTokens {
  const AppContentStyleTokens();

  static const tokens = AppContentStyleTokens();

  final reader = const ReaderStyleTokens();
  final share = const ShareStyleTokens();
}
