# Security, Backup & Recovery Architecture Specification

**Project:** ExpenseTracker  
**Phase:** 8 (Security, Backup & Recovery Hardening)  
**Classification:** Financial Application Technical Specification  

---

## 1. Threat Model & Security Objectives (CIA+R)

The ExpenseTracker application models threat actors ranging from opportunistic physical device attackers (lost/stolen device, shoulder surfing) to malicious network adversaries and compromised local file access. To defend personal financial information, the security architecture strictly enforces the **CIA+R** model:

| Objective | Threat Addressed | Primary Architectural Control |
| :--- | :--- | :--- |
| **Confidentiality** | Unauthorized inspection of financial records, PIN disclosure, credential leakage, key theft. | SQLCipher 256-bit AES database encryption at rest, Android Keystore / iOS Keychain encrypted storage, memory session wiping, sanitized logging. |
| **Integrity** | Malicious tampering with database files, corrupted backups, modified sync mutations, timing attacks. | Constant-time comparison on PINs/secrets, HMAC-SHA256 authenticated backup packaging, atomic database transactions, foreign key constraints. |
| **Availability** | Offline lockouts, corrupted encryption keys, network partition, interrupted write operations. | Offline-first local database, persistent sync queue, transaction-level rollback on error, fail-safe key verification. |
| **Recoverability** | Device loss, file corruption, accidental record deletion, unrecoverable local state. | Transactional full snapshots, password-protected encrypted archives, sync cursor reconciliation, clear separation from CSV reporting. |

---

## 2. Encryption at Rest & Key Management Lifecycle

### 2.1 Database Encryption via SQLCipher
* **Cipher Engine:** SQLCipher (via `sqlcipher_flutter_libs` and Drift `NativeDatabase`).
* **Algorithm:** 256-bit AES-CBC with HMAC-SHA512 per-page authentication.
* **Compatibility:** SQLCipher 4 (`PRAGMA cipher_compatibility = 4;`).
* **Key Format:** 256-bit entropy generated using cryptographically secure pseudorandom number generator (`Random.secure()`), represented as a 64-character hexadecimal string.

### 2.2 Key Lifecycle & Fail-Safe Invariant
Key retrieval and initialization are governed by a strict state machine implemented in `SecureStorageService` and `EncryptedDatabaseConnection`:

```
                 [App Launch]
                      │
           Does DB file exist on disk?
             /                 \
          [YES]               [NO]
           /                     \
   Read key from secure storage   Read key from secure storage
       /               \             /                 \
  [Found & Valid]    [Missing]  [Found & Valid]     [Missing]
      │                 │            │                 │
 Open Database   CRITICAL FAIL-SAFE  Open Database  Generate new 256-bit
                  THROW DatabaseKey                  CSPRNG key, write to
                  MissingException!                 secure storage, open DB
```

> **CRITICAL ARCHITECTURAL GUARANTEE:**
> If an existing database file is detected on disk and its encryption key is missing or corrupted, the system **NEVER** silently generates a new key. Generating a new key would attempt to open an existing encrypted database with the wrong key, triggering database corruption or permanently stranding the user's financial history. The system immediately halts with `DatabaseKeyMissingException`, logging a sanitized error event.

---

## 3. Cryptographic Standards & PIN Verification

### 3.1 Work Factor & Salt Configuration
* **Interactive PIN Hashing:** RFC 2898 / PKCS #5 v2.0 **PBKDF2-HMAC-SHA256** with **10,000 iterations** (configured to balance brute-force resistance against mobile CPU responsiveness during device unlock).
* **Backup Archive KDF:** RFC 2898 / PKCS #5 v2.0 **PBKDF2-HMAC-SHA256** with **100,000 iterations** (versioned via `BackupKdfParams`, providing stronger offline brute-force resistance for exported backup archives).
* **Salt Entropy:** 16-byte cryptographically secure random salt generated via `Random.secure()`, encoded as hexadecimal or URL-safe base64.
* **Digest Length:** 32 bytes (256 bits), represented as a 64-character lowercase hex string.

### 3.2 Side-Channel Defense: Constant-Time Comparison
Standard string and byte equality (`==`) exhibits early-exit behavior, which can leak timing information proportional to the number of matching leading characters.
To mitigate timing side-channel attacks against user PINs and authentication tags, `HashingService` implements bitwise XOR accumulation intended to reduce timing leakage:

$$\text{accumulator} = |A| \oplus |B|$$
$$\forall i \in [0, \min(|A|, |B|)): \quad \text{accumulator} = \text{accumulator} \mid (A[i] \oplus B[i])$$
$$\text{return } \text{accumulator} == 0$$

### 3.3 Backward-Compatible Migration Path
To prevent existing users from being locked out when upgrading from earlier multi-round SHA-256 loop implementations:
1. `verifyPin()` checks the candidate PIN against the stored hash using a constant-time comparison implementation intended to reduce timing leakage.
2. If verification fails, it tests the candidate PIN against the legacy multi-round SHA-256 algorithm using a constant-time comparison implementation intended to reduce timing leakage.
3. Upon a successful legacy match, the service transparently upgrades the stored hash to PBKDF2-HMAC-SHA256.

---

## 4. App Lock & Session Security

### 4.1 Timeout Enforcement
The `AppLockService` enforces application lock state based on user-configured timeouts:
* `Immediate`: Locks immediately upon transitioning to the background (`onAppPaused`).
* `1 minute`: Locks if background duration exceeds 60 seconds.
* `5 minutes`: Locks if background duration exceeds 300 seconds (default).
* `15 minutes`: Locks if background duration exceeds 900 seconds.
* `Never`: Application lock disabled.

### 4.2 Brute-Force Rate Limiting
To protect against rapid PIN guessing on physical devices:
* Failed attempt counter increments on each failed PIN submission.
* Upon 5 consecutive failed attempts, the service activates a 30-second lockout window (`_lockoutUntilUtc`).
* Any unlock attempt during active lockout throws `SecurityException(code: 'RATE_LIMITED')`.
* A successful authentication resets the failed attempts counter to 0.

### 4.3 Memory Hygiene & Session Wiping
* User authentication tokens, PIN hashes, and decrypted in-memory states are strictly isolated from static global scope.
* When logging out or switching accounts, `wipeSession()` clears all in-memory timestamps, failure counters, and cached secrets.

---

## 5. Transactional Backup & Recovery Engine

### 5.1 Comprehensive Snapshot Scope & Isolation
A system recovery backup captures a point-in-time snapshot across all 11 Drift database tables:
1. `users`
2. `categories`
3. `accounts`
4. `budgets`
5. `category_budgets`
6. `savings_goals`
7. `recurring_transactions`
8. `transactions`
9. `settings`
10. `sync_metadata`
11. `sync_operations`

**Snapshot Consistency Guarantee:**
All 11 table reads occur inside a single atomic Drift/SQLite read transaction (`await _db.transaction(() async { ... })`). In SQLite with Write-Ahead Logging (WAL), an active transaction guarantees repeatable-read snapshot isolation. All tables reflect the exact state of the database at the instant the transaction begins; concurrent writes cannot result in torn or inconsistent backup snapshots.

### 5.2 Field-Level Metadata & Tombstone Preservation
To ensure that restored backups seamlessly participate in Field-Level Last-Write-Wins conflict resolution:
* Every entity's `fieldTimestampsJson` vector is serialized and preserved verbatim.
* Every deleted record's `deletedAtUtc` tombstone is preserved verbatim.
* Restoring a backup preserves original UUIDs and created/updated UTC timestamps.

### 5.3 Authenticated Encryption with Associated Data (AEAD)
Encrypted backups use standard **AES-256-GCM** authenticated encryption via `package:cryptography 2.9.0`:

```json
{
  "metadata": {
    "formatVersion": 1,
    "appVersion": "1.0.0",
    "schemaVersion": 1,
    "createdAtUtc": "2026-09-06T10:00:00.000Z",
    "userId": "user-uuid",
    "databaseId": "db_12345",
    "checksum": "<16-byte-gcm-mac-tag-hex>",
    "isEncrypted": true,
    "encryptionAlgorithm": "AES-256-GCM",
    "kdfParams": {
      "algorithm": "PBKDF2-HMAC-SHA256",
      "iterations": 100000,
      "saltBytesLength": 16,
      "keyBitsLength": 256,
      "version": 1
    },
    "encryptionSalt": "<16-byte-salt-hex>",
    "nonce": "<12-byte-nonce-hex>",
    "entityCounts": { "transactions": 150, "accounts": 4 }
  },
  "ciphertext": "<base64-aes-256-gcm-ciphertext>"
}
```

#### Cryptographic Invariants & Authenticity Coverage:
1. **Cipher & Mode:** AES-256 in Galois/Counter Mode (GCM), standard authenticated encryption with associated data (AEAD) (`AesGcm.with256bits()`).
2. **Nonce/IV:** 12 bytes (96 bits) cryptographically random nonce generated per encryption via `AesGcm.with256bits().newNonce()`.
3. **Key Derivation:** PBKDF2-HMAC-SHA256 with 100,000 iterations deriving a 256-bit AES key. Parameters are versioned in `BackupKdfParams`. This parameterization was chosen as a practical balance between brute-force resistance and mobile responsiveness.
4. **Additional Authenticated Data (AAD):** The metadata container (`formatVersion`, `appVersion`, `schemaVersion`, `createdAtUtc`, `userId`, `databaseId`, `encryptionAlgorithm`, `kdfParams`, `encryptionSalt`, and `nonce`) is canonicalized and authenticated as AAD.
5. **Entity Counts Metadata:** `entityCounts` in the metadata header is untrusted informational metadata (intended solely for UI backup inspection and audit logging). The restore engine never relies on `entityCounts` for validation, record count enforcement, or database insertion; all restored entities and actual counts are derived strictly from the authenticated, decrypted plaintext payload. Modifying `entityCounts` cannot bypass validation or corrupt restored database contents.
6. **Integrity vs Authenticity Terminology:**
   * **Unencrypted Archives:** Use a canonical SHA-256 digest (`checksum`) for corruption detection.
   * **Encrypted Archives:** Store the 16-byte (128-bit) AES-GCM Message Authentication Code (`checksum: macTagHex`). Authentication occurs cryptographically via AEAD before any database mutation can begin.
7. **Tamper Resistance:** Any modification to `userId`, `formatVersion`, `schemaVersion`, `kdfParams`, `salt`, `nonce`, `ciphertext`, or `checksum` causes AES-GCM MAC verification to fail immediately upon decryption. Plaintext is never exposed if the tag or metadata does not authenticate.
8. **Zero Stored Secrets:** Neither user passwords nor derived encryption keys are stored in the backup container.

### 5.4 Transactional Restore, Domain Invariants & Atomic Rollback
Restore operations run inside an atomic `db.transaction()`:
1. **Format & Schema Validation:** Version numbers must be $\le$ supported current versions.
2. **Integrity & Authenticity Check:** Checksum / AES-GCM MAC verified before database mutation.
3. **Cross-User Protection:** If `backup.userId != activeUserId`, rejected unless explicit migration authorized.
4. **Money & Domain Invariants:**
   * Transactions: `amountMinor > 0` (strictly positive minor units; paise/cents).
   * Budgets: `amountMinor > 0`.
   * Category Budgets: `amountMinor > 0`.
   * Savings Goals: `targetAmountMinor > 0` (`currentAmountMinor >= 0`).
   * Recurring Transactions: `amountMinor > 0`.
   * **Account Opening Balance (Intentional Exception):** May legitimately be negative (e.g. credit card debt, overdraft), zero, or positive.
5. **Foreign Key Integrity:** Categories, accounts, and budgets must exist before child records can reference them.
6. **Full Replace Semantics & Atomic Rollback:**
   * Existing records for user deleted in child-first dependency order: transactions, recurring transactions, category budgets, budgets, savings goals, accounts, custom categories (system categories preserved), settings, sync operations, sync metadata.
   * Restored records inserted via `insertOnConflictUpdate`.
   * If ANY validation fails or an error occurs at any point, SQLite automatically **ROLLS BACK** the entire transaction, leaving the pre-existing database untouched.

### 5.5 Restore + Sync Reconciliation Policy & Idempotency
* **Sync Cursors:** The backup's `syncCursor` from `sync_metadata` is restored to timestamp $T_{backup}$. Restored composite cursors use `(updatedAtUtc, entityId)` ordering:
  ```text
  updatedAtUtc > cursorTimestamp
  OR (updatedAtUtc == cursorTimestamp AND entityId > cursorEntityId)
  ```
  This guarantees that records sharing the same millisecond timestamp are neither skipped nor duplicated.
* **Next Sync Pull:** The sync engine fetches all remote mutations that occurred after the restored cursor.
* **Deterministic Convergence:** The `ConflictResolver` applies Field-Level Last-Write-Wins against restored local entities using preserved `fieldTimestampsJson`. Newer remote field edits survive; older remote edits lose to local edits made prior to $T_{backup}$.
* **Sync Operations Queue Policy:**
  * **Case A (`restoreSyncQueue: true`):** Restored pending operations are re-inserted with original mutation IDs. Unsynced local edits are safely retried on next push.
  * **Case B (`already_processed` Idempotency):** If an operation was already committed by the server, the server returns `already_processed` along with the authoritative `merged_record`. The client deserializes the authoritative state, reconciles it locally via `ConflictResolver.reconcileEntityState`, updates the local entity, and only then deletes the queue operation and marks the entity `synced`. This prevents any stale-local-data-but-marked-synced state.
  * **Case C (`restoreSyncQueue: false`):** Pending operations are cleared from the queue. Restored entities have their `syncStatus` set to `'synced'` so that no orphaned pending records remain without corresponding queue items. Subsequent cloud pulls retrieve any newer remote changes.

### 5.6 Architectural Separation: Backup vs CSV Export
* `BackupService`: Complete relational snapshot preserving internal UUIDs, foreign keys, sync cursors, field-level vector timestamps, and tombstones for disaster recovery.
* `ExportService`: Human-readable RFC 4180 CSV export of financial transactions with major-currency units for spreadsheet analysis. Excludes cryptographic keys, sync metadata, and internal database structures.

---

## 6. Information Leakage Prevention & Sanitized Logging

The `AppLogger` enforces a sanitization boundary preventing sensitive financial and personal data leakage into log files, console output, or telemetry:

* **Strict Key Redaction:** Any map key matching or containing `amount`, `balance`, `note`, `description`, `title`, `pin`, `password`, `token`, `secret`, `key`, `email`, or `accountName` is automatically masked to `[REDACTED]`.
* **String Sanitization:** Automatic regex filters redact email addresses (`[EMAIL_REDACTED]`) and 32-to-64 character hexadecimal secrets (`[KEY_REDACTED]`) from error messages and stack traces.
* **Production Safety:** In release mode, production logs contain only high-level operational tags (`[TRANSACTION_SYNC]`, `[BACKUP_RESTORE]`), durations, and sanitized error categories.

---

## 7. Performance Benchmarks & Real-Device Limitations

### 7.1 Performance Benchmark Results
* **Test Environment:** Automated headless Flutter test runner (Dart 3.11 VM on 64-bit Windows workstation).
* **Workload:** 10,000 full transaction records, 10 accounts, 20 categories, foreign keys, and timestamps.
* **Observed Execution Time:**
  - Full backup snapshot generation: ~1.4 seconds.
  - Full transactional restore and database commit: ~1.7 seconds.
* **Memory Finding:** The 10,000-transaction benchmark completed successfully in the test environment without OutOfMemory. Actual Android/iOS production-device memory characteristics require real-device validation under operating system memory constraints.

### 7.2 Explicit Real-Device Limitations
Automated unit and integration test suites prove algorithmic correctness and database transaction semantics under controlled host conditions, but they do **NOT** fully prove real-world hardware behavior:
1. **Hardware Keystore Behavior:** Android Keystore (Keymaster/StrongBox) and iOS Keychain hardware backing may exhibit device-specific biometric timeouts, key invalidation upon lock screen credential reset, or manufacturer-specific key storage bugs.
2. **Biometric Hardware Integration:** Physical fingerprint and face sensors are subject to false rejection rates, sensor dirt/failure, and cancellation behaviors that cannot be simulated purely with unit test mocks.
3. **Power Interruption During Restore:** While SQLite WAL mode and Drift `db.transaction()` guarantee ACID transactional atomicity, catastrophic sudden physical power loss or battery pull during flash writes can cause filesystem-level corruption requiring OS-level fsck or file recovery.
4. **Physical Memory Pressure:** Low-end mobile devices (1GB–2GB RAM) running under active system memory pressure may aggressively kill background processes or garbage collect large JSON string buffers differently than 64-bit development workstations.
5. **Real-Device SQLCipher Key Retrieval:** Platform channel latency and Android/iOS secure storage retrieval timing under cold start must be measured on physical devices.
6. **Production Supabase Network Conditions:** Real carrier cellular networks introduce packet drops, captive portals, TLS renegotiation timeouts, and high-latency mobile handoffs that require end-to-end staging validation against real Supabase endpoints.
