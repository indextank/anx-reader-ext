import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anx_reader/utils/font_parser.dart';

/// 字体名解析缓存回归：同一文件（size+mtime 未变）只解析一次，
/// 文件变化后缓存失效重解析。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('font-name-cache-');
    FontNameCache.debugClear();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File writeFont(String name, List<int> bytes) {
    final f = File(
      '${tempDir.path}${Platform.pathSeparator}$name',
    )..writeAsBytesSync(bytes);
    return f;
  }

  test('same file parses once and reuses cache on second call', () {
    final f = writeFont('a.ttf', List.filled(1024, 0));
    getFontNameFromFile(f);
    final hitsAfterFirst = FontNameCache.debugHitCount;
    expect(hitsAfterFirst, 0, reason: '首次应真实解析');

    getFontNameFromFile(f);
    expect(FontNameCache.debugHitCount, hitsAfterFirst + 1,
        reason: '第二次应命中缓存，不重复读文件');
  });

  test('cache invalidates when file size or mtime changes', () {
    final f = writeFont('b.ttf', List.filled(512, 0));
    getFontNameFromFile(f);
    expect(FontNameCache.debugHitCount, 0);

    // size 变化 → 失效
    f.writeAsBytesSync(List.filled(1024, 1));
    getFontNameFromFile(f);
    expect(FontNameCache.debugHitCount, 0, reason: '文件变化后应重新解析');

    getFontNameFromFile(f);
    expect(FontNameCache.debugHitCount, 1);
  });

  test('different files cached independently', () {
    final a = writeFont('c.ttf', List.filled(64, 0));
    final b = writeFont('d.ttf', List.filled(64, 0));
    getFontNameFromFile(a);
    getFontNameFromFile(b);
    getFontNameFromFile(a);
    getFontNameFromFile(b);
    expect(FontNameCache.debugHitCount, 2);
  });
}
