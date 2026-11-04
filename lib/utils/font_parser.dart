import 'dart:io';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:flutter/foundation.dart';

Map<String, int> fontCache = {
  'en': 1033,
  'zh': 2052,
};

/// 字体名解析缓存：按 路径 + size + mtime 失效。
///
/// 解析需要整文件读入（CJK 字体常 10–20MB），样式面板每次构建都会
/// 列举字体目录，无缓存时打开面板会在 UI 线程重复同步读取全部字体
/// 文件，造成明显卡顿。
@visibleForTesting
class FontNameCache {
  FontNameCache._();

  static final _entries = <String, _CacheEntry>{};

  @visibleForTesting
  static int debugHitCount = 0;

  @visibleForTesting
  static void debugClear() {
    _entries.clear();
    debugHitCount = 0;
  }

  static String? lookup(String path, int length, int mtimeMs) {
    final e = _entries[path];
    if (e == null || e.length != length || e.mtimeMs != mtimeMs) return null;
    debugHitCount++;
    return e.name;
  }

  static void store(String path, int length, int mtimeMs, String name) {
    _entries[path] = _CacheEntry(length, mtimeMs, name);
  }
}

class _CacheEntry {
  const _CacheEntry(this.length, this.mtimeMs, this.name);

  final int length;
  final int mtimeMs;
  final String name;
}

String getFontNameFromFile(File file) {
  final stat = file.statSync();
  final cached = FontNameCache.lookup(
    file.absolute.path,
    stat.size,
    stat.modified.millisecondsSinceEpoch,
  );
  if (cached != null) return cached;
  final name = _parseFontName(file);
  FontNameCache.store(
    file.absolute.path,
    stat.size,
    stat.modified.millisecondsSinceEpoch,
    name,
  );
  return name;
}

String _parseFontName(File file) {
  Uint8List fontData;
  try {
    fontData = file.readAsBytesSync();
  } catch (_) {
    return 'Invalid font file';
  }
  final fallback =
      file.path.split(Platform.pathSeparator).last.split('.').first;
  try {
    final parsed = _parseFontNameBytes(fontData);
    return parsed.isEmpty ? fallback : parsed;
  } on RangeError catch (_) {
    // 损坏/非完整字体文件：越界读当无效处理，避免炸开面板。
    return fallback;
  }
}

String _parseFontNameBytes(Uint8List fontData) {
  int? nameTableOffset = _getNameTableOffset(fontData);

  if (nameTableOffset == null) {
    return 'Invalid font file';
  }

  int count = _readUint16(fontData, nameTableOffset + 2);
  int stringOffset = _readUint16(fontData, nameTableOffset + 4);
  String languageCode =
      Prefs().locale?.languageCode ?? Platform.localeName.split('_').first;
  int specifiedLanguageId = fontCache[languageCode] ?? fontCache['en']!;

  for (int i = 0; i < count; i++) {
    int recordOffset = nameTableOffset + 6 + i * 12;

    int platformID = _readUint16(fontData, recordOffset);
    int languageID = _readUint16(fontData, recordOffset + 4);
    int nameID = _readUint16(fontData, recordOffset + 6);

    if (nameID == 1 && platformID == 3 && languageID == specifiedLanguageId) {
      int length = _readUint16(fontData, recordOffset + 8);
      int offset = _readUint16(fontData, recordOffset + 10);

      return _readUnicodeString(
          fontData, nameTableOffset + stringOffset + offset, length);
    }
  }

  return '';
}

String _readUnicodeString(Uint8List data, int offset, int length) {
  List<int> codeUnits = [];
  for (int i = 0; i < length; i += 2) {
    codeUnits.add((data[offset + i] << 8) | data[offset + i + 1]);
  }
  return String.fromCharCodes(codeUnits);
}

int? _getNameTableOffset(Uint8List fontData) {
  int numTables = _readUint16(fontData, 4);

  for (int i = 0; i < numTables; i++) {
    int offset = 12 + i * 16;
    String tag = String.fromCharCodes(fontData.sublist(offset, offset + 4));

    if (tag == 'name') {
      return _readUint32(fontData, offset + 8);
    }
  }

  return null;
}

int _readUint16(Uint8List data, int offset) {
  return (data[offset] << 8) | data[offset + 1];
}

int _readUint32(Uint8List data, int offset) {
  return (data[offset] << 24) |
      (data[offset + 1] << 16) |
      (data[offset + 2] << 8) |
      data[offset + 3];
}
