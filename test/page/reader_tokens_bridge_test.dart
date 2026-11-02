import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/page/book_player/reader_tokens_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

const _legacyTokens = <String, Object>{
  'chromeRadiusXs': 2.0,
  'chromeRadiusSm': 4.0,
  'codeBlockRadius': 6.0,
  'inlineCodeRadius': 3.0,
  'overlayFontSize': 24.0,
  'searchOutlineColor': '#39c5bbaa',
  'searchHighlightColor': '#39c5bc83',
};

void main() {
  test('dart payload keys equal anx-tokens.js DEFAULT_TOKENS keys', () {
    final js = File('assets/foliate-js/src/anx-tokens.js').readAsStringSync();
    final block = js.split('DEFAULT_TOKENS = {')[1].split('}')[0];
    final jsKeys = RegExp(r'^\s*([a-zA-Z]+)\s*:', multiLine: true)
        .allMatches(block)
        .map((m) => m.group(1)!)
        .toSet();
    // 兼容 JSON 带引号键与 JS 裸键两种写法。
    final dartKeys = RegExp(r'"?([a-zA-Z]+)"?\s*:')
        .allMatches(readerTokensJs())
        .map((m) => m.group(1)!)
        .where((k) => k != 'tokens')
        .toSet();
    expect(dartKeys, jsKeys);
    expect(readerTokensMap().keys.toSet(), jsKeys);
    expect(jsKeys.length, 7);
  });

  test('readerTokensMap carries legacy values verbatim', () {
    expect(readerTokensMap(), _legacyTokens);
  });

  test('readerTokensJs is `tokens: {json}` and round-trips to the same map',
      () {
    final s = readerTokensJs();
    expect(s, startsWith('tokens: {'));
    expect(s, endsWith('}'));
    final decoded = jsonDecode(s.substring('tokens: '.length));
    expect(decoded, _legacyTokens);
  });

  test('dist bundle embeds anx css vars', () {
    final hit = Directory('assets/foliate-js/dist')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.js'))
        .any((f) => f.readAsStringSync().contains('--anx-chrome-radius-sm'));
    expect(hit, isTrue, reason: 'dist 未重建或桥接缺失');
  });

  test('epub_player sends tokens in changeStyle payload', () {
    final src =
        File('lib/page/book_player/epub_player.dart').readAsStringSync();
    expect(src, contains('readerTokensJs()'));
  });

  test('gererate_url seeds tokens into the first-frame style map', () {
    final src = File('lib/utils/webView/gererate_url.dart').readAsStringSync();
    expect(src, contains('readerTokensMap()'));
  });

  test('getCSS template keeps @namespace before the token :root block', () {
    // CSS 规范要求 @namespace 位于所有样式规则之前，否则整条被忽略，
    // 连带 aside[epub|type~="footnote"]{display:none} 失效（EPUB3 脚注回归）。
    final src = File('assets/foliate-js/src/book.js').readAsStringSync();
    final getCss = src.indexOf('const getCSS = (');
    expect(getCss, greaterThanOrEqualTo(0));
    final templateOpen = src.indexOf(RegExp(r'return `\s*\n'), getCss);
    expect(templateOpen, greaterThanOrEqualTo(0));
    final body = src.substring(templateOpen + 'return `'.length);
    expect(body.trimLeft().startsWith('@namespace'), isTrue,
        reason: '@namespace 必须是 getCSS 模板的首个非空 token');
    final ns = src.indexOf('@namespace epub', templateOpen);
    final tok = src.indexOf(r'${tokensToRootCSS(tokens)}', templateOpen);
    expect(ns, greaterThanOrEqualTo(0));
    expect(tok, greaterThan(ns), reason: '令牌 :root{} 块必须位于 @namespace 之后');
  });
}
