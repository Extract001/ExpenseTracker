/// Represents a deterministic, composite incremental synchronization cursor.
///
/// Combines an ISO-8601 UTC timestamp and the unique entity UUID to prevent
/// skipped records when multiple records share identical millisecond timestamps.
class SyncCursor {
  final DateTime timestampUtc;
  final String entityId;

  const SyncCursor({required this.timestampUtc, required this.entityId});

  /// Encodes this composite cursor into a compact string representation.
  String encode() => '${timestampUtc.toUtc().toIso8601String()}|$entityId';

  /// Decodes a raw cursor string into a `SyncCursor`.
  static SyncCursor? decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final separatorIdx = raw.indexOf('|');
    if (separatorIdx == -1) {
      // Fallback for legacy timestamp-only strings
      final dt = DateTime.tryParse(raw)?.toUtc();
      if (dt == null) return null;
      return SyncCursor(timestampUtc: dt, entityId: '');
    }

    final dateStr = raw.substring(0, separatorIdx);
    final idStr = raw.substring(separatorIdx + 1);
    final dt = DateTime.tryParse(dateStr)?.toUtc();
    if (dt == null) return null;

    return SyncCursor(timestampUtc: dt, entityId: idStr);
  }

  /// Determines whether candidate record (with [candidateTime] and [candidateId])
  /// comes strictly AFTER this cursor in the deterministic ordering:
  /// `ORDER BY updated_at_utc ASC, id ASC`.
  bool isAfterCursor({
    required DateTime candidateTime,
    required String candidateId,
  }) {
    final candUtc = candidateTime.toUtc();
    final curUtc = timestampUtc.toUtc();

    if (candUtc.isAfter(curUtc)) return true;
    if (candUtc.isBefore(curUtc)) return false;

    // Same timestamp -> tie-break via lexicographical entity UUID comparison
    return candidateId.compareTo(entityId) > 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncCursor &&
          runtimeType == other.runtimeType &&
          timestampUtc.isAtSameMomentAs(other.timestampUtc) &&
          entityId == other.entityId;

  @override
  int get hashCode => timestampUtc.hashCode ^ entityId.hashCode;

  @override
  String toString() => encode();
}
