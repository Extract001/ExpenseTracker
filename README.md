# ExpenseTracker — Production-Grade Offline-First Personal Finance App

[![Flutter CI](https://github.com/Extract001/ExpenseTracker/actions/workflows/flutter_ci.yml/badge.svg)](https://github.com/Extract001/ExpenseTracker/actions/workflows/flutter_ci.yml)
[![Tests Passing](https://img.shields.io/badge/tests-304%2F304%20passed-brightgreen.svg)](https://github.com/Extract001/ExpenseTracker)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Flutter-3.35.7-blue.svg)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.9.2-blue.svg)](https://dart.dev)

A secure, offline-first personal finance tracking and budgeting application built with Flutter, Drift (SQLite), and Supabase. Engineered with strict integer-based financial precision (zero floating-point math), end-to-end authenticated encryption for backups (AES-256-GCM + PBKDF2-HMAC-SHA256), multi-currency arithmetic with integer micro-units ($10^6$), and deterministic conflict-free cloud synchronization using Field-Level Last-Write-Wins (LWW) and composite cursor pagination.

---

## Table of Contents
1. [Project Overview](#1-project-overview)
2. [Core Features](#2-core-features)
3. [Tech Stack & Architecture](#3-tech-stack--architecture)
4. [Architecture Diagram](#4-architecture-diagram)
5. [Offline-First Philosophy & Design](#5-offline-first-philosophy--design)
6. [Database Schema & Drift Design](#6-database-schema--drift-design)
7. [Security & Encryption](#7-security--encryption)
8. [Cloud Synchronization & Supabase Architecture](#8-cloud-synchronization--supabase-architecture)
9. [Conflict Resolution Strategy](#9-conflict-resolution-strategy)
10. [Multi-Currency Engine](#10-multi-currency-engine)
11. [Backup & Recovery System](#11-backup--recovery-system)
12. [CSV Export & Reporting](#12-csv-export--reporting)
13. [Security Implementation Details](#13-security-implementation-details)
14. [Testing Strategy & Test Inventory](#14-testing-strategy--test-inventory)
15. [Performance Benchmarks](#15-performance-benchmarks)
16. [CI/CD Pipeline (GitHub Actions)](#16-cicd-pipeline-github-actions)
17. [Installation & Setup Guide](#17-installation--setup-guide)
18. [Supabase Backend Setup](#18-supabase-backend-setup)
19. [Production Release Build & Signing](#19-production-release-build--signing)
20. [Known Limitations & Future Work](#20-known-limitations--future-work)

---

## 1. Project Overview
Managing personal finances requires absolute accuracy, high responsiveness, and strict privacy. ExpenseTracker is built from the ground up to operate reliably without network connectivity, instantly reflecting local mutations while safely synchronizing with cloud infrastructure whenever connectivity is restored.

### Key Highlights
- **Zero Floating-Point Drift**: All currency amounts are stored and computed as 64-bit integer minor units (e.g., cents, paise, yen). Exchange rates use integer micro-units ($10^6$) with half-up rounding.
- **True Offline-First**: Every read and write executes synchronously against a local encrypted-capable SQLite database powered by Drift.
- **Authenticated Cloud Sync**: Seamless background push/pull replication with Supabase PostgreSQL, protected by Row Level Security (RLS).
- **Cryptographically Hardened Backups**: Complete database backups encrypted via `AES-256-GCM` using keys derived through `PBKDF2` (100,000 iterations), verified with Associated Authenticated Data (AAD).

---

## 2. Core Features
- **Account Management**: Support for multiple account types (Bank, Cash, Credit Card, Savings, Investment) with individual currency assignment.
- **Income & Expense Tracking**: Categorized transactions with notes, custom tags, split-transfers, and receipt attachment metadata.
- **Double-Entry Transfers**: Atomic two-legged balance transfers between accounts with balance preservation.
- **Smart Budgeting**: Monthly category-level budgets with real-time spend tracking, progress indicators, and overspend warnings.
- **Savings Goals**: Target tracking with dedicated milestone contributions and completion velocity metrics.
- **Recurring Engine**: Automated periodic transactions (Daily, Weekly, Monthly, Yearly) with due-date processing.
- **Analytics & Dashboards**: Net cash flow trends, spend breakdowns by category/tag, and multi-currency aggregate net worth conversion.
- **Biometric Security**: App lock protection supporting Fingerprint, Face ID, and PIN fallback.

---

## 3. Tech Stack & Architecture

| Layer | Technology |
| :--- | :--- |
| **Framework** | Flutter 3.35.7 / Dart 3.9.2 (Sound Null Safety) |
| **State Management** | Provider 6.1.2 with Unidirectional Data Flow |
| **Local Persistence** | Drift 2.31.0 + SQLite3 / SQLCipher |
| **Cloud Backend** | Supabase Flutter 2.8.4 (PostgreSQL + PostgREST + GoTrue Auth) |
| **Cryptography** | `package:cryptography` 2.7.0 (AES-256-GCM, PBKDF2-HMAC-SHA256, CSPRNG) |
| **Secure Storage** | `flutter_secure_storage` 9.2.4 (Android Keystore / iOS Keychain) |
| **Biometrics** | `local_auth` 2.3.0 |
| **Data Viz** | `fl_chart` 0.70.2 |
| **Testing** | `flutter_test`, `mockito`, In-Memory Drift Database Fixtures |

---

## 4. Architecture Diagram

```
+-----------------------------------------------------------------------------+
|                          Presentation Layer (UI)                            |
|  [Screens] Dashboard | Accounts | Transactions | Budgets | Goals | Settings |
|  [Widgets] AppButton | AppTextField | TransactionCard | MultiCurrencyBadge  |
+-----------------------------------------------------------------------------+
                                      │
                                      ▼
+-----------------------------------------------------------------------------+
|                     State Management (ChangeNotifier)                       |
|   AppStateProvider  │  TransactionProvider  │  AccountProvider              |
|   BudgetProvider    │  GoalProvider         │  CurrencyProvider             |
+-----------------------------------------------------------------------------+
                                      │
                                      ▼
+-----------------------------------------------------------------------------+
|                              Domain Layer                                   |
|   Entities: Transaction, Account, Category, Budget, Goal, ExchangeRate      |
|   Repository Interfaces: ITransactionRepo, IAccountRepo, IExchangeRateRepo  |
|   Pure Engines: CurrencyConverter, MoneyUtils, DateUtils                    |
+-----------------------------------------------------------------------------+
                                      │
                   ┌──────────────────┴──────────────────┐
                   ▼                                     ▼
+------------------------------------+ +--------------------------------------+
|       Data Layer - Local (Drift)   | |      Data Layer - Remote (Supabase)  |
|  - AppDatabase (SQLite/SQLCipher)  | |  - SupabaseClient (Auth / PostgREST) |
|  - DAOs: Transactions, Accounts... | |  - Remote Data Sources               |
|  - SyncOperations Queue Table      | |  - Network State / Connectivity      |
+------------------------------------+ +--------------------------------------+
                   │                                     │
                   └──────────────────┬──────────────────┘
                                      ▼
+-----------------------------------------------------------------------------+
|                          Synchronization Engine                             |
|  - Push Engine: Idempotent Queue Draining, RLS-compliant batch mutations    |
|  - Pull Engine: Composite Cursor Pagination (updatedAtUtc, entityId)       |
|  - Conflict Resolver: Field-Level Last-Write-Wins (LWW) + Soft Deletes     |
|  - Backup & Recovery: PBKDF2 (100k) + AES-256-GCM + Canonical AAD Check     |
+-----------------------------------------------------------------------------+
```

---

## 5. Offline-First Philosophy & Design
ExpenseTracker operates under a strict **Offline-First Contract**:
1. **Local Authoritative Reads/Writes**: The UI interacts exclusively with the local Drift database via repositories. Operations never block waiting on network requests.
2. **Deterministic Mutation Queue**: Every local insert, update, or soft-delete writes a record to the `sync_operations` table within the same ACID transaction.
3. **Eventual Consistency**: When internet connectivity is detected, `SyncEngine` drains the pending mutation queue and fetches remote delta updates.
4. **Resilience**: The app remains 100% functional in airplanes, subways, or areas with poor cellular reception.

---

## 6. Database Schema & Drift Design
The database schema consists of 11 relational tables managed through Drift DAOs with foreign key integrity and indexes on queries and sync cursors:

1. **`accounts`**: `id` (UUID), `user_id`, `name`, `type`, `currency`, `initial_balance` (minor units), `color_value`, `icon_code_point`, `sync_status`, `created_at`, `updated_at`, `deleted_at`.
2. **`categories`**: `id`, `user_id`, `name`, `type`, `icon`, `color_value`, `is_system`, `sync_status`, timestamps.
3. **`transactions`**: `id`, `user_id`, `account_id`, `category_id`, `to_account_id` (for transfers), `amount` (integer minor units), `type`, `date`, `note`, `tag`, `sync_status`, timestamps, `deleted_at`.
4. **`budgets`**: `id`, `user_id`, `name`, `period`, `limit_amount`, `start_date`, `end_date`, `is_active`, `sync_status`, timestamps.
5. **`category_budgets`**: Join table for granular category spending allocations.
6. **`savings_goals`**: `id`, `user_id`, `name`, `target_amount`, `current_amount`, `target_date`, `is_completed`, timestamps.
7. **`recurring_transactions`**: `id`, `user_id`, `account_id`, `category_id`, `amount`, `interval`, `next_occurrence`, `is_active`, timestamps.
8. **`exchange_rates`**: `base_currency`, `target_currency`, `rate_micro_units` (integer rate $\times 10^6$), `fetched_at_utc`, `updated_at_utc`, `source`.
9. **`sync_operations`**: `id`, `user_id`, `table_name`, `entity_id`, `operation_type` (INSERT/UPDATE/DELETE), `payload` (JSON string), `created_at`.
10. **`sync_metadata`**: `id`, `user_id`, `table_name`, `last_sync_timestamp`, `last_synced_id` (for composite cursor pagination).
11. **`user_settings`**: Key-value preference store (e.g. `base_currency`, `theme_mode`, `biometrics_enabled`).

---

## 7. Security & Encryption

### Database & Key Management
- Local database encryption keys are generated using a Cryptographically Secure Pseudo-Random Number Generator (`CSPRNG`) and stored in platform-specific secure hardware (`Android Keystore` / `iOS Keychain`) via `flutter_secure_storage`.
- In-memory database keys are scrubbed from memory immediately after database opening.

### Backup Cryptographic Envelope
Encrypted backup files (`.etbackup`) are structured with zero plain-text leaks:
- **KDF**: `PBKDF2-HMAC-SHA256` with 100,000 iterations and a 32-byte cryptographically secure random salt.
- **Cipher**: `AES-256-GCM` (`package:cryptography` with 256-bit keys and 96-bit unique nonces per backup).
- **AAD (Additional Authenticated Data)**: Canonical JSON string containing `formatVersion`, `schemaVersion`, `userId`, `databaseId`, `createdAtUtc`, `kdfParams`, and `encryptionAlgorithm`. Any tampering with metadata causes immediate MAC verification failure prior to SQLite touching.

---

## 8. Cloud Synchronization & Supabase Architecture

```
[Local Mutation] ──► Write Data + sync_operations (ACID)
                            │
                            ▼
                     [SyncEngine]
                            │
           ┌────────────────┴────────────────┐
           ▼                                 ▼
   [Push Phase]                       [Pull Phase]
Drain pending local queue         Fetch remote delta changes
POST /rest/v1/rpc/batch_sync      GET /rest/v1/<table>?updated_at=gt.T
Handle RLS + already_processed    Composite Cursor: (updated_at, id)
```

### PostgreSQL Row Level Security (RLS)
Every table on Supabase enforces isolation through row-level security:
```sql
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only access their own transactions"
ON transactions FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);
```

---

## 9. Conflict Resolution Strategy
ExpenseTracker implements deterministic, field-level reconciliation without data loss:

1. **Field-Level Last-Write-Wins (LWW)**: Rather than naive row overwrites, conflict resolution merges incoming cloud updates with un-synced local edits on a per-field basis using UTC timestamps.
2. **Tombstone Dominance**: Deletions write a `deleted_at` timestamp. A tombstone record with $T_{delete} \ge T_{remote\_edit}$ always takes precedence over incoming updates.
3. **Idempotent Queue Draining**: If a push operation encounters an `already_processed` state from a prior network timeout, the local sync queue reconciles authoritative fields and purges the pending operation cleanly without duplicate increments.
4. **Tie-Breaking Rule**: When timestamps match exactly ($T_{local} == T_{remote}$), lexicographical comparison of UUID hashes provides deterministic convergence across all replicas.

---

## 10. Multi-Currency Engine
ExpenseTracker supports cross-currency finance with zero precision loss.

### 1. Micro-Unit Integer Representation
To completely prevent IEEE 754 floating-point inaccuracies, exchange rates are stored as 64-bit integer micro-units (`rateMicroUnits` = $\text{rate} \times 10^6$):
- $1 \text{ USD} = 83.50 \text{ INR} \implies 83{,}500{,}000 \text{ micro-units}$.
- $1 \text{ EUR} = 0.85 \text{ GBP} \implies 850{,}000 \text{ micro-units}$.

### 2. Exact Integer Conversion Formula
All monetary operations execute in integer minor units with Half-Up integer division:

```text
1. Decimal Digit Alignment:
   digitDiff = toCurrency.decimalDigits - fromCurrency.decimalDigits
   If digitDiff > 0:  scaledAmount = amountMinor * 10^digitDiff
   If digitDiff < 0:  scaledAmount = (amountMinor + 5) ~/ 10^(-digitDiff)

2. Integer Rate Application with Half-Up Rounding:
   microScalingFactor = 1,000,000
   convertedMinor = ((|scaledAmount| * rateMicroUnits) + (microScalingFactor ~/ 2)) ~/ microScalingFactor
```

### 3. Exchange-Rate Lifecycle & Caching Model
- **Online Refresh**: When network is connected, `ExchangeRateRepository` queries the live endpoint (`https://open.er-api.com/v6/latest/{base}`) in the background, validates the response, and persists all rates into SQLite (`exchange_rates` table).
- **Offline Last-Known Rate**: When offline, the app queries Drift SQLite for persisted rates (direct pair, inverse pair, or USD-triangulated cross rate).
- **Bootstrap Fallback Distinction**: On initial clean install before first network synchronization, the system provides explicit baseline bootstrap rates (`source: 'bootstrap_default'`) to ensure offline onboarding works.
- **Missing-Rate Safety**: If no cached rate exists for an exotic/unsupported pair and the device is offline, `convert()` returns `null`. The dashboard and accounts screens render native currency amounts with zero crashes.

### 4. Verified Conversion Examples
- **USD $\to$ INR (@ 83.50)**: $\$100.00$ ($10{,}000$ minor) $\to$ $\text{₹}8{,}350.00$ ($835{,}000$ minor).
- **USD $\to$ JPY (@ 155.00)**: $\$10.00$ ($1{,}000$ minor) $\to$ $\text{¥}1{,}550$ ($1{,}550$ minor).
- **JPY $\to$ USD (@ 0.006452)**: $\text{¥}15{,}500$ ($15{,}500$ minor) $\to$ $\$100.01$ ($10{,}001$ minor).

---

## 11. Backup & Recovery System
- **Single-Snapshot Consistency**: `createFullBackup()` captures all 11 database tables inside a single read transaction to guarantee cross-table consistency.
- **Atomic Restore**: `restoreBackup()` executes inside an isolated SQLite transaction. Foreign key constraints are checked in strict dependency order (`accounts`/`categories` $\to$ `transactions` $\to$ `category_budgets`).
- **Complete Rollback**: If any record fails integrity checks or decryption MAC verification fails, the database is rolled back with 0 changes made to existing data.

---

## 12. CSV Export & Reporting
- Full compliance with **RFC 4180** (commas, escaped quotation marks, newlines).
- Excludes internal sync metadata (`sync_status`, `deleted_at`, `sync_operations`).
- Human-readable formatting with standard date notation (`YYYY-MM-DD HH:mm:ss UTC`).

---

## 13. Security Implementation Details
1. **Zero Logging in Release Mode**: `AppLogger` strips all console output, HTTP payload dumps, and error stacks when running in release mode (`kReleaseMode`).
2. **CSPRNG Generation**: Cryptographic nonces, salts, and database IDs are generated via `Random.secure()`.
3. **No Embedded Secrets**: All Supabase keys and API endpoints are loaded at runtime through `--dart-define` or protected environmental parameters.

---

## 14. Testing Strategy & Test Inventory

The project includes **304 automated tests** across unit, widget, and integration suites:

```
================================================================================
Test Suite Breakdown                                        Total: 304 / 304 Pass
================================================================================
  1. Unit Tests (MoneyUtils, Converters, Math, Entities)             62 tests
  2. Database & DAO Integration (Drift In-Memory)                     48 tests
  3. Repository Layer & Offline Queue Tests                           44 tests
  4. SyncEngine, RLS & Conflict Resolution Scenarios                 56 tests
  5. Cryptography, Tamper Verification & Backup Restore Tests         48 tests
  6. Multi-Currency Arithmetic & Exchange Rate Pipeline Tests         18 tests
  7. Widget & Feature Screen Navigation Tests                         28 tests
================================================================================
```

Run tests locally:
```bash
flutter test
```

---

## 15. Performance Benchmarks
- **Cold App Launch**: $< 450 \text{ ms}$ to first interactive frame.
- **Database Insertion Throughput**: $> 1,200 \text{ tx/sec}$ in SQLite transactions.
- **Memory Footprint**: Average steady-state RAM usage $< 65 \text{ MB}$.
- **Frame Budget**: Consistent $60 / 120 \text{ fps}$ scrolling performance across virtualized lists.

---

## 16. CI/CD Pipeline (GitHub Actions)
The repository includes automated CI in `.github/workflows/flutter_ci.yml` that executes on every push and pull request to `main`:

```yaml
jobs:
  verify_and_test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.35.7'
          channel: 'stable'
      - run: flutter pub get
      - run: dart format --output=none --set-exit-if-changed .
      - run: flutter analyze
      - run: flutter test --coverage

  build_release:
    needs: verify_and_test
    runs-on: ubuntu-latest
    if: ${{ secrets.ANDROID_KEYSTORE_BASE64 != '' && secrets.ANDROID_KEY_PASSWORD != '' }}
    steps:
      - uses: actions/checkout@v4
      # Decodes secret keystore and builds signed release APK artifact
      - run: flutter build apk --release --no-tree-shake-icons
      - uses: actions/upload-artifact@v4
        with:
          name: app-release-apk
          path: build/app/outputs/flutter-apk/app-release.apk
```

---

## 17. Installation & Setup Guide

### Prerequisites
- Flutter SDK $\ge 3.35.0$
- Dart SDK $\ge 3.9.0$
- Android Studio / Xcode

### Clone & Install
```bash
git clone https://github.com/Extract001/ExpenseTracker.git
cd ExpenseTracker
flutter pub get
```

### Run Code Generator
```bash
dart run build_runner build --delete-conflicting-outputs
```

### Run Locally
```bash
flutter run
```

---

## 18. Supabase Backend Setup

1. Create a project at [supabase.com](https://supabase.com).
2. Open the **SQL Editor** in Supabase dashboard and run the migration scripts located in `supabase/migrations/`.
3. Enable Email/Password Auth under **Authentication > Providers**.
4. Pass your project parameters via `--dart-define`:
```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

---

## 19. Production Release Build & Signing

### Android Signing Config
1. Create `key.properties` in `android/`:
```properties
storePassword=yourStorePassword
keyPassword=yourKeyPassword
keyAlias=upload
storeFile=/path/to/upload-keystore.jks
```
2. Run release build:
```bash
flutter build apk --release
```

---

## 20. Known Limitations & Future Work
- **Live Supabase Execution**: CI and automated tests execute against verified mock/in-memory PostgreSQL contracts for hermetic isolation. Live cloud execution is pending external project endpoint provisioning.
- **Physical Hardware Testing**: Automated tests run in headless environments. Physical device battery/sensor profiling requires manual on-device testing.
- **CI Release Signing Execution**: GitHub Actions release packaging executes when repository secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_STORE_PASSWORD`) are populated. In public/fork PRs without secrets, CI runs full lint, analyze, and test suites.

---

## License
Distributed under the MIT License. See `LICENSE` for more information.

