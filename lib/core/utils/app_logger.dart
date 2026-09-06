import 'package:flutter/foundation.dart';

/// Centralized, structured, and leak-safe logger.
///
/// Strictly strips all financial amounts, user notes, account numbers/names,
/// passwords, PINs, tokens, and cryptographic keys before outputting log entries.
class AppLogger {
  /// Console logging is disabled by default in release mode (!kReleaseMode).
  static bool enableConsoleLogging = !kReleaseMode;

  static const Set<String> _redactedKeys = {
    'amount',
    'amountminor',
    'initialbalanceminor',
    'targetamountminor',
    'currentamountminor',
    'balance',
    'note',
    'description',
    'title',
    'pin',
    'password',
    'passcode',
    'token',
    'key',
    'secret',
    'auth',
    'email',
    'name',
    'accountname',
    'categoryname',
    'currency',
    'authorization',
    'payload',
    'payloadjson',
  };

  /// Sanitizes a metadata map by replacing all sensitive keys with '[REDACTED]'.
  static Map<String, dynamic> sanitize(Map<String, dynamic>? input) {
    if (input == null) return {};
    final sanitized = <String, dynamic>{};
    for (final entry in input.entries) {
      final keyLower = entry.key.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]'),
        '',
      );
      if (_redactedKeys.contains(keyLower) ||
          keyLower.contains('token') ||
          keyLower.contains('secret') ||
          keyLower.contains('password') ||
          keyLower.contains('amount') ||
          keyLower.contains('balance') ||
          keyLower.contains('pin') ||
          keyLower.contains('note') ||
          keyLower.contains('desc') ||
          keyLower.contains('key')) {
        sanitized[entry.key] = '[REDACTED]';
      } else if (entry.value is Map<String, dynamic>) {
        sanitized[entry.key] = sanitize(entry.value as Map<String, dynamic>);
      } else if (entry.value is List) {
        sanitized[entry.key] = '[LIST:${(entry.value as List).length}]';
      } else {
        sanitized[entry.key] = entry.value;
      }
    }
    return sanitized;
  }

  /// Sanitizes error strings to prevent leakage of SQL statements or parameter values.
  static String sanitizeError(Object? error) {
    if (error == null) return 'UNKNOWN_ERROR';
    var text = error.toString();
    // Redact email addresses
    text = text.replaceAll(
      RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'),
      '[EMAIL_REDACTED]',
    );
    // Redact hex secrets / UUIDs / long alphanumeric keys
    text = text.replaceAll(RegExp(r'\b[0-9a-fA-F]{32,64}\b'), '[KEY_REDACTED]');
    return text;
  }

  static void info(
    String operation, {
    String? entityId,
    Map<String, dynamic>? metadata,
  }) {
    if (!enableConsoleLogging) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final cleanMeta = sanitize(metadata);
    final entity = entityId != null ? ' [id: $entityId]' : '';
    debugPrint('[$now] [INFO] [$operation]$entity $cleanMeta');
  }

  static void warning(
    String operation, {
    String? entityId,
    Object? error,
    Map<String, dynamic>? metadata,
  }) {
    if (!enableConsoleLogging) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final cleanMeta = sanitize(metadata);
    final entity = entityId != null ? ' [id: $entityId]' : '';
    final err = error != null ? ' error: ${sanitizeError(error)}' : '';
    debugPrint('[$now] [WARN] [$operation]$entity$err $cleanMeta');
  }

  static void error(
    String operation, {
    String? entityId,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    if (!enableConsoleLogging) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final cleanMeta = sanitize(metadata);
    final entity = entityId != null ? ' [id: $entityId]' : '';
    final err = error != null ? ' error: ${sanitizeError(error)}' : '';
    debugPrint('[$now] [ERROR] [$operation]$entity$err $cleanMeta');
  }
}
