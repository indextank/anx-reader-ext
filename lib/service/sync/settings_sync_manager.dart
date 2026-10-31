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
