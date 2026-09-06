import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class HashingService {
  /// Default PBKDF2 iteration count for interactive PIN hashing (minimum 10,000 for mobile responsiveness).
  static const int pinHashingIterations = 10000;

  /// Default PBKDF2 iteration count for offline backup archive encryption (100,000 iterations).
  static const int backupKdfIterations = 100000;

  /// Backward-compatible alias for default PIN iterations.
  static const int defaultIterations = pinHashingIterations;

  /// Default salt length in bytes (minimum 16 bytes).
  static const int defaultSaltBytes = 16;

  /// Generates cryptographically secure random bytes.
  static Uint8List generateRandomBytes([int length = defaultSaltBytes]) {
    final random = Random.secure();
    final values = Uint8List(length);
    for (int i = 0; i < length; i++) {
      values[i] = random.nextInt(256);
    }
    return values;
  }

  /// Generates a cryptographically secure random salt encoded as Base64Url (default: 16 bytes).
  static String generateSalt([int length = defaultSaltBytes]) {
    return base64UrlEncode(generateRandomBytes(length));
  }

  /// RFC 2898 standard PBKDF2 key derivation function using HMAC-SHA256.
  static Uint8List pbkdf2HmacSha256({
    required List<int> password,
    required List<int> salt,
    int iterations = defaultIterations,
    int keyLength = 32,
  }) {
    if (iterations < 1) {
      throw ArgumentError('Iterations must be at least 1');
    }
    if (keyLength < 1) {
      throw ArgumentError('Key length must be at least 1');
    }

    final hmac = Hmac(sha256, password);
    final numBlocks = (keyLength + 31) ~/ 32;
    final derivedKey = Uint8List(keyLength);

    var offset = 0;
    for (var block = 1; block <= numBlocks; block++) {
      // salt || INT_32_BE(block)
      final blockBytes = Uint8List(salt.length + 4);
      blockBytes.setRange(0, salt.length, salt);
      blockBytes[salt.length] = (block >> 24) & 0xff;
      blockBytes[salt.length + 1] = (block >> 16) & 0xff;
      blockBytes[salt.length + 2] = (block >> 8) & 0xff;
      blockBytes[salt.length + 3] = block & 0xff;

      var u = Uint8List.fromList(hmac.convert(blockBytes).bytes);
      final blockResult = Uint8List.fromList(u);

      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < 32; j++) {
          blockResult[j] ^= u[j];
        }
      }

      final bytesToCopy = (offset + 32 > keyLength) ? keyLength - offset : 32;
      derivedKey.setRange(offset, offset + bytesToCopy, blockResult);
      offset += bytesToCopy;
    }

    return derivedKey;
  }

  /// Constant-time comparison of two byte sequences to mitigate timing side-channel attacks.
  static bool constantTimeCompareBytes(List<int> a, List<int> b) {
    var result = a.length ^ b.length;
    final minLen = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < minLen; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// Constant-time comparison of two strings to mitigate timing side-channel attacks.
  static bool constantTimeCompare(String a, String b) {
    return constantTimeCompareBytes(utf8.encode(a), utf8.encode(b));
  }

  /// Hashes a PIN or secret using RFC 2898 PBKDF2-HMAC-SHA256 with 10,000 iterations.
  /// Returns a 64-character lowercase hex string.
  static String hashPin(
    String pin,
    String salt, {
    int iterations = defaultIterations,
  }) {
    final saltBytes = utf8.encode(salt);
    final pinBytes = utf8.encode(pin);
    final derived = pbkdf2HmacSha256(
      password: pinBytes,
      salt: saltBytes,
      iterations: iterations,
      keyLength: 32,
    );
    return derived.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Legacy multi-round SHA-256 hash calculation for backward compatibility.
  static String legacyHashPin(
    String pin,
    String salt, {
    int iterations = defaultIterations,
  }) {
    var bytes = utf8.encode(pin + salt);
    var digest = sha256.convert(bytes);
    for (int i = 1; i < iterations; i++) {
      digest = sha256.convert(digest.bytes + utf8.encode(salt));
    }
    return digest.toString();
  }

  /// Verifies a PIN against a known hash and salt using constant-time comparison.
  /// Seamlessly verifies both PBKDF2-HMAC-SHA256 hashes and legacy multi-round hashes.
  static bool verifyPin(
    String enteredPin,
    String storedHash,
    String storedSalt, {
    int iterations = defaultIterations,
  }) {
    // 1. Primary: Verify with standard PBKDF2-HMAC-SHA256
    final computedPbkdf2 = hashPin(
      enteredPin,
      storedSalt,
      iterations: iterations,
    );
    if (constantTimeCompare(computedPbkdf2, storedHash)) {
      return true;
    }

    // 2. Fallback: Verify against legacy multi-round hash for backward compatibility
    final computedLegacy = legacyHashPin(
      enteredPin,
      storedSalt,
      iterations: iterations,
    );
    return constantTimeCompare(computedLegacy, storedHash);
  }
}
