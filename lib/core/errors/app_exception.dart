abstract class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic details;

  const AppException(this.message, {this.code, this.details});

  @override
  String toString() => 'AppException: $message (code: ${code ?? 'UNKNOWN'})';
}

class DatabaseException extends AppException {
  const DatabaseException(super.message, {super.code, super.details});
}

class ValidationException extends AppException {
  const ValidationException(super.message, {super.code, super.details});
}

class AuthException extends AppException {
  const AuthException(super.message, {super.code, super.details});
}

class AuthFailureException extends AuthException {
  const AuthFailureException(super.message, {super.code, super.details});
}

class NetworkException extends AppException {
  const NetworkException(super.message, {super.code, super.details});
}

class SyncException extends AppException {
  const SyncException(super.message, {super.code, super.details});
}

class SecurityException extends AppException {
  const SecurityException(super.message, {super.code, super.details});
}

class NotFoundException extends AppException {
  const NotFoundException(super.message, {super.code, super.details});
}

class BackupRestoreException extends AppException {
  const BackupRestoreException(super.message, {super.code, super.details});
}

class DatabaseKeyMissingException extends SecurityException {
  const DatabaseKeyMissingException([
    super.message =
        'Database file exists on disk, but encryption key cannot be retrieved from secure storage. Halting to prevent data corruption.',
    String? code = 'DB_KEY_MISSING',
    dynamic details,
  ]) : super(code: code, details: details);
}

class DatabaseKeyCorruptedException extends SecurityException {
  const DatabaseKeyCorruptedException([
    super.message =
        'Database encryption key in secure storage is corrupted or invalid. Halting to prevent data corruption.',
    String? code = 'DB_KEY_CORRUPTED',
    dynamic details,
  ]) : super(code: code, details: details);
}
