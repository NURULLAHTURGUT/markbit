import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Encrypted content of a password-protected note.
///
/// The key is derived from the password with PBKDF2-HMAC-SHA256 ([salt],
/// [iterations]); the content is sealed with AES-256-GCM, so a wrong password
/// or tampered data fails authentication instead of producing garbage.
@immutable
class NoteLock {
  const NoteLock({
    required this.salt,
    required this.iterations,
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  final List<int> salt;
  final int iterations;
  final List<int> nonce;
  final List<int> cipherText;
  final List<int> mac;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'kdf': 'pbkdf2-sha256',
    'cipher': 'aes-256-gcm',
    'salt': base64Encode(salt),
    'iterations': iterations,
    'nonce': base64Encode(nonce),
    'data': base64Encode(cipherText),
    'mac': base64Encode(mac),
  };

  factory NoteLock.fromJson(Map<String, dynamic> j) {
    if (j['v'] != 1) throw const FormatException('Unsupported note lock');
    return NoteLock(
      salt: base64Decode(j['salt'] as String),
      iterations: (j['iterations'] as num).toInt(),
      nonce: base64Decode(j['nonce'] as String),
      cipherText: base64Decode(j['data'] as String),
      mac: base64Decode(j['mac'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NoteLock &&
      other.iterations == iterations &&
      listEquals(other.salt, salt) &&
      listEquals(other.nonce, nonce) &&
      listEquals(other.mac, mac) &&
      listEquals(other.cipherText, cipherText);

  @override
  int get hashCode => Object.hash(iterations, Object.hashAll(mac));
}

/// Raised when a password does not open a locked note.
class WrongPasswordException implements Exception {
  const WrongPasswordException();
}

abstract final class NoteCrypto {
  /// PBKDF2 rounds for new locks (about 1.5 s on a desktop, once per unlock).
  static const int defaultIterations = 310000;

  static final _cipher = AesGcm.with256bits();

  static List<int> newSalt() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256));
  }

  /// Derives the 256-bit key on a background isolate so the UI stays
  /// responsive during the deliberately slow key stretching.
  static Future<List<int>> deriveKey(
    String password,
    List<int> salt,
    int iterations,
  ) => Isolate.run(() async {
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: password, nonce: salt);
    return key.extractBytes();
  });

  /// Encrypts [content] (JSON) with a fresh random nonce.
  static Future<NoteLock> seal(
    List<int> key,
    List<int> salt,
    int iterations,
    Map<String, dynamic> content,
  ) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(content)),
      secretKey: SecretKey(key),
    );
    return NoteLock(
      salt: salt,
      iterations: iterations,
      nonce: box.nonce,
      cipherText: box.cipherText,
      mac: box.mac.bytes,
    );
  }

  /// Decrypts a lock; throws [WrongPasswordException] for a wrong key.
  static Future<Map<String, dynamic>> open(List<int> key, NoteLock lock) async {
    try {
      final clear = await _cipher.decrypt(
        SecretBox(lock.cipherText, nonce: lock.nonce, mac: Mac(lock.mac)),
        secretKey: SecretKey(key),
      );
      return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    } on SecretBoxAuthenticationError {
      throw const WrongPasswordException();
    }
  }
}
