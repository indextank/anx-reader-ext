# WebDAV 设置同步实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 在现有 WebDAV 同步之上，增加端到端加密的应用设置同步（含 AI 配置与服务密钥），按类别合并、默认开启、可排除、失败零影响。

**架构：** 新增三个单元——`SettingsSyncCrypto`（PBKDF2 派生密钥 + AES-256-GCM 加解密与文件封包）、`SettingsSyncCatalog`（类别→pref 键目录与采集）、`SettingsSyncManager`（编排：采集→比对远端→LWW 合并→应用→回写）。挂接在 `Sync.syncData()` 的 `syncFiles()` 之后，独立 try-catch。远端新增单文件 `anx/settings.v1.enc`。

**技术栈：** Flutter/Dart、`cryptography` ^2.7.0（纯 Dart）、SharedPreferences、现有 `SyncClientBase`。

**规格：** `docs/superpowers/specs/2026-10-31-webdav-settings-sync-design.md`（已批准；实现期修订：account 类别取消，共 6 类；状态存哈希非完整快照）。

---

## 文件结构

| 文件 | 操作 | 职责 |
| --- | --- | --- |
| `pubspec.yaml` | 修改 | 添加 `cryptography: ^2.7.0` |
| `lib/config/shared_preference_provider.dart` | 修改 | 新增 `settingsSyncEnabled`/`settingsSyncExcludedCategories`；提取静态 `encodePrefsEntry`/`applyPrefsEntry` |
| `lib/service/sync/settings_sync_crypto.dart` | 创建 | 密钥派生、加解密、二进制文件格式 |
| `lib/service/sync/settings_sync_catalog.dart` | 创建 | 类别枚举、键目录、排除清单、采集 |
| `lib/service/sync/settings_sync_manager.dart` | 创建 | 合并纯函数 + sync 编排 |
| `lib/providers/sync.dart` | 修改 | 挂接设置同步 |
| `lib/page/settings_page/sync.dart` | 修改 | 「设置同步」设置区块 |
| `lib/l10n/app_en.arb`、`app_zh.arb`、`app_zh-CN.arb`、`app_zh-TW.arb` | 修改 | 新增 9 个键 |
| `test/config/prefs_settings_sync_test.dart` | 创建 | Prefs 新键 + encode/apply helper 测试 |
| `test/service/sync/settings_sync_crypto_test.dart` | 创建 | 加密单元测试 |
| `test/service/sync/settings_sync_catalog_test.dart` | 创建 | 目录单元测试 |
| `test/service/sync/in_memory_sync_client.dart` | 创建 | 测试用内存 SyncClientBase |
| `test/service/sync/settings_sync_manager_test.dart` | 创建 | 合并与编排测试 |

**类型契约**（全计划一致，不得偏离）：

```dart
// settings_sync_catalog.dart
enum SettingsSyncCategory { appearance, reading, tts, translate, ai, advanced }

// Prefs（静态）
static Map<String, Object?>? encodePrefsEntry(Object? value);
static Future<bool> applyPrefsEntry(SharedPreferences prefs, String key, Map<dynamic, dynamic> entry);

// settings_sync_crypto.dart
static Future<List<int>> deriveSalt(String username);
static Future<Uint8List> encrypt(List<int> clearText, {required String password, required String username, int iterations});
static Future<List<int>> decrypt(List<int> payload, {required String password, int iterations});

// settings_sync_manager.dart
SettingsSyncManager({SyncClientBase? client, int kdfIterations, void Function(String)? onUserMessage, String? tempDirPath});
Future<void> sync(SyncDirection direction);
(Map<String, Map<String, dynamic>>, Map<String, Map<String, dynamic>>) mergeCategories({required Map<String, Map<String, dynamic>> local, required Map<String, dynamic> remote, required Set<String> excluded});
Future<String> canonicalJsonHash(Object? value);
```

payload/远端 JSON 结构（value 编码复用备份 schema 的 `{type, value}`）：

```json
{ "version": 1, "categories": { "ai": { "updatedAt": 1730000000000, "keys": { "aiRpm": {"type":"int","value":10} } } } }
```

本地状态键 `settingsSyncState`：`{"ai": {"updatedAt": 1730000000000, "hash": "<sha256-hex>"}}`。

测试环境约定（所有测试文件）：`SharedPreferences.setMockInitialValues({...})` 后 `await Prefs().initPrefs()`；Prefs 为单例，每个 `test()` 内重新初始化。

---

### 任务 1：提交设计文档修订

**文件：**
- 修改：`docs/superpowers/specs/2026-10-31-webdav-settings-sync-design.md`（已在计划编写时更新：account 类别取消、哈希状态）

- [x] **步骤 1：Commit 设计修订**

```bash
git add docs/superpowers/specs/2026-10-31-webdav-settings-sync-design.md
git commit -m "docs: revise settings sync spec (6 categories, hash-based state)"
```

---

### 任务 2：依赖与 Prefs 新键

**文件：**
- 修改：`pubspec.yaml`
- 修改：`lib/config/shared_preference_provider.dart`（追加到类尾部 `customSearchEngines` setter 之后、类结束 `}` 之前，即原 1735 行附近）
- 测试：`test/config/prefs_settings_sync_test.dart`

- [ ] **步骤 1：添加依赖**

`pubspec.yaml` dependencies 中 `shared_preferences: ^2.2.2` 行后添加：

```yaml
  cryptography: ^2.7.0
```

运行：`flutter pub get`，预期成功。

- [ ] **步骤 2：编写失败的测试**

创建 `test/config/prefs_settings_sync_test.dart`：

```dart
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  group('settingsSyncEnabled', () {
    test('defaults to true', () {
      expect(Prefs().settingsSyncEnabled, isTrue);
    });

    test('persists', () {
      Prefs().settingsSyncEnabled = false;
      expect(Prefs().prefs.getBool('settingsSyncEnabled'), isFalse);
      expect(Prefs().settingsSyncEnabled, isFalse);
    });
  });

  group('settingsSyncExcludedCategories', () {
    test('defaults to empty', () {
      expect(Prefs().settingsSyncExcludedCategories, isEmpty);
    });

    test('persists', () {
      Prefs().settingsSyncExcludedCategories = ['ai', 'tts'];
      expect(Prefs().settingsSyncExcludedCategories, ['ai', 'tts']);
    });
  });
}
```

- [ ] **步骤 3：运行测试验证失败**

运行：`flutter test test/config/prefs_settings_sync_test.dart`
预期：FAIL，`settingsSyncEnabled` getter 未定义。

- [ ] **步骤 4：实现**

在 `lib/config/shared_preference_provider.dart` 的 `Prefs` 类内（`deleteCustomSearchEngine` 方法后、类闭合 `}` 前）添加：

```dart
  // ---- Settings sync (anx/settings.v1.enc) ----

  bool get settingsSyncEnabled {
    return prefs.getBool('settingsSyncEnabled') ?? true;
  }

  set settingsSyncEnabled(bool enabled) {
    prefs.setBool('settingsSyncEnabled', enabled);
    notifyListeners();
  }

  List<String> get settingsSyncExcludedCategories {
    return prefs.getStringList('settingsSyncExcludedCategories') ?? [];
  }

  set settingsSyncExcludedCategories(List<String> categories) {
    prefs.setStringList('settingsSyncExcludedCategories', categories);
    notifyListeners();
  }
```

- [ ] **步骤 5：运行测试验证通过**

运行：`flutter test test/config/prefs_settings_sync_test.dart`
预期：PASS（4 个测试）。

- [ ] **步骤 6：Commit**

```bash
git add pubspec.yaml pubspec.lock lib/config/shared_preference_provider.dart test/config/prefs_settings_sync_test.dart
git commit -m "feat(sync): add settings sync prefs keys and cryptography dependency"
```

---

### 任务 3：提取 Prefs 编解码 helper

现有 `buildPrefsBackupMap` 内局部函数 `encodePrefsBackupEntry` 与 `applyPrefsBackupMap` 的类型分发逻辑被设置同步复用。提取为静态方法，行为不变。

**文件：**
- 修改：`lib/config/shared_preference_provider.dart:83-170`（`buildPrefsBackupMap`/`applyPrefsBackupMap`）
- 测试：`test/config/prefs_settings_sync_test.dart`（追加）

- [ ] **步骤 1：编写失败的测试**

在 `test/config/prefs_settings_sync_test.dart` 的 `main()` 内追加：

```dart
  group('encodePrefsEntry', () {
    test('encodes each supported type', () {
      expect(Prefs.encodePrefsEntry(true),
          {'type': 'bool', 'value': true});
      expect(Prefs.encodePrefsEntry(42), {'type': 'int', 'value': 42});
      expect(Prefs.encodePrefsEntry(1.5), {'type': 'double', 'value': 1.5});
      expect(Prefs.encodePrefsEntry('x'), {'type': 'string', 'value': 'x'});
      expect(Prefs.encodePrefsEntry(<String>['a', 'b']),
          {'type': 'stringList', 'value': ['a', 'b']});
      expect(Prefs.encodePrefsEntry(<dynamic>[1, 'a']), isNull);
      expect(Prefs.encodePrefsEntry(<String, String>{'k': 'v'}), isNull);
    });
  });

  group('applyPrefsEntry', () {
    test('writes each supported type', () async {
      final prefs = Prefs().prefs;
      expect(
          await Prefs.applyPrefsEntry(
              prefs, 'k1', {'type': 'bool', 'value': true}),
          isTrue);
      expect(
          await Prefs.applyPrefsEntry(
              prefs, 'k2', {'type': 'int', 'value': 7}),
          isTrue);
      expect(
          await Prefs.applyPrefsEntry(
              prefs, 'k3', {'type': 'double', 'value': 9}),
          isTrue);
      expect(
          await Prefs.applyPrefsEntry(
              prefs, 'k4', {'type': 'string', 'value': 'v'}),
          isTrue);
      expect(
          await Prefs.applyPrefsEntry(prefs, 'k5',
              {'type': 'stringList', 'value': <String>['a']}),
          isTrue);
      expect(prefs.getBool('k1'), isTrue);
      expect(prefs.getInt('k2'), 7);
      expect(prefs.getDouble('k3'), 9.0);
      expect(prefs.getString('k4'), 'v');
      expect(prefs.getStringList('k5'), ['a']);
    });

    test('rejects wrong types and unknown tags', () async {
      final prefs = Prefs().prefs;
      expect(
          await Prefs.applyPrefsEntry(
              prefs, 'b1', {'type': 'bool', 'value': 'not-bool'}),
          isFalse);
      expect(
          await Prefs.applyPrefsEntry(
              prefs, 'b2', {'type': 'nope', 'value': 1}),
          isFalse);
      expect(prefs.containsKey('b1'), isFalse);
      expect(prefs.containsKey('b2'), isFalse);
    });
  });
```

- [ ] **步骤 2：运行测试验证失败**

运行：`flutter test test/config/prefs_settings_sync_test.dart`
预期：FAIL，`encodePrefsEntry` 未定义。

- [ ] **步骤 3：实现**

在 `Prefs` 类内（`settingsSyncExcludedCategories` setter 后）添加静态方法；并重写 `buildPrefsBackupMap`/`applyPrefsBackupMap` 复用它们（替换原 83-170 行的两个方法体，保持外部行为不变）：

```dart
  /// Encode a pref value into the backup schema `{type, value}` map.
  /// Returns null for values that cannot be represented.
  static Map<String, Object?>? encodePrefsEntry(Object? value) {
    if (value is bool) {
      return <String, Object?>{'type': 'bool', 'value': value};
    }
    if (value is int) {
      return <String, Object?>{'type': 'int', 'value': value};
    }
    if (value is double) {
      return <String, Object?>{'type': 'double', 'value': value};
    }
    if (value is String) {
      return <String, Object?>{'type': 'string', 'value': value};
    }
    if (value is List) {
      final bool allStrings =
          value.every((dynamic element) => element is String);
      if (allStrings) {
        return <String, Object?>{
          'type': 'stringList',
          'value': List<String>.from(value, growable: false),
        };
      }
    }
    return null;
  }

  /// Apply a backup-schema entry to [prefs]. Returns false (and writes
  /// nothing) when the tag is unknown or the value type does not match.
  static Future<bool> applyPrefsEntry(
    SharedPreferences prefs,
    String key,
    Map<dynamic, dynamic> entry,
  ) async {
    final dynamic type = entry['type'];
    final dynamic value = entry['value'];
    if (type is! String) return false;
    switch (type) {
      case 'bool':
        if (value is bool) {
          await prefs.setBool(key, value);
          return true;
        }
      case 'int':
        if (value is int) {
          await prefs.setInt(key, value);
          return true;
        }
      case 'double':
        if (value is num) {
          await prefs.setDouble(key, value.toDouble());
          return true;
        }
      case 'string':
        if (value is String) {
          await prefs.setString(key, value);
          return true;
        }
      case 'stringList':
        if (value is List && value.every((dynamic e) => e is String)) {
          await prefs.setStringList(key, List<String>.from(value));
          return true;
        }
    }
    return false;
  }
```

重写后的两个既有方法：

```dart
  Future<Map<String, dynamic>> buildPrefsBackupMap() async {
    final Map<String, dynamic> backup = <String, dynamic>{
      prefsBackupVersionKey: prefsBackupSchemaVersion,
    };
    for (final String key in prefs.getKeys()) {
      final Map<String, Object?>? encoded =
          encodePrefsEntry(prefs.get(key));
      if (encoded != null) {
        backup[key] = encoded;
      }
    }
    return backup;
  }

  Future<void> applyPrefsBackupMap(Map<String, dynamic> backup) async {
    for (final MapEntry<String, dynamic> entry in backup.entries) {
      final String key = entry.key;
      if (key == prefsBackupVersionKey || _prefsImportSkipKeys.contains(key)) {
        continue;
      }
      final dynamic entryValue = entry.value;
      if (entryValue is! Map) continue;
      await applyPrefsEntry(prefs, key, entryValue);
    }
    notifyListeners();
  }
```

注意：原 `applyPrefsBackupMap` 末尾若无 `notifyListeners()` 则不添加（对照原实现保持行为一致；原实现在循环后结束，无需通知则维持原样——以仓库当前代码为准，若原本无通知则删去最后一行）。

- [ ] **步骤 4：运行测试验证通过**

运行：`flutter test test/config/prefs_settings_sync_test.dart`
预期：PASS（全部）。

- [ ] **步骤 5：Commit**

```bash
git add lib/config/shared_preference_provider.dart test/config/prefs_settings_sync_test.dart
git commit -m "refactor(prefs): extract encode/apply prefs entry helpers"
```

---

### 任务 4：SettingsSyncCrypto

**文件：**
- 创建：`lib/service/sync/settings_sync_crypto.dart`
- 测试：`test/service/sync/settings_sync_crypto_test.dart`

- [ ] **步骤 1：编写失败的测试**

```dart
import 'dart:convert';

import 'package:anx_reader/service/sync/settings_sync_crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const password = 'p@ssw0rd-密码';
  const username = 'reader@example.com';
  const iterations = 1000; // keep tests fast

  test('deriveSalt is deterministic and 16 bytes', () async {
    final a = await SettingsSyncCrypto.deriveSalt(username);
    final b = await SettingsSyncCrypto.deriveSalt(username);
    final other = await SettingsSyncCrypto.deriveSalt('other');
    expect(a.length, 16);
    expect(a, b);
    expect(a, isNot(other));
  });

  test('encrypt/decrypt roundtrip', () async {
    final clear = utf8.encode('{"version":1,"categories":{}}');
    final payload = await SettingsSyncCrypto.encrypt(
      clear,
      password: password,
      username: username,
      iterations: iterations,
    );
    final decrypted = await SettingsSyncCrypto.decrypt(
      payload,
      password: password,
      iterations: iterations,
    );
    expect(decrypted, clear);
  });

  test('file format: magic + salt + nonce + ciphertext + mac', () async {
    final payload = await SettingsSyncCrypto.encrypt(
      utf8.encode('hello'),
      password: password,
      username: username,
      iterations: iterations,
    );
    expect(payload.sublist(0, 7), [0x41, 0x4E, 0x58, 0x53, 0x45, 0x54, 0x31]);
    expect(payload.length, 7 + 16 + 12 + 5 + 16);
  });

  test('wrong password throws SecretBoxAuthenticationError', () async {
    final payload = await SettingsSyncCrypto.encrypt(
      utf8.encode('hello'),
      password: password,
      username: username,
      iterations: iterations,
    );
    await expectLater(
      SettingsSyncCrypto.decrypt(
        payload,
        password: 'wrong',
        iterations: iterations,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('tampered magic throws FormatException', () async {
    final payload = await SettingsSyncCrypto.encrypt(
      utf8.encode('hello'),
      password: password,
      username: username,
      iterations: iterations,
    );
    payload[0] = 0x00;
    await expectLater(
      SettingsSyncCrypto.decrypt(
        payload,
        password: password,
        iterations: iterations,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('truncated payload throws FormatException', () async {
    await expectLater(
      SettingsSyncCrypto.decrypt(
        List<int>.filled(10, 0),
        password: password,
        iterations: iterations,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`flutter test test/service/sync/settings_sync_crypto_test.dart`
预期：FAIL，文件不存在（编译错误）。

- [ ] **步骤 3：实现**

创建 `lib/service/sync/settings_sync_crypto.dart`：

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Encrypts/decrypts the settings sync payload with AES-256-GCM.
///
/// The key is derived from the WebDAV password with PBKDF2-SHA256 and a
/// deterministic per-account salt, so every device using the same WebDAV
/// account derives the same key without extra configuration.
///
/// File layout: `magic(7) | kdfSalt(16) | nonce(12) | ciphertext || tag(16)`.
class SettingsSyncCrypto {
  SettingsSyncCrypto._();

  /// "ANXSET1"
  static const List<int> magicHeader = [
    0x41, 0x4E, 0x58, 0x53, 0x45, 0x54, 0x31,
  ];
  static const int saltLength = 16;
  static const int nonceLength = 12;
  static const int macLength = 16;
  static const int defaultIterations = 210000;
  static const String _saltDomain = 'anx-reader-settings-sync-v1:';

  static final AesGcm _cipher = AesGcm.with256bits();
  static final Sha256 _sha256 = Sha256();

  /// Deterministic salt: first [saltLength] bytes of SHA-256(domain+username).
  static Future<List<int>> deriveSalt(String username) async {
    final digest =
        await _sha256.hash(utf8.encode('$_saltDomain$username'));
    return digest.bytes.sublist(0, saltLength);
  }

  static Future<SecretKey> deriveKey(
    String password,
    List<int> salt, {
    int iterations = defaultIterations,
  }) {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  static Future<Uint8List> encrypt(
    List<int> clearText, {
    required String password,
    required String username,
    int iterations = defaultIterations,
  }) async {
    final salt = await deriveSalt(username);
    final key = await deriveKey(password, salt, iterations: iterations);
    final secretBox = await _cipher.encrypt(
      clearText,
      secretKey: key,
      nonce: _cipher.newNonce(),
    );
    final builder = BytesBuilder();
    builder.add(magicHeader);
    builder.add(salt);
    builder.add(secretBox.nonce);
    builder.add(secretBox.cipherText);
    builder.add(secretBox.mac.bytes);
    return builder.toBytes();
  }

  /// Throws [FormatException] on bad header and
  /// [SecretBoxAuthenticationError] on wrong password or tampering.
  static Future<List<int>> decrypt(
    List<int> payload, {
    required String password,
    int iterations = defaultIterations,
  }) async {
    final int minLength =
        magicHeader.length + saltLength + nonceLength + macLength;
    if (payload.length <= minLength) {
      throw const FormatException('Settings sync payload too short');
    }
    for (var i = 0; i < magicHeader.length; i++) {
      if (payload[i] != magicHeader[i]) {
        throw const FormatException('Bad settings sync magic header');
      }
    }
    var offset = magicHeader.length;
    final salt = payload.sublist(offset, offset + saltLength);
    offset += saltLength;
    final nonce = payload.sublist(offset, offset + nonceLength);
    offset += nonceLength;
    final cipherText =
        payload.sublist(offset, payload.length - macLength);
    final mac = payload.sublist(payload.length - macLength);
    final key = await deriveKey(password, salt, iterations: iterations);
    return _cipher.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
    );
  }
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：`flutter test test/service/sync/settings_sync_crypto_test.dart`
预期：PASS（6 个测试）。

- [ ] **步骤 5：Commit**

```bash
git add lib/service/sync/settings_sync_crypto.dart test/service/sync/settings_sync_crypto_test.dart
git commit -m "feat(sync): add AES-256-GCM crypto for settings sync"
```

---

### 任务 5：SettingsSyncCatalog

**文件：**
- 创建：`lib/service/sync/settings_sync_catalog.dart`
- 测试：`test/service/sync/settings_sync_catalog_test.dart`

- [ ] **步骤 1：编写失败的测试**

```dart
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/sync/settings_sync_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'themeColor': 4280391411,
      'locale': 'zh',
      'readStyle': '{"fontSize":18}',
      'aiProviders': '[{"id":"p1","apiKeys":[{"key":"sk-secret"}]}]',
      'aiPrompt_translate': 'Translate this',
      'ttsVoiceModel_ms': 'zh-CN-Xiaoxiao',
      'translateServiceConfig_deepl': '{"api_key":"secret"}',
      'customStoragePath': '/device/specific',
      'webdavInfo': '{"url":"https://dav","username":"u","password":"p"}',
      'httpProxyHost': '127.0.0.1',
      'settingsSyncState': '{}',
      'unknownFutureKey': 'x',
    });
    await Prefs().initPrefs();
  });

  test('exact keys map to categories', () {
    expect(SettingsSyncCatalog.categoryOf('themeColor'),
        SettingsSyncCategory.appearance);
    expect(SettingsSyncCatalog.categoryOf('readStyle'),
        SettingsSyncCategory.reading);
    expect(SettingsSyncCatalog.categoryOf('aiProviders'),
        SettingsSyncCategory.ai);
  });

  test('prefix keys map to categories', () {
    expect(SettingsSyncCatalog.categoryOf('aiPrompt_translate'),
        SettingsSyncCategory.ai);
    expect(SettingsSyncCatalog.categoryOf('ttsVoiceModel_ms'),
        SettingsSyncCategory.tts);
    expect(SettingsSyncCatalog.categoryOf('translateServiceConfig_deepl'),
        SettingsSyncCategory.translate);
    expect(SettingsSyncCatalog.categoryOf('onlineTtsConfig_aliyun'),
        SettingsSyncCategory.tts);
  });

  test('never-sync keys return null', () {
    expect(SettingsSyncCatalog.categoryOf('webdavInfo'), isNull);
    expect(SettingsSyncCatalog.categoryOf('customStoragePath'), isNull);
    expect(SettingsSyncCatalog.categoryOf('httpProxyHost'), isNull);
    expect(SettingsSyncCatalog.categoryOf('settingsSyncState'), isNull);
    expect(SettingsSyncCatalog.categoryOf('autoSync'), isNull);
  });

  test('unmapped keys return null', () {
    expect(SettingsSyncCatalog.categoryOf('unknownFutureKey'), isNull);
  });

  test('collect groups values with type tags', () {
    final collected =
        SettingsSyncCatalog.collect(Prefs().prefs, excluded: const {});
    expect(collected['appearance']!['themeColor'],
        {'type': 'int', 'value': 4280391411});
    expect(collected['ai']!['aiPrompt_translate'],
        {'type': 'string', 'value': 'Translate this'});
    expect(collected.containsKey('unknownFutureKey'), isFalse);
    // never-sync keys never appear anywhere
    for (final keys in collected.values) {
      expect(keys.containsKey('webdavInfo'), isFalse);
      expect(keys.containsKey('customStoragePath'), isFalse);
      expect(keys.containsKey('settingsSyncState'), isFalse);
    }
  });

  test('collect skips excluded categories', () {
    final collected = SettingsSyncCatalog.collect(Prefs().prefs,
        excluded: {SettingsSyncCategory.ai.name});
    expect(collected.containsKey('ai'), isFalse);
    expect(collected.containsKey('appearance'), isTrue);
  });

  test('every category contains at least one registered key', () {
    for (final category in SettingsSyncCategory.values) {
      expect(
        SettingsSyncCatalog.exactKeys[category]!.isNotEmpty ||
            SettingsSyncCatalog.keyPrefixes[category]!.isNotEmpty,
        isTrue,
        reason: '$category must not be empty',
      );
    }
  });
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`flutter test test/service/sync/settings_sync_catalog_test.dart`
预期：FAIL，文件不存在。

- [ ] **步骤 3：实现**

创建 `lib/service/sync/settings_sync_catalog.dart`：

```dart
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings sync categories. Keys not listed here are never synced.
enum SettingsSyncCategory { appearance, reading, tts, translate, ai, advanced }

/// Maps preference keys to sync categories and collects typed snapshots.
///
/// Unmapped keys are deliberately ignored: device-specific settings
/// (storage path, proxy, trust flags, sync state itself) must never leak
/// across devices, and new keys opt in explicitly.
class SettingsSyncCatalog {
  SettingsSyncCatalog._();

  static const Map<SettingsSyncCategory, List<String>> exactKeys = {
    SettingsSyncCategory.appearance: [
      'themeColor', 'locale', 'themeMode', 'trueDarkMode', 'eInkMode',
      'bgimg', 'bookCoverWidth', 'bookshelfFolderStyle',
      'showBookTitleOnDefaultCover', 'showAuthorOnDefaultCover',
      'openBookAnimation', 'showTextUnderIconButton',
      'useOriginalCoverRatio', 'sortField', 'sortOrder',
      'bottomNavigatorShowNote', 'bottomNavigatorShowStatistics',
      'bottomNavigatorShowAI',
    ],
    SettingsSyncCategory.reading: [
      'readStyle', 'readTheme', 'font', 'readingRules', 'readingInfo',
      'pageTurningType', 'pageTurnStyle', 'pageTurnMode',
      'customPageTurnConfig', 'annotationType', 'annotationColor',
      'volumeKeyTurnPage', 'keyboardShortcutTurnPage', 'swapPageTurnArea',
      'showMenuOnHover', 'showActionLabels', 'hideStatusBar',
      'autoHideBottomBar', 'awakeTime', 'useBookStyles',
      'pageHeaderMargin', 'pageHeaderLeftMargin', 'pageHeaderRightMargin',
      'pageHeaderFontSize', 'pageFooterMargin', 'pageFooterLeftMargin',
      'pageFooterRightMargin', 'pageFooterFontSize', 'writingMode',
      'notesViewSortField', 'notesViewSortDirection',
      'notesExportSortField', 'notesExportSortDirection',
      'notesExportMergeChapters', 'excerptShareTemplate',
      'excerptShareFont', 'excerptShareColorIndex',
      'excerptShareBgimgIndex', 'reduceVibrationFeedback',
    ],
    SettingsSyncCategory.tts: [
      'ttsService', 'isSystemTts', 'onlineTtsService',
      'ttsVolume', 'ttsPitch', 'ttsRate',
    ],
    SettingsSyncCategory.translate: [
      'translateService', 'translateFrom', 'translateTo',
      'autoTranslateSelection', 'autoMarkSelection',
      'fullTextTranslateService', 'fullTextTranslateFrom',
      'fullTextTranslateTo', 'translationMode', 'bookTranslationModes',
    ],
    SettingsSyncCategory.ai: [
      'aiProviders', 'selectedAiService', 'userPrompts', 'enabledAiTools',
      'aiRpm', 'maxAiCacheCount', 'aiChatFontSize', 'aiChatDisplayMode',
      'aiPanelWidth', 'aiPanelHeight', 'autoSummaryPreviousContent',
      'autoSummaryDelayLevel', 'autoAdjustReadingTheme',
    ],
    SettingsSyncCategory.advanced: [
      'clearLogWhenStart', 'enableJsForEpub', 'chapterSplitSelectedRuleId',
      'chapterSplitCustomRules', 'customCSSEnabled', 'customCSS',
      'statisticsDashboardTiles', 'searchEngines', 'selectedSearchEngineId',
      'searchDisplayMode',
    ],
  };

  static const Map<SettingsSyncCategory, List<String>> keyPrefixes = {
    SettingsSyncCategory.appearance: ['hint_'],
    SettingsSyncCategory.tts: ['ttsVoiceModel_', 'onlineTtsConfig_'],
    SettingsSyncCategory.translate: ['translateServiceConfig_'],
    SettingsSyncCategory.ai: ['aiPrompt_', 'aiConfig_'],
    SettingsSyncCategory.advanced: [],
    SettingsSyncCategory.reading: [],
  };

  /// Keys that must never be synced, whatever their shape.
  static const Set<String> neverSyncKeys = {
    // Sync plumbing and credentials of the sync target itself
    'webdavInfo', 'syncProtocol', 'webdavStatus', 'autoSync',
    'onlySyncWhenWifi', 'syncCompletedToast', 'lastUploadBookDate',
    // Device-specific
    'customStoragePath', 'trustUserCertificates', 'windowInfo',
    'developerOptionsEnabled', 'lastServerPort',
    // Ephemeral / book-instance state
    'lastShowUpdate', 'lastAppVersion', 'beginDate',
    'iapPurchaseStatus', 'iapLastCheckTime', '__prefsBackupVersion',
  };

  static const List<String> neverSyncPrefixes = [
    'settingsSync',
    'httpProxy',
    'lastAutoSummaryTimestamp_',
  ];

  /// Returns the category owning [key], or null when it must not sync.
  static SettingsSyncCategory? categoryOf(String key) {
    if (neverSyncKeys.contains(key)) return null;
    for (final prefix in neverSyncPrefixes) {
      if (key.startsWith(prefix)) return null;
    }
    for (final entry in exactKeys.entries) {
      if (entry.value.contains(key)) return entry.key;
    }
    for (final entry in keyPrefixes.entries) {
      for (final prefix in entry.value) {
        if (key.startsWith(prefix)) return entry.key;
      }
    }
    return null;
  }

  /// Collect current values into `{category.name: {key: {type, value}}}`.
  /// Categories named in [excluded] are skipped entirely.
  static Map<String, Map<String, Map<String, Object?>>> collect(
    SharedPreferences prefs, {
    Set<String> excluded = const {},
  }) {
    final result = <String, Map<String, Map<String, Object?>>>{};
    for (final String key in prefs.getKeys()) {
      final category = categoryOf(key);
      if (category == null) continue;
      if (excluded.contains(category.name)) continue;
      final encoded = Prefs.encodePrefsEntry(prefs.get(key));
      if (encoded == null) continue;
      result
          .putIfAbsent(
              category.name, () => <String, Map<String, Object?>>{})
          .putIfAbsent(key, () => <String, Object?>{...encoded});
    }
    return result;
  }
}
```

注意：`putIfAbsent(key, () => {...encoded})` 展开一层防御性拷贝；若 lint 报 map 字面量类型问题，改为 `Map<String, Object?>.from(encoded)`。

- [ ] **步骤 4：运行测试验证通过**

运行：`flutter test test/service/sync/settings_sync_catalog_test.dart`
预期：PASS（7 个测试）。

- [ ] **步骤 5：Commit**

```bash
git add lib/service/sync/settings_sync_catalog.dart test/service/sync/settings_sync_catalog_test.dart
git commit -m "feat(sync): add settings sync category catalog"
```

---

### 任务 6：Manager 合并纯函数

**文件：**
- 创建：`lib/service/sync/settings_sync_manager.dart`（本任务先只含纯函数）
- 测试：`test/service/sync/settings_sync_manager_test.dart`

- [ ] **步骤 1：编写失败的测试**

```dart
import 'package:anx_reader/service/sync/settings_sync_manager.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Map<String, Object?>> cat(int updatedAt,
        [Map<String, Map<String, Object?>>? keys]) =>
    {
      'updatedAt': updatedAt,
      'keys': keys ?? {},
    };

void main() {
  test('canonicalJsonHash is order-insensitive and stable', () async {
    final a = await canonicalJsonHash({
      'b': {'type': 'int', 'value': 2},
      'a': {'type': 'string', 'value': 'x'},
    });
    final b = await canonicalJsonHash({
      'a': {'type': 'string', 'value': 'x'},
      'b': {'type': 'int', 'value': 2},
    });
    final c = await canonicalJsonHash({
      'a': {'type': 'string', 'value': 'y'},
    });
    expect(a, b);
    expect(a, isNot(c));
    expect(a.length, 64);
  });

  group('mergeCategories', () {
    test('remote wins when strictly newer', () {
      final local = {
        'ai': cat(100, {
          'aiRpm': {'type': 'int', 'value': 10}
        })
      };
      final remote = <String, dynamic>{
        'ai': cat(200, {
          'aiRpm': {'type': 'int', 'value': 20}
        })
      };
      final (merged, remoteWon) = mergeCategories(
          local: local, remote: remote, excluded: const {});
      expect(merged['ai']!['updatedAt'], 200);
      expect(remoteWon.containsKey('ai'), isTrue);
    });

    test('local wins when newer or equal', () {
      for (final remoteTs in [50, 100]) {
        final local = {
          'ai': cat(100, {
            'aiRpm': {'type': 'int', 'value': 10}
          })
        };
        final remote = <String, dynamic>{
          'ai': cat(remoteTs, {
            'aiRpm': {'type': 'int', 'value': 20}
          })
        };
        final (merged, remoteWon) = mergeCategories(
            local: local, remote: remote, excluded: const {});
        expect(merged['ai']!['updatedAt'], 100);
        expect(remoteWon.containsKey('ai'), isFalse);
      }
    });

    test('remote-only category is taken and applied', () {
      final remote = <String, dynamic>{'ai': cat(5, {})};
      final (merged, remoteWon) = mergeCategories(
          local: {}, remote: remote, excluded: const {});
      expect(merged['ai']!['updatedAt'], 5);
      expect(remoteWon.containsKey('ai'), isTrue);
    });

    test('local-only category is kept and not applied', () {
      final local = {'ai': cat(5, {})};
      final (merged, remoteWon) = mergeCategories(
          local: local, remote: {}, excluded: const {});
      expect(merged['ai']!['updatedAt'], 5);
      expect(remoteWon.containsKey('ai'), isFalse);
    });

    test('excluded categories are dropped from merged', () {
      final local = {
        'ai': cat(100, {}),
        'tts': cat(100, {}),
      };
      final remote = <String, dynamic>{
        'ai': cat(50, {}),
        'tts': cat(500, {}),
      };
      final (merged, remoteWon) = mergeCategories(
          local: local, remote: remote, excluded: {'tts'});
      expect(merged.containsKey('tts'), isFalse);
      expect(remoteWon.containsKey('tts'), isFalse);
      expect(merged.containsKey('ai'), isTrue);
    });

    test('malformed remote entries are ignored', () {
      final local = {'ai': cat(100, {})};
      final remote = <String, dynamic>{
        'ai': 'not-a-map',
        'tts': {'noUpdatedAt': 'x'},
      };
      final (merged, remoteWon) = mergeCategories(
          local: local, remote: remote, excluded: const {});
      expect(merged['ai']!['updatedAt'], 100);
      expect(remoteWon.containsKey('ai'), isFalse);
      expect(merged.containsKey('tts'), isFalse);
    });
  });
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`flutter test test/service/sync/settings_sync_manager_test.dart`
预期：FAIL，文件不存在。

- [ ] **步骤 3：实现（纯函数部分）**

创建 `lib/service/sync/settings_sync_manager.dart`：

```dart
import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/service/sync/settings_sync_catalog.dart';
import 'package:anx_reader/service/sync/settings_sync_crypto.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SHA-256 hex of a canonical JSON encoding (recursively key-sorted) of
/// [value]. Insertion order never affects the result.
Future<String> canonicalJsonHash(Object? value) async {
  final digest = await Sha256().hash(utf8.encode(jsonEncode(_canonical(value))));
  return digest.bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((e) => e.toString()).toList()..sort();
    return <String, Object?>{
      for (final k in keys) k: _canonical(value[k]),
    };
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

/// Last-write-wins merge per category.
///
/// [local] maps `category -> {updatedAt: int, keys: {...}}`; [remote] is the
/// decoded remote document's `categories` map with the same value shape.
/// Remote wins only when strictly newer. Returns `(merged, remoteWon)` where
/// remoteWon holds the `category -> keys` that must be applied locally.
/// Excluded categories are absent from both results.
(Map<String, Map<String, dynamic>>, Map<String, Map<String, dynamic>>)
    mergeCategories({
  required Map<String, Map<String, dynamic>> local,
  required Map<String, dynamic> remote,
  required Set<String> excluded,
}) {
  final merged = <String, Map<String, dynamic>>{};
  final remoteWon = <String, Map<String, dynamic>>{};

  Map<String, dynamic>? normalizeRemote(dynamic value) {
    if (value is! Map) return null;
    final keys = value['keys'];
    if (keys is! Map) return null;
    return <String, dynamic>{
      'updatedAt': value['updatedAt'] is int ? value['updatedAt'] as int : 0,
      'keys': keys,
    };
  }

  for (final category in {...local.keys, ...remote.keys}) {
    if (excluded.contains(category)) continue;
    final localValue = local[category];
    final remoteValue = normalizeRemote(remote[category]);

    if (remoteValue == null) {
      if (localValue != null) merged[category] = localValue;
      continue;
    }
    if (localValue == null) {
      merged[category] = remoteValue;
      remoteWon[category] =
          Map<String, dynamic>.from(remoteValue['keys'] as Map);
      continue;
    }
    final int remoteTs = remoteValue['updatedAt'] as int;
    final int localTs =
        localValue['updatedAt'] is int ? localValue['updatedAt'] as int : 0;
    if (remoteTs > localTs) {
      merged[category] = remoteValue;
      remoteWon[category] =
          Map<String, dynamic>.from(remoteValue['keys'] as Map);
    } else {
      merged[category] = localValue;
    }
  }
  return (merged, remoteWon);
}
```

（任务 7 会在同一文件追加 `SettingsSyncManager` 类；本步骤文件暂不 import `dart:io`/`get_temp_dir`。）

- [ ] **步骤 4：运行测试验证通过**

运行：`flutter test test/service/sync/settings_sync_manager_test.dart`
预期：PASS（7 个测试）。

- [ ] **步骤 5：Commit**

```bash
git add lib/service/sync/settings_sync_manager.dart test/service/sync/settings_sync_manager_test.dart
git commit -m "feat(sync): add LWW merge and canonical hash for settings sync"
```

---

### 任务 7：Manager 编排与 InMemory 测试客户端

**文件：**
- 创建：`test/service/sync/in_memory_sync_client.dart`
- 修改：`lib/service/sync/settings_sync_manager.dart`（追加类）
- 测试：`test/service/sync/settings_sync_manager_test.dart`（追加）

- [ ] **步骤 1：创建 InMemory 测试客户端**

创建 `test/service/sync/in_memory_sync_client.dart`：

```dart
import 'dart:io' as io;

import 'package:anx_reader/models/remote_file.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:dio/dio.dart';

/// File-backed in-memory SyncClientBase for tests: writes go to a local
/// temp directory keyed by remote path, so upload/download round-trips work.
class InMemorySyncClient implements SyncClientBase {
  final io.Directory dir;
  final Map<String, List<int>> files = {};

  InMemorySyncClient(this.dir);

  io.File _file(String path) =>
      io.File('${dir.path}/${path.replaceAll('/', '_')}');

  @override
  Future<void> ping() async {}

  @override
  Future<void> testFullCapabilities() async {}

  @override
  Future<void> mkdirAll(String path) async {}

  @override
  Future<List<RemoteFile>> readDir(String path) async => [];

  @override
  Future<void> remove(String path) async {
    files.remove(path);
    final f = _file(path);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<bool> isExist(String path) async {
    if (files.containsKey(path)) return true;
    return _file(path).existsSync();
  }

  @override
  Future<void> uploadFile(String localPath, String remotePath,
      {bool replace = true,
      void Function(int sent, int total)? onProgress,
      CancelToken? cancelToken}) async {
    files[remotePath] = await io.File(localPath).readAsBytes();
    await _file(remotePath).writeAsBytes(files[remotePath]!);
  }

  @override
  Future<void> downloadFile(String remotePath, String localPath,
      {void Function(int received, int total)? onProgress}) async {
    await io.File(localPath).writeAsBytes(files[remotePath]!);
  }

  @override
  Future<List<RemoteFile>> safeReadDir(String path) async => [];

  @override
  Future<RemoteFile?> readProps(String path) async => null;

  @override
  String get protocolName => 'InMemory';

  @override
  Map<String, dynamic> get config => {};

  @override
  void updateConfig(Map<String, dynamic> newConfig) {}

  @override
  bool get isConfigured => true;
}
```

`RemoteFile` 模型若为 freezed 生成，`readProps`/`readDir` 返回空即可，无需构造实例。

- [ ] **步骤 2：编写失败的编排测试**

在 `test/service/sync/settings_sync_manager_test.dart` 顶部补充 import 并在 `main()` 内追加：

```dart
// 追加 import（文件顶部）：
// dart:io as io, package:anx_reader/config/shared_preference_provider.dart,
// package:anx_reader/enums/sync_direction.dart,
// package:anx_reader/service/sync/in_memory_sync_client.dart,
// package:shared_preferences/shared_preferences.dart

  late io.Directory tempDir;
  late InMemorySyncClient client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    tempDir = await io.Directory.systemTemp.createTemp('settings_sync_test');
    client = InMemorySyncClient(tempDir);
  });

  addTearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  SettingsSyncManager newManager() => SettingsSyncManager(
        client: client,
        kdfIterations: 1000,
        tempDirPath: tempDir.path,
      );

  Future<Map<String, dynamic>> remoteDoc() async {
    final bytes = client.files[SettingsSyncManager.remotePath]!;
    final clear = await SettingsSyncCrypto.decrypt(
      bytes,
      password: 'pw',
      iterations: 1000,
    );
    return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
  }

  Future<void> seedCredentials() async {
    SharedPreferences.setMockInitialValues({
      'webdavInfo': '{"url":"https://dav","username":"user","password":"pw"}',
    });
    await Prefs().initPrefs();
  }

  test('first sync uploads local settings encrypted', () async {
    await seedCredentials();
    Prefs().prefs.setInt('aiRpm', 10);
    await newManager().sync(SyncDirection.both);

    final doc = await remoteDoc();
    expect(doc['version'], SettingsSyncManager.payloadVersion);
    final ai = (doc['categories'] as Map<String, dynamic>)['ai'] as Map;
    expect((ai['keys'] as Map)['aiRpm'], {'type': 'int', 'value': 10});
    // Raw bytes must not leak plaintext keys.
    final raw = utf8.decode(client.files[SettingsSyncManager.remotePath]!,
        allowMalformed: true);
    expect(raw.contains('aiRpm'), isFalse);
  });

  test('download applies newer remote category', () async {
    await seedCredentials();
    // Seed a remote file from a "device A" state.
    Prefs().prefs.setInt('aiRpm', 10);
    await newManager().sync(SyncDirection.both);
    // Mutate remote directly: bump updatedAt and change value.
    final doc = await remoteDoc();
    final ai = (doc['categories'] as Map)['ai'] as Map;
    ai['updatedAt'] = (ai['updatedAt'] as int) + 10000;
    (ai['keys'] as Map)['aiRpm'] = {'type': 'int', 'value': 99};
    final encrypted = await SettingsSyncCrypto.encrypt(
      utf8.encode(jsonEncode(doc)),
      password: 'pw',
      username: 'user',
      iterations: 1000,
    );
    client.files[SettingsSyncManager.remotePath] = encrypted;

    // Fresh device: same credentials, no local state.
    SharedPreferences.setMockInitialValues({
      'webdavInfo': '{"url":"https://dav","username":"user","password":"pw"}',
    });
    await Prefs().initPrefs();
    await newManager().sync(SyncDirection.download);

    expect(Prefs().prefs.getInt('aiRpm'), 99);
  });

  test('local change wins over stale remote', () async {
    await seedCredentials();
    Prefs().prefs.setInt('aiRpm', 10);
    await newManager().sync(SyncDirection.both);

    Prefs().prefs.setInt('aiRpm', 20);
    await newManager().sync(SyncDirection.both);

    final doc = await remoteDoc();
    final ai = (doc['categories'] as Map)['ai'] as Map;
    expect((ai['keys'] as Map)['aiRpm']['value'], 20);
    expect(Prefs().prefs.getInt('aiRpm'), 20);
  });

  test('unchanged local keeps updatedAt (no spurious wins)', () async {
    await seedCredentials();
    Prefs().prefs.setInt('aiRpm', 10);
    await newManager().sync(SyncDirection.both);
    final first = await remoteDoc();
    final firstTs =
        ((first['categories'] as Map)['ai'] as Map)['updatedAt'];
    await newManager().sync(SyncDirection.both);
    final second = await remoteDoc();
    final secondTs =
        ((second['categories'] as Map)['ai'] as Map)['updatedAt'];
    expect(secondTs, firstTs);
  });

  test('upload direction does not apply remote-won categories', () async {
    await seedCredentials();
    Prefs().prefs.setInt('aiRpm', 10);
    await newManager().sync(SyncDirection.both);
    final doc = await remoteDoc();
    final ai = (doc['categories'] as Map)['ai'] as Map;
    ai['updatedAt'] = (ai['updatedAt'] as int) + 10000;
    (ai['keys'] as Map)['aiRpm'] = {'type': 'int', 'value': 99};
    final encrypted = await SettingsSyncCrypto.encrypt(
      utf8.encode(jsonEncode(doc)),
      password: 'pw',
      username: 'user',
      iterations: 1000,
    );
    client.files[SettingsSyncManager.remotePath] = encrypted;

    await newManager().sync(SyncDirection.upload);
    // Local untouched; remote keeps the newer value (LWW).
    expect(Prefs().prefs.getInt('aiRpm'), 10);
    final after = await remoteDoc();
    final afterAi = (after['categories'] as Map)['ai'] as Map;
    expect((afterAi['keys'] as Map)['aiRpm']['value'], 99);
  });

  test('excluded category keeps remote value and is not applied', () async {
    await seedCredentials();
    Prefs().prefs.setInt('aiRpm', 10);
    Prefs().prefs.setDouble('ttsVolume', 1.0);
    await newManager().sync(SyncDirection.both);

    // Exclude tts, change it locally, sync: remote tts must stay intact.
    Prefs().prefs.setStringList(
        'settingsSyncExcludedCategories', ['tts']);
    Prefs().prefs.setDouble('ttsVolume', 0.1);
    await newManager().sync(SyncDirection.both);

    final doc = await remoteDoc();
    final categories = doc['categories'] as Map<String, dynamic>;
    expect((categories['tts'] as Map)['keys'], isNotEmpty);
    final ttsKeys = (categories['tts'] as Map)['keys'] as Map;
    expect(ttsKeys['ttsVolume']['value'], 1.0);
  });

  test('decrypt failure keeps local and remote untouched, reports once',
      () async {
    await seedCredentials();
    Prefs().prefs.setInt('aiRpm', 10);
    await newManager().sync(SyncDirection.both);
    final before = client.files[SettingsSyncManager.remotePath]!;

    // Remote encrypted with different password.
    final encrypted = await SettingsSyncCrypto.encrypt(
      utf8.encode('{"version":1,"categories":{}}'),
      password: 'other',
      username: 'user',
      iterations: 1000,
    );
    client.files[SettingsSyncManager.remotePath] = encrypted;

    var reported = '';
    await SettingsSyncManager(
      client: client,
      kdfIterations: 1000,
      tempDirPath: tempDir.path,
      onUserMessage: (m) => reported = m,
    ).sync(SyncDirection.both);

    expect(reported, isNotEmpty);
    expect(Prefs().prefs.getInt('aiRpm'), 10);
    expect(
        client.files[SettingsSyncManager.remotePath], isNot(equals(before)));
    // The bad remote file must not have been overwritten by this run.
    expect(
      client.files[SettingsSyncManager.remotePath],
      encrypted,
    );
  });

  test('skips silently when disabled or unconfigured', () async {
    Prefs().settingsSyncEnabled = false;
    await newManager().sync(SyncDirection.both);
    expect(client.files.containsKey(SettingsSyncManager.remotePath), isFalse);

    Prefs().settingsSyncEnabled = true;
    // No webdavInfo seeded -> no credentials -> skip.
    await newManager().sync(SyncDirection.both);
    expect(client.files.containsKey(SettingsSyncManager.remotePath), isFalse);
  });
```

- [ ] **步骤 3：运行测试验证失败**

运行：`flutter test test/service/sync/settings_sync_manager_test.dart`
预期：FAIL，`SettingsSyncManager` 未定义。

- [ ] **步骤 4：实现（追加类）**

在 `lib/service/sync/settings_sync_manager.dart` 追加（文件头补 `dart:io`/`get_temp_dir` 相关 import）：

```dart
/// Orchestrates settings synchronization over [client].
///
/// Flow: collect local categories → compare content hashes against the
/// last-sync state → download + decrypt the remote file → LWW merge →
/// apply remote-won categories (unless uploading) → re-encrypt and upload
/// the merged document. Any failure aborts without touching local data
/// beyond what was already applied, and never overwrites the remote file
/// on decrypt failure.
class SettingsSyncManager {
  static const String remotePath = 'anx/settings.v1.enc';
  static const int payloadVersion = 1;
  static const String statePrefsKey = 'settingsSyncState';

  final SyncClientBase? clientOverride;
  final int kdfIterations;
  final void Function(String message)? onUserMessage;
  final String? tempDirPath;

  SettingsSyncManager({
    SyncClientBase? client,
    this.kdfIterations = SettingsSyncCrypto.defaultIterations,
    this.onUserMessage,
    this.tempDirPath,
  }) : clientOverride = client;

  Future<void> sync(SyncDirection direction) async {
    if (!Prefs().settingsSyncEnabled) return;
    final info =
        Prefs().getSyncInfo(SyncClientFactory.getCurrentSyncProtocol());
    final String username = (info['username'] ?? '') as String;
    final String password = (info['password'] ?? '') as String;
    if (username.isEmpty || password.isEmpty) {
      AnxLog.info('Settings sync skipped: no credentials');
      return;
    }
    final client = clientOverride ?? SyncClientFactory.currentClient;
    if (client == null) {
      AnxLog.info('Settings sync skipped: no sync client');
      return;
    }

    final prefs = Prefs().prefs;
    final excluded = Prefs().settingsSyncExcludedCategories.toSet();
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. Collect local categories; refresh updatedAt when content changed.
    final collected =
        SettingsSyncCatalog.collect(prefs, excluded: excluded);
    final prevState = _loadState(prefs);
    final local = <String, Map<String, dynamic>>{};
    for (final entry in collected.entries) {
      final hash = await canonicalJsonHash(entry.value);
      final prev = prevState[entry.key];
      final int updatedAt = (prev != null && prev['hash'] == hash)
          ? (prev['updatedAt'] as int? ?? now)
          : now;
      local[entry.key] = {'updatedAt': updatedAt, 'keys': entry.value};
    }

    // 2. Download + decrypt remote.
    Map<String, dynamic> remoteCategories = {};
    if (await client.isExist(remotePath)) {
      try {
        final bytes = await _downloadBytes(client);
        final clear = await SettingsSyncCrypto.decrypt(bytes,
            password: password, iterations: kdfIterations);
        final doc = jsonDecode(utf8.decode(clear));
        if (doc is Map<String, dynamic> && doc['categories'] is Map) {
          remoteCategories =
              Map<String, dynamic>.from(doc['categories'] as Map);
        } else {
          throw const FormatException('Bad settings sync payload');
        }
      } on Exception catch (e) {
        // Keep local data, never overwrite a remote file we cannot read.
        AnxLog.severe('Settings sync: cannot decrypt remote file\n$e');
        onUserMessage?.call('decrypt-failed');
        return;
      }
    }

    // 3. Merge (LWW per category).
    final (merged, remoteWon) = mergeCategories(
      local: local,
      remote: remoteCategories,
      excluded: excluded,
    );

    // 4. Apply remote-won categories locally (both/download only).
    if (direction != SyncDirection.upload) {
      for (final entry in remoteWon.entries) {
        for (final keyEntry in entry.value.entries) {
          final value = keyEntry.value;
          if (value is! Map) continue;
          final ok =
              await Prefs.applyPrefsEntry(prefs, keyEntry.key, value);
          if (!ok) {
            AnxLog.warning(
                'Settings sync: dropped invalid entry ${keyEntry.key}');
          }
        }
      }
    }

    // 5. Upload merged document; excluded categories keep remote values.
    final uploadCategories = Map<String, dynamic>.from(merged);
    for (final category in excluded) {
      final remoteValue = remoteCategories[category];
      if (remoteValue != null) uploadCategories[category] = remoteValue;
    }
    final payload = utf8.encode(jsonEncode(<String, dynamic>{
      'version': payloadVersion,
      'categories': uploadCategories,
    }));
    final encrypted = await SettingsSyncCrypto.encrypt(
      payload,
      password: password,
      username: username,
      iterations: kdfIterations,
    );
    await _uploadBytes(client, encrypted);

    // 6. Persist state from the actual post-sync local content so that an
    // upload-only run does not mistake unchanged local data for changes.
    final afterLocal =
        SettingsSyncCatalog.collect(prefs, excluded: excluded);
    final newState = <String, dynamic>{};
    for (final entry in uploadCategories.entries) {
      if (excluded.contains(entry.key)) continue;
      final int ts = (entry.value as Map)['updatedAt'] as int? ?? now;
      newState[entry.key] = {
        'updatedAt': ts,
        'hash': await canonicalJsonHash(afterLocal[entry.key] ?? {}),
      };
    }
    await prefs.setString(statePrefsKey, jsonEncode(newState));

    if (direction != SyncDirection.upload) {
      Prefs().notifyListeners();
    }
    AnxLog.info('Settings sync done (${uploadCategories.length} categories)');
  }

  Map<String, Map<String, dynamic>> _loadState(
      SharedPreferences prefs) {
    final raw = prefs.getString(statePrefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      return decoded.map((k, v) =>
          MapEntry(k, v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{}));
    } catch (_) {
      return {};
    }
  }

  Future<List<int>> _downloadBytes(SyncClientBase client) async {
    final file = io.File('${_tempDir()}/settings_sync_download.enc');
    await client.downloadFile(remotePath, file.path);
    return await file.readAsBytes();
  }

  Future<void> _uploadBytes(SyncClientBase client, List<int> bytes) async {
    final file = io.File('${_tempDir()}/settings_sync_upload.enc');
    await file.writeAsBytes(bytes, flush: true);
    await client.uploadFile(file.path, remotePath);
  }

  String _tempDir() => tempDirPath ?? (io.Directory.systemTemp).path;
}
```

import 区最终为（文件顶部完整 import 列表）：

```dart
import 'dart:convert';
import 'dart:io' as io;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/service/sync/settings_sync_catalog.dart';
import 'package:anx_reader/service/sync/settings_sync_crypto.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
```

- [ ] **步骤 5：运行测试验证通过**

运行：`flutter test test/service/sync/settings_sync_manager_test.dart`
预期：PASS（全部，含任务 6 的纯函数测试）。

- [ ] **步骤 6：Commit**

```bash
git add lib/service/sync/settings_sync_manager.dart test/service/sync/settings_sync_manager_test.dart test/service/sync/in_memory_sync_client.dart
git commit -m "feat(sync): settings sync orchestration with LWW merge"
```

---

### 任务 8：挂接 syncData

**文件：**
- 修改：`lib/providers/sync.dart:332`（`await syncFiles();` 之后）

- [ ] **步骤 1：实现挂接**

在 `lib/providers/sync.dart` 的 `syncData()` 中，`await syncFiles();`（当前 332 行）之后、`imageCache.clear();` 之前插入：

```dart
      // Settings sync runs independently; its failure must not affect the
      // database/file sync that already succeeded above.
      try {
        await SettingsSyncManager(
          onUserMessage: (_) => AnxToast.show(
              L10n.of(navigatorKey.currentContext!).settingsSyncDecryptFailed),
        ).sync(finalDirection);
      } catch (e, s) {
        AnxLog.warning('Settings sync failed\n$e\n$s');
      }
```

文件头添加 import：

```dart
import 'package:anx_reader/service/sync/settings_sync_manager.dart';
```

（`AnxToast`、`L10n`、`navigatorKey` 均已在该文件 import。）

- [ ] **步骤 2：静态检查**

运行：`flutter analyze lib/providers/sync.dart lib/service/sync`
预期：No issues found（若 analysis_options 有既有告警，以不新增为标准）。

- [ ] **步骤 3：Commit**

```bash
git add lib/providers/sync.dart
git commit -m "feat(sync): wire settings sync into syncData"
```

---

### 任务 9：l10n 与设置 UI

**文件：**
- 修改：`lib/l10n/app_en.arb`、`app_zh.arb`、`app_zh-CN.arb`、`app_zh-TW.arb`
- 修改：`lib/page/settings_page/sync.dart`

- [ ] **步骤 1：添加 arb 键**

在 `app_en.arb`（模板）`settingsSyncAutoSync` 键附近追加：

```json
  "settingsSyncAppSettingsTitle": "Sync app settings",
  "settingsSyncAppSettingsHint": "Appearance, reading, narration, translation, AI and advanced settings are synced encrypted with your book progress. Secrets like API keys are encrypted before upload.",
  "settingsSyncCategoryAppearance": "Appearance",
  "settingsSyncCategoryReading": "Reading",
  "settingsSyncCategoryTts": "Narration (TTS)",
  "settingsSyncCategoryTranslate": "Translation",
  "settingsSyncCategoryAi": "AI",
  "settingsSyncCategoryAdvanced": "Advanced",
  "settingsSyncDecryptFailed": "Settings sync failed: cannot decrypt cloud settings (WebDAV password may have changed). Local settings are kept.",
```

`app_zh.arb` / `app_zh-CN.arb`：

```json
  "settingsSyncAppSettingsTitle": "同步应用设置",
  "settingsSyncAppSettingsHint": "外观、阅读、朗读、翻译、AI 与高级设置将随阅读进度一起加密同步。API 密钥等敏感信息在上传前加密。",
  "settingsSyncCategoryAppearance": "外观",
  "settingsSyncCategoryReading": "阅读",
  "settingsSyncCategoryTts": "朗读（TTS）",
  "settingsSyncCategoryTranslate": "翻译",
  "settingsSyncCategoryAi": "AI",
  "settingsSyncCategoryAdvanced": "高级",
  "settingsSyncDecryptFailed": "设置同步失败：无法解密云端设置（WebDAV 密码可能已更改），已保留本地设置。",
```

`app_zh-TW.arb`：

```json
  "settingsSyncAppSettingsTitle": "同步應用設定",
  "settingsSyncAppSettingsHint": "外觀、閱讀、朗讀、翻譯、AI 與進階設定將隨閱讀進度一起加密同步。API 金鑰等敏感資訊在上傳前加密。",
  "settingsSyncCategoryAppearance": "外觀",
  "settingsSyncCategoryReading": "閱讀",
  "settingsSyncCategoryTts": "朗讀（TTS）",
  "settingsSyncCategoryTranslate": "翻譯",
  "settingsSyncCategoryAi": "AI",
  "settingsSyncCategoryAdvanced": "進階",
  "settingsSyncDecryptFailed": "設定同步失敗：無法解密雲端設定（WebDAV 密碼可能已變更），已保留本機設定。",
```

- [ ] **步骤 2：生成本地化代码**

```bash
flutter gen-l10n
dart run normalize_arb_files.dart
```

预期：`lib/l10n/generated/L10n.dart` 包含 `settingsSyncAppSettingsTitle` 等 getter；其余语言记入 `docs/untranslated_messages.txt`（fallback 到英文，属预期）。

- [ ] **步骤 3：实现 UI**

在 `lib/page/settings_page/sync.dart` 第一个 `SettingsSection`（WebDAV，第 127 行 `),`）与「导出与导入」Section 之间插入新 Section：

```dart
        SettingsSection(
          title: Text(L10n.of(context).settingsSyncAppSettingsTitle),
          tiles: [
            SettingsTile.switchTile(
              title: Text(L10n.of(context).settingsSyncAppSettingsTitle),
              description:
                  Text(L10n.of(context).settingsSyncAppSettingsHint),
              leading: const Icon(Icons.settings_suggest_outlined),
              initialValue: Prefs().settingsSyncEnabled,
              enabled: Prefs().webdavStatus,
              onToggle: (bool value) {
                setState(() {
                  Prefs().settingsSyncEnabled = value;
                });
              },
            ),
            ...SettingsSyncCategory.values.map((category) {
              final excluded =
                  Prefs().settingsSyncExcludedCategories;
              return SettingsTile.switchTile(
                title: Text(_settingsSyncCategoryLabel(context, category)),
                leading: Icon(_settingsSyncCategoryIcon(category)),
                initialValue: !excluded.contains(category.name),
                enabled: Prefs().webdavStatus && Prefs().settingsSyncEnabled,
                onToggle: (bool value) {
                  setState(() {
                    final list = [...Prefs().settingsSyncExcludedCategories];
                    if (value) {
                      list.remove(category.name);
                    } else {
                      list.add(category.name);
                    }
                    Prefs().settingsSyncExcludedCategories = list;
                  });
                },
              );
            }),
          ],
        ),
```

文件底部（`SyncSetting` 类外）添加辅助函数：

```dart
String _settingsSyncCategoryLabel(
    BuildContext context, SettingsSyncCategory category) {
  final l10n = L10n.of(context);
  return switch (category) {
    SettingsSyncCategory.appearance => l10n.settingsSyncCategoryAppearance,
    SettingsSyncCategory.reading => l10n.settingsSyncCategoryReading,
    SettingsSyncCategory.tts => l10n.settingsSyncCategoryTts,
    SettingsSyncCategory.translate => l10n.settingsSyncCategoryTranslate,
    SettingsSyncCategory.ai => l10n.settingsSyncCategoryAi,
    SettingsSyncCategory.advanced => l10n.settingsSyncCategoryAdvanced,
  };
}

IconData _settingsSyncCategoryIcon(SettingsSyncCategory category) {
  return switch (category) {
    SettingsSyncCategory.appearance => Icons.palette_outlined,
    SettingsSyncCategory.reading => Icons.menu_book_outlined,
    SettingsSyncCategory.tts => Icons.record_voice_over_outlined,
    SettingsSyncCategory.translate => Icons.translate_outlined,
    SettingsSyncCategory.ai => Icons.auto_awesome_outlined,
    SettingsSyncCategory.advanced => Icons.tune_outlined,
  };
}
```

文件头添加 import：

```dart
import 'package:anx_reader/service/sync/settings_sync_catalog.dart';
```

- [ ] **步骤 4：静态检查**

运行：`flutter analyze lib/page/settings_page/sync.dart`
预期：No issues found。

- [ ] **步骤 5：Commit**

```bash
git add lib/l10n lib/page/settings_page/sync.dart docs/untranslated_messages.txt
git commit -m "feat(sync): settings sync UI with per-category toggles"
```

---

### 任务 10：全量验证

- [ ] **步骤 1：全量测试**

```bash
flutter test
```

预期：全部 PASS（含既有测试套件——`Prefs` 重构不得破坏 `buildPrefsBackupMap` 行为）。

- [ ] **步骤 2：全量静态检查**

```bash
flutter analyze
```

预期：不新增 issue（对照 `git stash` 前后输出；项目 analysis_options 有既有工具噪声，以不新增为准）。

- [ ] **步骤 3：手动冒烟（可选，需真机/模拟器）**

1. 配置 WebDAV → 开启同步 → 改一个 AI 设置 → 立即同步 → 检查远端出现 `anx/settings.v1.enc` 且下载后不可读出明文。
2. 另一设备（或清数据后）同账号登录 → 同步 → AI 设置出现。
3. 断网 → 立即同步 → 书籍/进度同步失败提示正常，App 功能不受影响。

- [ ] **步骤 4：最终 Commit**

```bash
git add -A
git commit -m "test: full suite green for settings sync"
```

（若无剩余变更则跳过。）

---

## 自检记录（计划编写时已完成）

1. **规格覆盖度**：§3 架构→任务 4/5/6/7；§4 加密→任务 4；§5 类别与排除→任务 5/2/9；§6 合并→任务 6/7；§7 错误与兼容→任务 7/8；§8 UI→任务 9；§9 测试→各任务 + 任务 10。无遗漏。
2. **占位符扫描**：无「待定/TODO/类似任务 N」；所有代码步骤含完整代码。
3. **类型一致性**：`collect` 返回 `{category: {key: {type,value}}}`、`mergeCategories` 输入包装为 `{updatedAt, keys}`、`remotePath`/`statePrefsKey`/`payloadVersion` 常量在任务 7 定义并被任务 8 引用，已核对一致。
