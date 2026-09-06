import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../constants/app_constants.dart';
import '../security/secure_storage_service.dart';

class EncryptedDatabaseConnection {
  /// Opens an encrypted SQLite database connection backed by SQLCipher via Drift.
  static LazyDatabase createEncryptedConnection({
    SecureStorageService? secureStorage,
    String dbName = AppConstants.databaseFileName,
    File? databaseFileOverride,
  }) {
    return LazyDatabase(() async {
      final storage = secureStorage ?? SecureStorageService();

      final File file;
      if (databaseFileOverride != null) {
        file = databaseFileOverride;
      } else {
        final dbFolder = await getApplicationDocumentsDirectory();
        file = File(p.join(dbFolder.path, dbName));
      }

      final fileExists = file.existsSync();
      // Fail-safe check: Throws DatabaseKeyMissingException if DB file exists but key is absent
      final key = await storage.getOrInitializeDatabaseKey(
        databaseFileExists: fileExists,
      );

      return NativeDatabase(
        file,
        setup: (rawDb) {
          // Configure SQLCipher 256-bit AES encryption
          rawDb.execute("PRAGMA key = '$key';");
          rawDb.execute("PRAGMA cipher_compatibility = 4;");
        },
      );
    });
  }

  /// In-memory SQLite database connection for unit & integration testing.
  static QueryExecutor createInMemoryConnection() {
    return NativeDatabase.memory();
  }
}
