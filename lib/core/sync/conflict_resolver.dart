import 'dart:convert';
import 'sync_types.dart';

/// Pure functional conflict resolver that performs surgical, field-by-field
/// reconciliation between local and remote record states based on granular field timestamps.
class ConflictResolver {
  /// Maximum permitted forward clock skew before clamping future timestamps to current server time.
  static const Duration maxPermittedClockSkew = Duration(minutes: 5);

  /// Sanitizes a map of field timestamps, clamping any timestamps in the future
  /// (exceeding [nowUtc] + [maxSkew]) to [nowUtc] to prevent malicious permanent wins.
  static Map<String, String> sanitizeFieldTimestamps(
    Map<String, String> timestamps, {
    DateTime? nowUtc,
    Duration maxSkew = maxPermittedClockSkew,
  }) {
    final now = (nowUtc ?? DateTime.now()).toUtc();
    final maxAllowed = now.add(maxSkew);
    final sanitized = <String, String>{};

    for (final entry in timestamps.entries) {
      final parsed = DateTime.tryParse(entry.value)?.toUtc();
      if (parsed == null) {
        sanitized[entry.key] = now.toIso8601String();
      } else if (parsed.isAfter(maxAllowed)) {
        // Clamp malicious or drifted future timestamps to current time
        sanitized[entry.key] = now.toIso8601String();
      } else {
        sanitized[entry.key] = parsed.toIso8601String();
      }
    }
    return sanitized;
  }

  /// Recursively transforms any dynamic data structure (Map, List, primitive)
  /// into a canonical representation where all Map keys at every nesting level
  /// are sorted deterministically in lexicographical order.
  static dynamic canonicalizeValue(dynamic value) {
    if (value == null) {
      return null;
    } else if (value is Map) {
      final sortedKeys = value.keys.map((k) => k.toString()).toList()..sort();
      final canonicalMap = <String, dynamic>{};
      for (final key in sortedKeys) {
        canonicalMap[key] = canonicalizeValue(value[key]);
      }
      return canonicalMap;
    } else if (value is List) {
      return value.map((item) => canonicalizeValue(item)).toList();
    } else {
      return value;
    }
  }

  /// Serializes any dynamic value into a deterministic canonical JSON string where:
  /// - Maps at every nesting level have their keys sorted lexicographically.
  /// - Lists preserve ordered elements with recursively canonicalized children.
  /// - Primitives and nulls format deterministically.
  static String canonicalJsonEncode(dynamic value) {
    return jsonEncode(canonicalizeValue(value));
  }

  /// Normalizes snake_case database column names to canonical camelCase entity field names.
  static String canonicalKey(String key) {
    switch (key) {
      case 'amount_minor':
        return 'amountMinor';
      case 'transaction_type':
        return 'transactionType';
      case 'category_id':
        return 'categoryId';
      case 'account_id':
        return 'accountId';
      case 'to_account_id':
        return 'toAccountId';
      case 'transaction_date_utc':
        return 'transactionDateUtc';
      case 'transaction_time':
        return 'transactionTime';
      case 'attachment_path':
        return 'attachmentPath';
      case 'is_recurring':
        return 'isRecurring';
      case 'recurring_rule_id':
        return 'recurringRuleId';
      case 'icon_code_point':
        return 'iconCodePoint';
      case 'color_value':
        return 'colorValue';
      case 'is_system':
        return 'isSystem';
      case 'is_archived':
        return 'isArchived';
      case 'account_type':
        return 'accountType';
      case 'initial_balance_minor':
        return 'initialBalanceMinor';
      case 'month_year':
        return 'monthYear';
      case 'budget_id':
        return 'budgetId';
      case 'target_amount_minor':
        return 'targetAmountMinor';
      case 'current_amount_minor':
        return 'currentAmountMinor';
      case 'target_date_utc':
        return 'targetDateUtc';
      case 'start_date_utc':
        return 'startDateUtc';
      case 'next_occurrence_utc':
        return 'nextOccurrenceUtc';
      case 'last_executed_date_utc':
        return 'lastExecutedDateUtc';
      case 'is_active':
        return 'isActive';
      case 'created_at_utc':
        return 'createdAtUtc';
      case 'updated_at_utc':
        return 'updatedAtUtc';
      case 'deleted_at_utc':
        return 'deletedAtUtc';
      case 'user_id':
        return 'userId';
      case 'sync_status':
        return 'syncStatus';
      case 'field_timestamps_json':
        return 'fieldTimestampsJson';
      default:
        return key;
    }
  }

  /// Reconciles two JSON/Map payloads representing local and remote entity states.
  ///
  /// Non-overlapping edits (e.g. Device A changed `amount`, Device B changed `note`)
  /// are merged so both changes are preserved.
  /// Overlapping edits (e.g. both modified `amount`) resolve using Field-Level Last-Write-Wins (LWW).
  static FieldConflictResult resolvePayloadConflict({
    required Map<String, dynamic> localPayload,
    required Map<String, dynamic> remotePayload,
    required Map<String, String> localFieldTimestamps,
    required Map<String, String> remoteFieldTimestamps,
    required DateTime localUpdatedAtUtc,
    required DateTime remoteUpdatedAtUtc,
    DateTime? nowUtc,
  }) {
    final defaultRefNow = remoteUpdatedAtUtc.isAfter(localUpdatedAtUtc)
        ? (remoteUpdatedAtUtc.isAfter(DateTime.now().toUtc())
              ? remoteUpdatedAtUtc
              : DateTime.now().toUtc())
        : (localUpdatedAtUtc.isAfter(DateTime.now().toUtc())
              ? localUpdatedAtUtc
              : DateTime.now().toUtc());

    final refNow = nowUtc ?? defaultRefNow;

    final normalizedLocalPayload = localPayload.map(
      (k, v) => MapEntry(canonicalKey(k), v),
    );
    final normalizedRemotePayload = remotePayload.map(
      (k, v) => MapEntry(canonicalKey(k), v),
    );
    final normalizedLocalTimestamps = localFieldTimestamps.map(
      (k, v) => MapEntry(canonicalKey(k), v),
    );
    final normalizedRemoteTimestamps = remoteFieldTimestamps.map(
      (k, v) => MapEntry(canonicalKey(k), v),
    );

    final sanitizedLocalTimestamps = sanitizeFieldTimestamps(
      normalizedLocalTimestamps,
      nowUtc: refNow,
    );
    final sanitizedRemoteTimestamps = sanitizeFieldTimestamps(
      normalizedRemoteTimestamps,
      nowUtc: refNow,
    );

    final mergedPayload = Map<String, dynamic>.from(normalizedLocalPayload);
    final mergedTimestamps = Map<String, String>.from(sanitizedLocalTimestamps);

    int fieldsUpdatedFromRemote = 0;
    int fieldsRetainedFromLocal = 0;
    final List<String> resolvedFields = [];

    // Collect all distinct field keys from both local and remote payloads
    final allKeys = <String>{
      ...normalizedLocalPayload.keys,
      ...normalizedRemotePayload.keys,
    };

    for (final key in allKeys) {
      // Exclude metadata fields handled separately
      if (key == 'fieldTimestampsJson' ||
          key == 'syncStatus' ||
          key == 'id' ||
          key == 'userId' ||
          key == 'createdAtUtc' ||
          key == 'updatedAtUtc' ||
          key == 'deletedAtUtc') {
        continue;
      }

      final hasLocal = normalizedLocalPayload.containsKey(key);
      final hasRemote = normalizedRemotePayload.containsKey(key);

      final localValue = normalizedLocalPayload[key];
      final remoteValue = normalizedRemotePayload[key];

      final localTimeStr = sanitizedLocalTimestamps[key];
      final remoteTimeStr = sanitizedRemoteTimestamps[key];

      final localTime = localTimeStr != null
          ? DateTime.tryParse(localTimeStr)?.toUtc() ?? localUpdatedAtUtc
          : localUpdatedAtUtc;

      final remoteTime = remoteTimeStr != null
          ? DateTime.tryParse(remoteTimeStr)?.toUtc() ?? remoteUpdatedAtUtc
          : remoteUpdatedAtUtc;

      if (!hasLocal && hasRemote) {
        // Field only exists on remote (e.g. newly introduced remote field)
        mergedPayload[key] = remoteValue;
        mergedTimestamps[key] = remoteTime.toIso8601String();
        fieldsUpdatedFromRemote++;
        resolvedFields.add(key);
      } else if (hasLocal && !hasRemote) {
        // Field only exists on local (remote omitted field in partial update)
        mergedPayload[key] = localValue;
        mergedTimestamps[key] = localTime.toIso8601String();
      } else if (remoteTime.isAfter(localTime)) {
        // Remote field is strictly newer
        mergedPayload[key] = remoteValue;
        mergedTimestamps[key] = remoteTime.toIso8601String();
        fieldsUpdatedFromRemote++;
        resolvedFields.add(key);
      } else if (localTime.isAfter(remoteTime)) {
        // Local field is strictly newer
        mergedPayload[key] = localValue;
        mergedTimestamps[key] = localTime.toIso8601String();
        fieldsRetainedFromLocal++;
      } else {
        // Timestamps are equal:
        final localCanonical = canonicalJsonEncode(localValue);
        final remoteCanonical = canonicalJsonEncode(remoteValue);

        if (localCanonical == remoteCanonical) {
          // Values are logically identical (including maps with differing key insertion order) -> clean no-op
          mergedPayload[key] = localValue;
          mergedTimestamps[key] = localTime.toIso8601String();
        } else if (localValue == null && remoteValue != null) {
          // Deterministic intrinsic tie-break: Non-null value takes precedence over null
          mergedPayload[key] = remoteValue;
          mergedTimestamps[key] = remoteTime.toIso8601String();
          fieldsUpdatedFromRemote++;
          resolvedFields.add(key);
        } else if (localValue != null && remoteValue == null) {
          // Deterministic intrinsic tie-break: Non-null value takes precedence over null
          mergedPayload[key] = localValue;
          mergedTimestamps[key] = localTime.toIso8601String();
          fieldsRetainedFromLocal++;
        } else {
          // Deterministic intrinsic tie-break: Lexical comparison of canonical serialized value
          // Ensures merge(A, B) == merge(B, A) regardless of argument arrival direction or JSON key order.
          if (remoteCanonical.compareTo(localCanonical) > 0) {
            mergedPayload[key] = remoteValue;
            mergedTimestamps[key] = remoteTime.toIso8601String();
            fieldsUpdatedFromRemote++;
            resolvedFields.add(key);
          } else {
            mergedPayload[key] = localValue;
            mergedTimestamps[key] = localTime.toIso8601String();
            fieldsRetainedFromLocal++;
          }
        }
      }
    }

    // Preserve the latest overall updatedAt
    final latestUpdatedAt = remoteUpdatedAtUtc.isAfter(localUpdatedAtUtc)
        ? remoteUpdatedAtUtc
        : localUpdatedAtUtc;
    mergedPayload['updatedAtUtc'] = latestUpdatedAt.toIso8601String();

    return FieldConflictResult(
      mergedPayload: mergedPayload,
      mergedFieldTimestamps: mergedTimestamps,
      fieldsUpdatedFromRemote: fieldsUpdatedFromRemote,
      fieldsRetainedFromLocal: fieldsRetainedFromLocal,
      resolvedFieldNames: resolvedFields,
    );
  }

  /// Parses a raw JSON string into a `Map<String, String>` of field timestamps.
  static Map<String, String> parseFieldTimestamps(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
    } catch (_) {}
    return {};
  }

  /// Serializes a `Map<String, String>` into a JSON string.
  static String encodeFieldTimestamps(Map<String, String> timestamps) {
    return jsonEncode(timestamps);
  }

  /// Evaluates tombstone precedence between local and remote states.
  ///
  /// Returns `true` if the entity should be considered deleted (tombstoned).
  static bool shouldRecordBeDeleted({
    required DateTime? localDeletedAtUtc,
    required DateTime? remoteDeletedAtUtc,
    required DateTime localUpdatedAtUtc,
    required DateTime remoteUpdatedAtUtc,
  }) {
    // If both are deleted, it stays deleted
    if (localDeletedAtUtc != null && remoteDeletedAtUtc != null) {
      return true;
    }

    // If locally deleted: only a remote update that is STRICTLY newer than local deletion can un-delete
    if (localDeletedAtUtc != null && remoteDeletedAtUtc == null) {
      return !remoteUpdatedAtUtc.isAfter(localDeletedAtUtc);
    }

    // If remotely deleted: only a local update that is STRICTLY newer than remote deletion can un-delete
    if (remoteDeletedAtUtc != null && localDeletedAtUtc == null) {
      return !localUpdatedAtUtc.isAfter(remoteDeletedAtUtc);
    }

    // Neither is deleted
    return false;
  }

  /// Reconciles full entity state including field conflict merge and tombstone evaluation.
  static FieldConflictResult reconcileEntityState({
    required Map<String, dynamic> localPayload,
    required Map<String, dynamic> remotePayload,
    required Map<String, String> localFieldTimestamps,
    required Map<String, String> remoteFieldTimestamps,
    required DateTime localUpdatedAtUtc,
    required DateTime remoteUpdatedAtUtc,
    required DateTime? localDeletedAtUtc,
    required DateTime? remoteDeletedAtUtc,
    DateTime? nowUtc,
  }) {
    final conflictResult = resolvePayloadConflict(
      localPayload: localPayload,
      remotePayload: remotePayload,
      localFieldTimestamps: localFieldTimestamps,
      remoteFieldTimestamps: remoteFieldTimestamps,
      localUpdatedAtUtc: localUpdatedAtUtc,
      remoteUpdatedAtUtc: remoteUpdatedAtUtc,
      nowUtc: nowUtc,
    );

    final isDeleted = shouldRecordBeDeleted(
      localDeletedAtUtc: localDeletedAtUtc,
      remoteDeletedAtUtc: remoteDeletedAtUtc,
      localUpdatedAtUtc: localUpdatedAtUtc,
      remoteUpdatedAtUtc: remoteUpdatedAtUtc,
    );

    final finalPayload = Map<String, dynamic>.from(
      conflictResult.mergedPayload,
    );
    if (isDeleted) {
      final latestDeletion =
          (localDeletedAtUtc != null && remoteDeletedAtUtc != null)
          ? (localDeletedAtUtc.isAfter(remoteDeletedAtUtc)
                ? localDeletedAtUtc
                : remoteDeletedAtUtc)
          : (localDeletedAtUtc ?? remoteDeletedAtUtc);
      finalPayload['deletedAtUtc'] = latestDeletion?.toIso8601String();
    } else {
      finalPayload['deletedAtUtc'] = null;
    }

    return FieldConflictResult(
      mergedPayload: finalPayload,
      mergedFieldTimestamps: conflictResult.mergedFieldTimestamps,
      fieldsUpdatedFromRemote: conflictResult.fieldsUpdatedFromRemote,
      fieldsRetainedFromLocal: conflictResult.fieldsRetainedFromLocal,
      resolvedFieldNames: conflictResult.resolvedFieldNames,
    );
  }
}
