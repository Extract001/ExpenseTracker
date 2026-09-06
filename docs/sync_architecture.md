# Cloud Sync Architecture Specification: Offline-First Expense Tracker

This document defines the production architecture, data flow, conflict resolution algorithms, queue management, security policies, and schema mappings for the Cloud Synchronization subsystem of the Offline-First Expense Tracker.

---

## 1. Core Architectural Invariants & Data Flow

### 1.1 Local-First Unidirectional Pipeline
The local encrypted Drift database (backed by AES-256 SQLCipher) is the **single authoritative persistent source of truth** for the application UI. The presentation and repository layers operate entirely against the local database and have zero direct dependencies on network availability or Supabase servers.

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                           PRESENTATION LAYER                            │
│           (Widgets, Screens, Theme, Navigation, View Models)            │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │ Reads & Writes
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                             PROVIDER LAYER                              │
│       (TransactionProvider, AccountProvider, BudgetProvider, etc.)      │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │ Domain Operations
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         DOMAIN REPOSITORY LAYER                         │
│  (ITransactionRepository, IAccountRepository, ICategoryRepository, etc.)│
└────────────────────────────────────┬────────────────────────────────────┘
                                     │ CRUD + Queue Enqueue
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       DATA & LOCAL DATABASE LAYER                       │
│    ┌───────────────────────────────┐   ┌───────────────────────────┐    │
│    │    Encrypted Drift DB DAOs    │   │    Sync Queue Table       │    │
│    │  (Accounts, Categories, etc.) │   │     (sync_operations)     │    │
│    └───────────────────────────────┘   └─────────────┬─────────────┘    │
└──────────────────────────────────────────────────────┼──────────────────┘
                                                       │ Poll / Stream
                                                       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         CLOUD SYNC SUBSYSTEM                            │
│    ┌───────────────────────────────┐   ┌───────────────────────────┐    │
│    │     Connectivity Monitor      │───▶│     Sync Coordinator      │    │
│    │     (connectivity_plus)       │   │  (ISyncCoordinator)      │    │
│    └───────────────────────────────┘   └─────────────┬─────────────┘    │
└──────────────────────────────────────────────────────┼──────────────────┘
                                                       │ HTTPS RPC / WSS
                                                       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           SUPABASE CLOUD                                │
│    ┌───────────────────────────────┐   ┌───────────────────────────┐    │
│    │         Supabase Auth         │   │   apply_sync_mutation RPC │    │
│    │     (auth.users / tokens)     │   │   (Field-Level Merge)     │    │
│    └───────────────────────────────┘   └───────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Pipeline Invariants
1. **Zero UI Network Blocking**: UI mutations immediately update local Drift tables and enqueue sync operations in a single local database transaction. The UI updates optimistically with sub-16ms latency.
2. **Zero Remote Direct Reads for UI**: The UI never queries Supabase directly. All UI queries subscribe to Drift reactive streams or load from local DAOs.
3. **Decoupled Sync Engine**: Remote synchronization occurs asynchronously in the background via the `SyncCoordinator`. Network interruptions or HTTP 5xx/4xx errors never abort or roll back local user actions.
4. **Security Principle of Least Privilege**: Client-side code exclusively uses the Supabase `anon` public key. The administrative `service_role` key is strictly prohibited in client bundles. All cloud security is enforced at the database level using PostgreSQL Row Level Security (RLS) with explicit `WITH CHECK` clauses.

---

## 2. Server-Side Field-Level Merge & Stored Procedure

### 2.1 The Problem with Whole-Record `updated_at_utc` Overwrite
If a cloud push executed standard `INSERT ... ON CONFLICT (id) DO UPDATE ... WHERE EXCLUDED.updated_at_utc >= existing.updated_at_utc`, a newer record timestamp would overwrite the entire row, silently discarding legitimate changes made on other devices to different fields.

### 2.2 PL/pgSQL Stored Procedure: `apply_sync_mutation`
In Supabase PostgreSQL, synchronization mutations are dispatched via the `apply_sync_mutation` RPC. This function performs true **Field-Level Last-Write-Wins (LWW)** reconciliation:

```sql
CREATE OR REPLACE FUNCTION public.apply_sync_mutation(
    p_operation_id UUID,
    p_entity_type TEXT,
    p_entity_id UUID,
    p_operation_type TEXT,
    p_payload JSONB,
    p_field_timestamps JSONB,
    p_updated_at_utc TIMESTAMPTZ,
    p_deleted_at_utc TIMESTAMPTZ DEFAULT NULL
) RETURNS JSONB ...
```

### 2.3 Server-Side Reconciliation Steps
1. **Auth & Identity Check**: Validates `auth.uid() = user_id`.
2. **Operation Idempotency Guard**: Checks if `(user_id, idempotency_token)` exists in `sync_audit_log`. If found, returns `{"status": "already_processed"}` without re-applying mutations.
3. **Clock Skew Protection**: Any field timestamp exceeding `now() + 5 minutes` is clamped to server `now()`.
4. **Independent Field Comparison**:
   For each field $F$:
   - If $T_{\text{incoming}}(F) > T_{\text{existing}}(F)$ (or field does not exist in existing state), update column $F$ to incoming value and update $T_{\text{merged}}(F) = T_{\text{incoming}}(F)$.
   - Otherwise, preserve existing column $F$ and $T_{\text{existing}}(F)$.
5. **Tombstone Evaluation**: Evaluates deletion timestamp against update timestamps. Older edits cannot revive newer soft-deletions; explicit newer edits un-delete the record.
6. **Atomic Audit Logging**: Writes `(user_id, entity_type, entity_id, operation_type, idempotency_token, now())` to `sync_audit_log` before committing.

---

## 3. True Two-Tier Idempotency & Operation Token Ownership

### 3.1 Entity-Level Idempotency
- Every entity has a client-generated RFC 4122 UUID v4 primary key.
- Repeated inserts of the same entity update the existing row in place without creating duplicate entities.

### 3.2 Operation-Level Idempotency
- Each queued sync operation generates a unique RFC 4122 UUID v4 `id` (`operation_id`).
- When network connections drop or timeouts occur, the client retries with the same `operation_id`.
- The database enforces `CONSTRAINT uq_user_idempotency_token UNIQUE (user_id, idempotency_token)`.
- Replaying the same operation token is an atomic no-op returning `already_processed`.

### 3.3 Operation Token Ownership & Cross-User Security
- Idempotency tokens are strictly scoped to the authenticated user via composite uniqueness `(user_id, idempotency_token)` and Row Level Security `auth.uid() = user_id`.
- User A's token cannot be accessed, hijacked, or replayed by User B.

---

## 4. Field Timestamp Security & Clock Skew Model

### 4.1 Clock Drift Invariant
Client clocks can drift or be intentionally set to future dates (e.g. year 2099) in an attempt to permanently win all future conflict merges.

### 4.2 Clamping Safeguard
- Both client-side `ConflictResolver.sanitizeFieldTimestamps` and server-side `apply_sync_mutation` enforce a strict **5-minute forward clock skew limit**:
  $$\text{Allowed Timestamp} \le \text{Server Time} + 5\text{ minutes}$$
- Any field timestamp exceeding this boundary is automatically clamped to server `now()`.
- Legitimate subsequent updates with real timestamps can overwrite the record normally.

---

## 5. Deterministic Incremental Sync Cursor

### 5.1 The Timestamp Collision Invariant
Multiple records modified within the same millisecond or transaction share identical `updated_at_utc` timestamps. Advancing a cursor by timestamp alone causes unread records with identical timestamps to be permanently skipped.

### 5.2 Composite Cursor Architecture
- Composite token format: `"${timestampUtc.toIso8601String()}|${entityId}"`.
- Implemented in `SyncCursor`.
- Query ordering clause:
  ```sql
  WHERE user_id = :userId 
    AND (updated_at_utc > :cursorTime 
         OR (updated_at_utc = :cursorTime AND id > :cursorId))
  ORDER BY updated_at_utc ASC, id ASC
  LIMIT :limit;
  ```
- Backed by compound PostgreSQL indexes:
  `CREATE INDEX idx_<table_name>_user_cursor ON public.<table_name> (user_id, updated_at_utc ASC, id ASC);`

---

## 6. Tombstone & Soft-Delete Precedence Matrix

| Local / Existing State | Remote / Incoming State | Conflict Condition | Reconciled Result |
|---|---|---|---|
| Deleted at $T_{\text{del}}$ | Edited at $T_{\text{edit}}$ ($T_{\text{edit}} < T_{\text{del}}$) | Device B was offline and edited note before Device A deleted the record. | **Deletion wins**. The record remains soft-deleted. |
| Deleted at $T_{\text{del}}$ | Restored/Edited at $T_{\text{restore}}$ ($T_{\text{restore}} > T_{\text{del}}$) | Device B explicitly un-deleted or edited after deletion timestamp. | **Newer edit wins**. Record is un-deleted with merged fields. |
| Active (not deleted) | Deleted at $T_{\text{del}}$ ($T_{\text{del}} > T_{\text{edit}}$) | Remote deletion occurred after local edit. | **Deletion wins**. Record is soft-deleted. |
| Both soft-deleted | Both soft-deleted | Both devices deleted the record. | **Remains deleted** with $\max(T_{\text{delLocal}}, T_{\text{delRemote}})$. |

---

## 7. Row Level Security (RLS) Policy Specifications

### 7.1 Security Architecture
Every remote table in Supabase has Row Level Security enabled (`ALTER TABLE ... ENABLE ROW LEVEL SECURITY;`). All policies evaluate against `auth.uid()`.

### 7.2 Strict Policies with `WITH CHECK`
For all tables (`categories`, `accounts`, `transactions`, `budgets`, `category_budgets`, `savings_goals`, `recurring_transactions`, `user_settings`, `sync_audit_log`):
- **SELECT**: `FOR SELECT TO authenticated USING (auth.uid() = user_id)`
- **INSERT**: `FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id)`
- **UPDATE**: `FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id)`
- **DELETE**: `FOR DELETE TO authenticated USING (auth.uid() = user_id)`

---

## 8. Network Resilience, Retry Strategy & Connectivity

### 8.1 Exponential Backoff Schedule
Failed sync operations are retried according to an exponential backoff formula:
$$\text{Delay}(n) = \min(2^n \text{ seconds} + \text{jitter}, 60 \text{ seconds})$$
- Attempt 1: 2s
- Attempt 2: 4s
- Attempt 3: 8s
- Attempt 4: 16s
- Attempt 5: 32s
- Maximum Attempts: 5. If 5 attempts fail, operation status is marked `failed` with diagnostic `error_message` preserved in `sync_operations`.

### 8.2 Connectivity Monitoring
`ConnectivityService` listens to network state changes using `connectivity_plus`. When transitioning from `offline` $\rightarrow$ `online`, `SyncCoordinator` resets transient failure counts and triggers an incremental sync cycle.
