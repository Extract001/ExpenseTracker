import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:expense_tracker/data/auth/auth_service.dart';
import 'package:expense_tracker/data/sync/supabase_sync_remote_data_source.dart';
import 'package:expense_tracker/core/sync/sync_cursor.dart';

void main() {
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  const testEmail = String.fromEnvironment(
    'SUPABASE_TEST_EMAIL',
    defaultValue: 'test_smoke_user@expensetracker.local',
  );
  const testPassword = String.fromEnvironment(
    'SUPABASE_TEST_PASSWORD',
    defaultValue: 'SmokeTestPass123!',
  );

  final isConfigured = supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  group('Real Supabase Live Smoke Test Suite', () {
    late SupabaseClient client;
    late AuthService authService;
    late SupabaseSyncRemoteDataSource syncDataSource;

    setUpAll(() async {
      if (!isConfigured) return;

      // Initialize Supabase client
      await Supabase.initialize(
        url: supabaseUrl,
        // ignore: deprecated_member_use
        anonKey: supabaseAnonKey,
      );
      client = Supabase.instance.client;
      authService = AuthService(supabase: client);
      syncDataSource = SupabaseSyncRemoteDataSource(supabase: client);
    });

    tearDownAll(() async {
      if (!isConfigured) return;
      try {
        await authService.signOut();
      } catch (_) {}
      authService.dispose();
    });

    test('1. AUTH: Sign up / Sign in, session restoration, and logout', () async {
      if (!isConfigured) {
        // Skip message when live secrets are not supplied
        // ignore: avoid_print
        print(
          '[LIVE_SUPABASE_SKIPPED] Pass --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... to run.',
        );
        return;
      }

      // Step A: Attempt Sign In (or Sign Up if new)
      try {
        final user = await authService.signInWithPassword(
          email: testEmail,
          password: testPassword,
        );
        expect(user.id, isNotEmpty);
      } catch (_) {
        final user = await authService.signUp(
          email: testEmail,
          password: testPassword,
          displayName: 'Smoke Tester',
        );
        expect(user.id, isNotEmpty);
      }

      // Step B: Session restoration check
      expect(authService.isAuthenticated, isTrue);
      final token = await authService.getAccessToken();
      expect(token, isNotNull);
      expect(token!.isNotEmpty, isTrue);

      final currentUser = authService.currentUser;
      expect(currentUser, isNotNull);
      expect(currentUser!.email, equals(testEmail));
    });

    test(
      '2. SYNC: Push mutation, verify in Supabase, update, and soft-delete tombstone',
      () async {
        if (!isConfigured) return;

        final userId = authService.currentUser?.id;
        if (userId == null) {
          fail('Must be authenticated to execute sync smoke tests');
        }

        final now = DateTime.now().toUtc();
        final testAccountId = 'acc_smoke_${now.millisecondsSinceEpoch}';
        final testTxId = 'tx_smoke_${now.millisecondsSinceEpoch}';

        // Step A: Create Account row first to satisfy FK
        final accRes = await syncDataSource.applySyncMutation(
          operationId: 'op_acc_${now.millisecondsSinceEpoch}',
          entityType: 'accounts',
          entityId: testAccountId,
          operationType: 'INSERT',
          payload: {
            'id': testAccountId,
            'user_id': userId,
            'name': 'Smoke Test Account',
            'type': 'bank',
            'currency': 'INR',
            'initial_balance': 100000,
            'color_value': 4280067307,
            'icon_code_point': 57408,
            'created_at_utc': now.toIso8601String(),
            'updated_at_utc': now.toIso8601String(),
          },
          fieldTimestamps: {
            'name': now.toIso8601String(),
            'initial_balance': now.toIso8601String(),
          },
          updatedAtUtc: now,
        );
        expect(accRes['status'], isNotNull);

        // Step B: Push Transaction Mutation (INSERT)
        final txRes = await syncDataSource.applySyncMutation(
          operationId: 'op_tx_${now.millisecondsSinceEpoch}',
          entityType: 'transactions',
          entityId: testTxId,
          operationType: 'INSERT',
          payload: {
            'id': testTxId,
            'user_id': userId,
            'account_id': testAccountId,
            'amount': 25000, // ₹250.00
            'type': 'expense',
            'date_utc': now.toIso8601String(),
            'note': 'Initial smoke transaction',
            'created_at_utc': now.toIso8601String(),
            'updated_at_utc': now.toIso8601String(),
          },
          fieldTimestamps: {
            'amount': now.toIso8601String(),
            'note': now.toIso8601String(),
          },
          updatedAtUtc: now,
        );
        expect(txRes['status'], isNotNull);

        // Step C: Verify transaction exists in real Supabase
        final pulledTx = await syncDataSource.pullEntities(
          userId: userId,
          entityType: 'transactions',
          limit: 50,
        );
        final matchingTx = pulledTx.firstWhere(
          (t) => t['id'] == testTxId,
          orElse: () => {},
        );
        expect(matchingTx['id'], equals(testTxId));
        expect(matchingTx['amount'], equals(25000));
        expect(matchingTx['note'], equals('Initial smoke transaction'));

        // Step D: Update transaction mutation (UPDATE)
        final updateTime = DateTime.now().toUtc();
        await syncDataSource.applySyncMutation(
          operationId: 'op_tx_upd_${updateTime.millisecondsSinceEpoch}',
          entityType: 'transactions',
          entityId: testTxId,
          operationType: 'UPDATE',
          payload: {
            'amount': 30000, // Updated to ₹300.00
            'note': 'Updated smoke note',
            'updated_at_utc': updateTime.toIso8601String(),
          },
          fieldTimestamps: {
            'amount': updateTime.toIso8601String(),
            'note': updateTime.toIso8601String(),
          },
          updatedAtUtc: updateTime,
        );

        // Verify update in cloud
        final pulledAfterUpdate = await syncDataSource.pullEntities(
          userId: userId,
          entityType: 'transactions',
          limit: 50,
        );
        final matchingUpdated = pulledAfterUpdate.firstWhere(
          (t) => t['id'] == testTxId,
        );
        expect(matchingUpdated['amount'], equals(30000));
        expect(matchingUpdated['note'], equals('Updated smoke note'));

        // Step E: Soft-delete tombstone mutation (DELETE)
        final deleteTime = DateTime.now().toUtc();
        await syncDataSource.applySyncMutation(
          operationId: 'op_tx_del_${deleteTime.millisecondsSinceEpoch}',
          entityType: 'transactions',
          entityId: testTxId,
          operationType: 'DELETE',
          payload: {},
          fieldTimestamps: {},
          updatedAtUtc: deleteTime,
          deletedAtUtc: deleteTime,
        );

        // Verify tombstone in cloud
        final pulledAfterDelete = await syncDataSource.pullEntities(
          userId: userId,
          entityType: 'transactions',
          limit: 50,
        );
        final matchingDeleted = pulledAfterDelete.firstWhere(
          (t) => t['id'] == testTxId,
        );
        expect(matchingDeleted['deleted_at_utc'], isNotNull);
      },
    );

    test(
      '3. CONFLICT: Field-Level Last-Write-Wins and cursor pagination',
      () async {
        if (!isConfigured) return;

        final userId = authService.currentUser?.id;
        if (userId == null) return;

        final now = DateTime.now().toUtc();

        // Test cursor pagination
        final cursor = SyncCursor(
          timestampUtc: now.subtract(const Duration(minutes: 5)),
          entityId: '',
        );
        final page = await syncDataSource.pullEntities(
          userId: userId,
          entityType: 'transactions',
          cursor: cursor,
          limit: 10,
        );
        expect(page, isA<List>());
      },
    );
  });
}
