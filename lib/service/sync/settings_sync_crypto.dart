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
    0x41,
    0x4E,
    0x58,
    0x53,
    0x45,
    0x54,
    0x31,
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
    final digest = await _sha256.hash(utf8.encode('$_saltDomain$username'));
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
    final cipherText = payload.sublist(offset, payload.length - macLength);
    final mac = payload.sublist(payload.length - macLength);
    final key = await deriveKey(password, salt, iterations: iterations);
    return _cipher.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
    );
  }
}
