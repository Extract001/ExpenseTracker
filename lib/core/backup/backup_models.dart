import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../security/hashing_service.dart';

/// Version of the backup format.
const int kCurrentBackupFormatVersion = 1;

/// Current schema version of the database.
const int kCurrentSchemaVersion = 1;

/// Parameters used by the Key Derivation Function (KDF) for encrypted backups.
class BackupKdfParams {
  final String algorithm; // e.g. 'PBKDF2-HMAC-SHA256'
  final int iterations; // e.g. 100000 for production offline backups
  final int saltBytesLength; // 16 bytes
  final int keyBitsLength; // 256 bits
  final int version; // 1

  const BackupKdfParams({
    this.algorithm = 'PBKDF2-HMAC-SHA256',
    this.iterations = 100000,
    this.saltBytesLength = 16,
    this.keyBitsLength = 256,
    this.version = 1,
  });

  Map<String, dynamic> toJson() => {
    'algorithm': algorithm,
    'iterations': iterations,
    'saltBytesLength': saltBytesLength,
    'keyBitsLength': keyBitsLength,
    'version': version,
  };

  factory BackupKdfParams.fromJson(Map<String, dynamic> json) {
    return BackupKdfParams(
      algorithm: json['algorithm'] as String? ?? 'PBKDF2-HMAC-SHA256',
      iterations: json['iterations'] as int? ?? 100000,
      saltBytesLength: json['saltBytesLength'] as int? ?? 16,
      keyBitsLength: json['keyBitsLength'] as int? ?? 256,
      version: json['version'] as int? ?? 1,
    );
  }
}

/// Metadata header describing the backup archive.
class BackupMetadata {
  final int formatVersion;
  final String appVersion;
  final int schemaVersion;
  final DateTime createdAtUtc;
  final String userId;
  final String databaseId;
  final String
  checksum; // For unencrypted: SHA-256 of canonical data. For encrypted: MAC tag hex.
  final bool isEncrypted;
  final String? encryptionAlgorithm; // 'AES-256-GCM'
  final BackupKdfParams? kdfParams;
  final String? encryptionSalt; // hex
  final String? nonce; // hex
  final Map<String, int> entityCounts;

  const BackupMetadata({
    required this.formatVersion,
    required this.appVersion,
    required this.schemaVersion,
    required this.createdAtUtc,
    required this.userId,
    required this.databaseId,
    required this.checksum,
    this.isEncrypted = false,
    this.encryptionAlgorithm,
    this.kdfParams,
    this.encryptionSalt,
    this.nonce,
    this.entityCounts = const {},
  });

  Map<String, dynamic> toJson() => {
    'formatVersion': formatVersion,
    'appVersion': appVersion,
    'schemaVersion': schemaVersion,
    'createdAtUtc': createdAtUtc.toIso8601String(),
    'userId': userId,
    'databaseId': databaseId,
    'checksum': checksum,
    'isEncrypted': isEncrypted,
    if (encryptionAlgorithm != null) 'encryptionAlgorithm': encryptionAlgorithm,
    if (kdfParams != null) 'kdfParams': kdfParams!.toJson(),
    'encryptionSalt': encryptionSalt,
    'nonce': nonce,
    'entityCounts': entityCounts,
  };

  factory BackupMetadata.fromJson(Map<String, dynamic> json) {
    return BackupMetadata(
      formatVersion: json['formatVersion'] as int? ?? 1,
      appVersion: json['appVersion'] as String? ?? '1.0.0',
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      createdAtUtc: DateTime.parse(json['createdAtUtc'] as String).toUtc(),
      userId: json['userId'] as String,
      databaseId: json['databaseId'] as String? ?? 'default',
      checksum: json['checksum'] as String,
      isEncrypted: json['isEncrypted'] as bool? ?? false,
      encryptionAlgorithm: json['encryptionAlgorithm'] as String?,
      kdfParams: json['kdfParams'] != null
          ? BackupKdfParams.fromJson(
              Map<String, dynamic>.from(json['kdfParams'] as Map),
            )
          : null,
      encryptionSalt: json['encryptionSalt'] as String?,
      nonce: json['nonce'] as String?,
      entityCounts: json['entityCounts'] != null
          ? Map<String, int>.from(json['entityCounts'] as Map)
          : const {},
    );
  }

  /// Computes the exact canonical UTF-8 bytes to authenticate as Additional Authenticated Data (AAD).
  ///
  /// Protects formatVersion, appVersion, schemaVersion, createdAtUtc, userId,
  /// databaseId, encryptionAlgorithm, kdfParams, encryptionSalt, and nonce from tampering.
  List<int> computeAadBytes() {
    final aadMap = <String, dynamic>{
      'formatVersion': formatVersion,
      'appVersion': appVersion,
      'schemaVersion': schemaVersion,
      'createdAtUtc': createdAtUtc.toIso8601String(),
      'userId': userId,
      'databaseId': databaseId,
      'encryptionAlgorithm': encryptionAlgorithm ?? 'AES-256-GCM',
      if (kdfParams != null) 'kdfParams': kdfParams!.toJson(),
      'encryptionSalt': encryptionSalt ?? '',
      'nonce': nonce ?? '',
    };
    final canonicalAad = BackupArchive.canonicalize(aadMap);
    return utf8.encode(jsonEncode(canonicalAad));
  }
}

/// Complete backup container holding metadata and either raw or encrypted data.
class BackupArchive {
  final BackupMetadata metadata;
  final Map<String, dynamic>? data;
  final String? ciphertext;

  const BackupArchive({required this.metadata, this.data, this.ciphertext});

  Map<String, dynamic> toJson() => {
    'metadata': metadata.toJson(),
    if (data != null) 'data': data,
    if (ciphertext != null) 'ciphertext': ciphertext,
  };

  factory BackupArchive.fromJson(Map<String, dynamic> json) {
    final meta = BackupMetadata.fromJson(
      Map<String, dynamic>.from(json['metadata'] as Map),
    );
    final dataMap = json['data'] != null
        ? Map<String, dynamic>.from(json['data'] as Map)
        : null;
    final cipher = json['ciphertext'] as String?;

    return BackupArchive(metadata: meta, data: dataMap, ciphertext: cipher);
  }

  /// Verifies the cryptographic checksum of unencrypted data.
  bool verifyChecksum() {
    if (metadata.isEncrypted || data == null) return false;
    final canonicalJsonStr = jsonEncode(canonicalize(data!));
    final digest = sha256.convert(utf8.encode(canonicalJsonStr)).toString();
    return HashingService.constantTimeCompare(digest, metadata.checksum);
  }

  static dynamic canonicalize(dynamic value) {
    if (value is Map) {
      final sortedKeys = value.keys.map((k) => k.toString()).toList()..sort();
      final result = <String, dynamic>{};
      for (final key in sortedKeys) {
        result[key] = canonicalize(value[key]);
      }
      return result;
    } else if (value is List) {
      return value.map(canonicalize).toList();
    }
    return value;
  }
}
