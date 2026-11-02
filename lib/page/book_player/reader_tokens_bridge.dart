import 'dart:convert';

import 'package:anx_reader/theme/content_style_tokens.dart';

/// 阅读器 chrome 令牌（键名与 anx-tokens.js 的 DEFAULT_TOKENS 一致，由
/// test/page/reader_tokens_bridge_test.dart 交叉校验）。
/// 首帧经 gererate_url.dart 的初始 style map 注入，后续经 epub_player.dart 的
/// changeStyle payload 注入，两处同一来源。
Map<String, Object> readerTokensMap(
        [ReaderStyleTokens t = const ReaderStyleTokens()]) =>
    {
      'chromeRadiusXs': t.chromeRadiusXs,
      'chromeRadiusSm': t.chromeRadiusSm,
      'codeBlockRadius': t.codeBlockRadius,
      'inlineCodeRadius': t.inlineCodeRadius,
      'overlayFontSize': t.overlayFontSize,
      'searchOutlineColor': t.searchOutlineColor,
      'searchHighlightColor': t.searchHighlightColor,
    };

/// changeStyle payload 片段：`tokens: {...}`（JSON 编码，无手工拼接转义顾虑）。
String readerTokensJs([ReaderStyleTokens t = const ReaderStyleTokens()]) =>
    'tokens: ${jsonEncode(readerTokensMap(t))}';
