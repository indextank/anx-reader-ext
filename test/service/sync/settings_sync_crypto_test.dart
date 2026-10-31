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
