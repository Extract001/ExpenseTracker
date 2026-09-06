import 'package:uuid/uuid.dart';

class IdGenerator {
  static const _uuid = Uuid();

  /// Generates a cryptographically random RFC 4122 UUID v4.
  static String generateUuid() {
    return _uuid.v4();
  }

  /// Shorthand alias for generateUuid.
  static String uuid() => generateUuid();

  /// Validates whether a given string is a valid UUID.
  static bool isValidUuid(String id) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(id);
  }
}
