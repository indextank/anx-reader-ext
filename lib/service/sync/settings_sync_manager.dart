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

/// SHA-256 hex of a canonical JSON encoding (recursively key-sorted) of
/// [value]. Insertion order never affects the result.
Future<String> canonicalJsonHash(Object? value) async {
  final digest =
      await Sha256().hash(utf8.encode(jsonEncode(_canonical(value))));
  return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
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
    final collected = SettingsSyncCatalog.collect(prefs, excluded: excluded);
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
          final ok = await Prefs.applyPrefsEntry(prefs, keyEntry.key, value);
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
    final afterLocal = SettingsSyncCatalog.collect(prefs, excluded: excluded);
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
      Prefs().notifySettingsChanged();
    }
    AnxLog.info('Settings sync done (${uploadCategories.length} categories)');
  }

  Map<String, Map<String, dynamic>> _loadState(SharedPreferences prefs) {
    final raw = prefs.getString(statePrefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      return decoded.map((k, v) => MapEntry(
          k, v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{}));
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
