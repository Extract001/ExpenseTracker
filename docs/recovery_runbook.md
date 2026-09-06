# Disaster Recovery & Operational Runbook

**Project:** ExpenseTracker  
**Phase:** 8 (Security, Backup & Recovery Hardening)  
**Target Audience:** DevOps, Support Engineers, and Application Maintainers  

---

## Scenario 1: Device Lost or Stolen

### Impact
Device containing encrypted SQLite database and locally cached session token is in unknown hands.

### Immediate Action Checklist
1. **Revoke Remote Supabase Session:**
   - Log into Supabase Admin Console or trigger user session revocation:
     ```sql
     -- Invalidate all active refresh tokens for the compromised user
     DELETE FROM auth.refresh_tokens WHERE user_id = '<USER_UUID>';
     ```
2. **Rotate Master Credentials:**
   - Prompt the user to perform a remote password reset on Supabase Auth from a secure computer.
3. **Local Data Protection Invariant:**
   - The local database is encrypted with SQLCipher 256-bit AES.
   - The key is secured in Android Keystore / iOS Keychain hardware security module.
   - Unless the device OS PIN/biometrics are broken, the local database remains cryptographically inaccessible.
4. **New Device Provisioning:**
   - User signs into new device.
   - Initial pull will populate all cloud-synchronized accounts and transactions.
   - If user maintained a local encrypted backup file on external storage, restore following Scenario 5.

---

## Scenario 2: Database Corruption Detected

### Symptoms
* App launch crashes with `SqliteException` or `DatabaseCorruptedException`.
* Drift query fails with `database disk image is malformed`.

### Step-by-Step Resolution Procedure
1. **Quarantine Malformed Database:**
   - Do NOT delete the corrupted file immediately.
   - Rename `expense_tracker.enc.sqlite` to `expense_tracker.enc.sqlite.corrupt.<TIMESTAMP>`.
2. **Inspect Encryption Key Integrity:**
   - Confirm key exists in secure storage using `SecureStorageService.hasDatabaseKey()`.
   - If key was lost, reference Scenario 2B (Missing Key Fail-Safe).
3. **Re-initialize Clean Database:**
   - Instantiate fresh `AppDatabase`. On first open, Drift will recreate all tables and default seeds.
4. **Restore Financial Data:**
   - If Supabase Cloud sync is configured: sign in. The sync engine will automatically execute an initial pull, repopulating all cloud-stored accounts, categories, and transactions.
   - If offline: locate the most recent `.json` backup file and trigger `BackupService.restoreFromBackup(backupJson, targetUserId: activeUserId)`.

---

## Scenario 3: Backup File Corrupted or Tampered

### Symptoms
* Restore fails with `BackupRestoreException: Backup checksum verification failed` or `invalid JSON format`.

### Diagnostic & Safe Fallback Procedure
1. **Do NOT Force Bypass:**
   - Never disable checksum or HMAC verification to force a restore. A corrupted backup may contain partially written or truncated records that violate relational integrity.
2. **Verify Backup Origin:**
   - Check if the backup was modified by a text editor (line endings CRLF vs LF can alter plain text hashes if not using canonical JSON).
3. **Check Cryptographic Password:**
   - If the backup is password-protected, verify whether the user entered the correct passphrase. An incorrect passphrase or corrupted archive causes AES-GCM MAC authentication to fail.
4. **Locate Alternate Snapshot:**
   - Search device storage or cloud drives for the next most recent valid backup file.
   - Run `BackupArchive.fromJson(jsonDecode(backupText)).verifyChecksum()` in a safe sandbox before applying to the database.

---

## Scenario 4: Wrong Backup Selected (e.g. Account Collision)

### Symptoms
* Restore fails with `SecurityException: Backup belongs to user "USER_A", but active user is "USER_B"`.

### Safe Resolution
1. **Root Cause Analysis:**
   - The user is currently authenticated as User B, but attempted to restore a backup file generated while logged in as User A.
2. **If Intentional Account Migration:**
   - If User B is a newly created cloud account and the user explicitly intends to import guest data from User A:
     - Invoke `BackupService.restoreFromBackup(..., targetUserId: userB_Id, allowCrossUserRestore: true)`.
     - The service will reassign all restored entities to `userB_Id`.
3. **If Accidental Selection:**
   - Reject the restore. Switch the active session to User A or select the correct backup belonging to User B.

---

## Scenario 5: Device Migration (Old Phone -> New Phone)

### Objective
Migrate all financial history, custom categories, recurring rules, and sync cursors to a new device without data loss.

### Step-by-Step Procedure
1. **On Old Phone:**
   - Open Settings -> System Backup.
   - Tap **Create Encrypted Backup**.
   - Enter a strong backup password (derives AES-256-GCM AEAD encryption key via PBKDF2 with 100,000 iterations).
   - Export the resulting `.enc.json` backup file via secure share (AirDrop, Nearby Share, or encrypted flash drive).
2. **On New Phone:**
   - Install ExpenseTracker on the new device.
   - Launch app (generates new local database and new device-specific encryption key).
   - Sign in with the user's Supabase account.
   - Navigate to Settings -> Restore Backup.
   - Select the `.enc.json` backup file and enter the backup password.
   - Tap **Restore**.
3. **Verification:**
   - `BackupService` will transactionally restore all tables, preserving `fieldTimestampsJson` and `deletedAtUtc`.
   - The sync engine will trigger a synchronization pull using the restored `syncCursor`. Any changes made in the cloud since the backup will be seamlessly merged via Field-Level Last-Write-Wins.

---

## Scenario 6: Supabase Cloud Authentication Unavailable (Offline Emergency)

### Symptoms
* HTTP 503 / Network Timeout on login or sync.
* User needs immediate emergency access to record expenses or view account balances.

### Operational Procedure
1. **Automatic Offline Transition:**
   - ExpenseTracker is strictly offline-first. The user can continue using the application in Guest or Offline Mode without cloud connectivity.
2. **Queueing Local Operations:**
   - All transactions, account balance changes, and category edits are committed to the local SQLCipher database immediately.
   - Corresponding sync mutations are enqueued in `sync_operations` with `createdAtUtc` timestamps.
3. **Recovery on Cloud Restoration:**
   - When network connectivity returns, `SyncCoordinator` detects network availability via `connectivity_plus`.
   - Queued mutations are pushed in order of foreign key dependency.
   - Transient network errors use exponential backoff and never wipe or drop unsent records.

---

## Scenario 7: Cloud Data Divergence After Backup Restore

### Situation
A user restored a backup from 7 days ago, but other devices made edits to accounts and transactions over the past week.

### Reconciliation & Convergence Behavior
1. **Automatic Reconciliation via Phase 7 Conflict Resolution:**
   - When the backup is restored, `sync_metadata` resets `syncCursor` to the backup timestamp ($T - 7\text{d}$).
   - The next sync pull fetches all server mutations with `updated_at > T - 7\text{d}`.
   - For every entity:
     - If the remote field timestamp is newer than the restored local field timestamp: **Remote field wins**.
     - If the local field timestamp is newer or equal: **Restored local field wins**.
     - If an entity was deleted on the cloud during the 7 days: **Tombstone wins**, entity marked deleted locally.
2. **Zero Infinite Ping-Pong:**
   - The synchronization converges in finite steps without queue cycling.
3. **No Stale Replay:**
   - The pending sync queue is not blindly replayed against the server, preventing stale overrides.

---

## Scenario 8: Interrupted Restore / Power Loss Mid-Operation

### Situation
The device battery dies or the OS kills the process in the middle of executing `restoreFromBackup()`.

### Guarantees & Recovery
1. **SQLite Transaction Atomicity (ACID):**
   - The entire restore operation executes inside `_db.transaction(() async { ... })`.
   - SQLite uses write-ahead logging (WAL) / rollback journal.
   - An interrupted transaction is NEVER committed at the database engine level.
   - Upon next launch, SQLite automatically detects the incomplete journal and rolls back all uncommitted writes.
2. **Pre-Restore State Preservation:**
   - The database returns to its state prior to the interrupted restore under ordinary process interruption.
   - *Note on Hardware Power Cuts:* While SQLite provides ACID rollbacks, extreme hardware-level power loss during active flash block writes can result in underlying OS filesystem or storage block damage requiring OS-level fsck.
3. **User Action:**
   - Charge device and restart application.
   - Re-run the restore operation from Settings.
