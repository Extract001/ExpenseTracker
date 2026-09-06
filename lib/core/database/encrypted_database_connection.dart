import 'dart:ffi';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/open.dart';
import '../constants/app_constants.dart';
import '../security/secure_storage_service.dart';

class EncryptedDatabaseConnection {
  static bool _isSqlCipherConfigured = false;

  /// Ensures SQLite loads the SQLCipher dynamic library across platforms.
  static void _ensureSqlCipherConfigured() {
    if (_isSqlCipherConfigured) return;
    if (Platform.isAndroid) {
      open.overrideFor(
        OperatingSystem.android,
        () => DynamicLibrary.open('libsqlcipher.so'),
      );
    } else if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlcipher.so'),
      );
    } else if (Platform.isWindows) {
      open.overrideFor(
        OperatingSystem.windows,
        () => DynamicLibrary.open('sqlcipher.dll'),
      );
    } else if (Platform.isMacOS) {
      open.overrideFor(
        OperatingSystem.macOS,
        () => DynamicLibrary.open('libsqlcipher.dylib'),
      );
    } else if (Platform.isIOS) {
      open.overrideFor(OperatingSystem.iOS, () => DynamicLibrary.process());
    }
    _isSqlCipherConfigured = true;
  }

  /// Opens an encrypted SQLite database connection backed by SQLCipher via Drift.
  static LazyDatabase createEncryptedConnection({
    SecureStorageService? secureStorage,
    String dbName = AppConstants.databaseFileName,
    File? databaseFileOverride,
  }) {
    return LazyDatabase(() async {
      _ensureSqlCipherConfigured();

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
