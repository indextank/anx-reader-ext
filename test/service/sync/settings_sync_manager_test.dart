import 'package:anx_reader/service/sync/settings_sync_manager.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
