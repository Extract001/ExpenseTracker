import 'package:intl/intl.dart';

class DateTimeUtils {
  /// Converts a DateTime to ISO-8601 UTC string.
  static String toUtcIsoString(DateTime dateTime) {
    return dateTime.toUtc().toIso8601String();
  }

  /// Parses an ISO-8601 UTC string into a local DateTime.
  static DateTime parseUtcIsoToLocal(String isoString) {
    return DateTime.parse(isoString).toLocal();
  }

  /// Parses an ISO-8601 UTC string into UTC DateTime.
  static DateTime parseUtcIso(String isoString) {
    return DateTime.parse(isoString).toUtc();
  }

  /// Formats a DateTime for user display (e.g., "06 Sep 2026").
  static String formatDate(DateTime dateTime) {
    return DateFormat('dd MMM yyyy').format(dateTime.toLocal());
  }

  /// Formats a DateTime with time (e.g., "06 Sep 2026, 03:15 PM").
  static String formatDateTime(DateTime dateTime) {
    return DateFormat('dd MMM yyyy, hh:mm a').format(dateTime.toLocal());
  }

  /// Formats time only (e.g., "03:15 PM").
  static String formatTime(DateTime dateTime) {
    return DateFormat('hh:mm a').format(dateTime.toLocal());
  }

  /// Formats month and year (e.g., "September 2026").
  static String formatMonthYear(DateTime dateTime) {
    return DateFormat('MMMM yyyy').format(dateTime.toLocal());
  }

  /// Generates month key (e.g. "2026-09").
  static String toMonthKey(DateTime dateTime) {
    final local = dateTime.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}';
  }

  /// Returns start of month in UTC for query filtering.
  static DateTime startOfMonthUtc(DateTime date) {
    final local = date.toLocal();
    final startLocal = DateTime(local.year, local.month, 1, 0, 0, 0);
    return startLocal.toUtc();
  }

  /// Returns end of month in UTC for query filtering.
  static DateTime endOfMonthUtc(DateTime date) {
    final local = date.toLocal();
    final nextMonthLocal = DateTime(local.year, local.month + 1, 1, 0, 0, 0);
    final endLocal = nextMonthLocal.subtract(const Duration(milliseconds: 1));
    return endLocal.toUtc();
  }

  /// Returns start of day in UTC.
  static DateTime startOfDayUtc(DateTime date) {
    final local = date.toLocal();
    final startLocal = DateTime(local.year, local.month, local.day, 0, 0, 0);
    return startLocal.toUtc();
  }

  /// Returns end of day in UTC.
  static DateTime endOfDayUtc(DateTime date) {
    final local = date.toLocal();
    final endLocal = DateTime(
      local.year,
      local.month,
      local.day,
      23,
      59,
      59,
      999,
    );
    return endLocal.toUtc();
  }
}
