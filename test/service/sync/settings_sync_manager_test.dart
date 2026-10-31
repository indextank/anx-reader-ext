import 'dart:convert';
import 'dart:io' as io;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'in_memory_sync_client.dart';
import 'package:anx_reader/service/sync/settings_sync_crypto.dart';
import 'package:anx_reader/service/sync/settings_sync_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> cat(
        int updatedAt, Map<String, Map<String, Object?>> keys) =>
    {
      'updatedAt': updatedAt,
      'keys': keys,
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

  group('SettingsSyncManager.sync', () {
    late io.Directory tempDir;
    late InMemorySyncClient client;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Prefs().initPrefs();
      tempDir = await io.Directory.systemTemp.createTemp('settings_sync_test');
      client = InMemorySyncClient(tempDir);
    });

    tearDown(() {
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
      final ai = (doc['categories'] as Map<String, dynamic>)['ai'] as Map;
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
      final ai = (doc['categories'] as Map<String, dynamic>)['ai'] as Map;
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
      final ai = (doc['categories'] as Map<String, dynamic>)['ai'] as Map;
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
      final afterAi = (after['categories'] as Map<String, dynamic>)['ai'] as Map;
      expect((afterAi['keys'] as Map)['aiRpm']['value'], 99);
    });

    test('excluded category keeps remote value and is not applied', () async {
      await seedCredentials();
      Prefs().prefs.setInt('aiRpm', 10);
      Prefs().prefs.setDouble('ttsVolume', 1.0);
      await newManager().sync(SyncDirection.both);

      // Exclude tts, change it locally, sync: remote tts must stay intact.
      Prefs().prefs.setStringList('settingsSyncExcludedCategories', ['tts']);
      Prefs().prefs.setDouble('ttsVolume', 0.1);
      await newManager().sync(SyncDirection.both);

      final doc = await remoteDoc();
      final categories = doc['categories'] as Map<String, dynamic>;
      expect((categories['tts'] as Map)['keys'], isNotEmpty);
      final ttsKeys = (categories['tts'] as Map)['keys'] as Map;
      expect(ttsKeys['ttsVolume']['value'], 1.0);
    });

    test(
        'decrypt failure keeps local and remote untouched, reports once',
        () async {
      await seedCredentials();
      Prefs().prefs.setInt('aiRpm', 10);
      await newManager().sync(SyncDirection.both);

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
      // The bad remote file must not have been overwritten by this run.
      expect(client.files[SettingsSyncManager.remotePath], encrypted);
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
  });
}
