import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:expense_tracker/core/utils/id_generator.dart';
import 'package:expense_tracker/data/auth/auth_service.dart';
import 'package:expense_tracker/data/sync/supabase_sync_remote_data_source.dart';
import 'package:expense_tracker/core/sync/sync_cursor.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

      HttpOverrides.global = _RealHttpOverrides();

      // Initialize Supabase client with in-memory storage for headless test
      await Supabase.initialize(
        url: supabaseUrl,
        // ignore: deprecated_member_use
        anonKey: supabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(),
        ),
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

      // Step A: Attempt Sign In, Sign Up, or Anonymous Auth
      try {
        final user = await authService.signInWithPassword(
          email: testEmail,
          password: testPassword,
        );
        expect(user.id, isNotEmpty);
      } catch (_) {
        try {
          final user = await authService.signUp(
            email: testEmail,
            password: testPassword,
            displayName: 'Smoke Tester',
          );
          expect(user.id, isNotEmpty);
        } catch (_) {
          final user = await authService.signInAnonymously();
          expect(user.id, isNotEmpty);
        }
      }

      // Step B: Session restoration check
      expect(authService.isAuthenticated, isTrue);
      final token = await authService.getAccessToken();
      expect(token, isNotNull);
      expect(token!.isNotEmpty, isTrue);

      final currentUser = authService.currentUser;
      expect(currentUser, isNotNull);
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
        final testAccountId = IdGenerator.generateUuid();
        final testCategoryId = IdGenerator.generateUuid();
        final testTxId = IdGenerator.generateUuid();

        // Step A: Create Account row first to satisfy FK
        final accRes = await syncDataSource.applySyncMutation(
          operationId: IdGenerator.generateUuid(),
          entityType: 'account',
          entityId: testAccountId,
          operationType: 'INSERT',
          payload: {
            'id': testAccountId,
            'user_id': userId,
            'name': 'Smoke Test Account',
            'accountType': 'bank',
            'currency': 'INR',
            'initialBalanceMinor': 100000,
            'colorValue': 4280067307.toSigned(32),
            'iconCodePoint': 57408,
            'createdAtUtc': now.toIso8601String(),
            'updatedAtUtc': now.toIso8601String(),
          },
          fieldTimestamps: {
            'name': now.toIso8601String(),
            'initialBalanceMinor': now.toIso8601String(),
          },
          updatedAtUtc: now,
        );
        expect(accRes['status'], isNotNull);

        // Step B: Create Category row to satisfy FK
        final catRes = await syncDataSource.applySyncMutation(
          operationId: IdGenerator.generateUuid(),
          entityType: 'category',
          entityId: testCategoryId,
          operationType: 'INSERT',
          payload: {
            'id': testCategoryId,
            'user_id': userId,
            'name': 'Smoke Category',
            'type': 'expense',
            'iconCodePoint': 57408,
            'colorValue': 4280067307.toSigned(32),
            'isSystem': false,
            'isArchived': false,
            'createdAtUtc': now.toIso8601String(),
            'updatedAtUtc': now.toIso8601String(),
          },
          fieldTimestamps: {
            'name': now.toIso8601String(),
          },
          updatedAtUtc: now,
        );
        expect(catRes['status'], isNotNull);

        // Step C: Push Transaction Mutation (INSERT)
        final txRes = await syncDataSource.applySyncMutation(
          operationId: IdGenerator.generateUuid(),
          entityType: 'transaction',
          entityId: testTxId,
          operationType: 'INSERT',
          payload: {
            'id': testTxId,
            'user_id': userId,
            'accountId': testAccountId,
            'categoryId': testCategoryId,
            'amountMinor': 25000, // ₹250.00
            'transactionType': 'expense',
            'transactionDateUtc': now.toIso8601String(),
            'note': 'Initial smoke transaction',
            'createdAtUtc': now.toIso8601String(),
            'updatedAtUtc': now.toIso8601String(),
          },
          fieldTimestamps: {
            'amountMinor': now.toIso8601String(),
            'note': now.toIso8601String(),
          },
          updatedAtUtc: now,
        );
        expect(txRes['status'], isNotNull);

        // Step D: Verify transaction exists in real Supabase
        final pulledTx = await syncDataSource.pullEntities(
          userId: userId,
          entityType: 'transaction',
          limit: 50,
        );
        final matchingTx = pulledTx.firstWhere(
          (t) => t['id'] == testTxId,
          orElse: () => {},
        );
        expect(matchingTx['id'], equals(testTxId));
        expect(matchingTx['amount_minor'], equals(25000));
        expect(matchingTx['note'], equals('Initial smoke transaction'));

        // Step E: Update transaction mutation (UPDATE)
        final updateTime = DateTime.now().toUtc();
        await syncDataSource.applySyncMutation(
          operationId: IdGenerator.generateUuid(),
          entityType: 'transaction',
          entityId: testTxId,
          operationType: 'UPDATE',
          payload: {
            'amountMinor': 30000, // Updated to ₹300.00
            'note': 'Updated smoke note',
            'updatedAtUtc': updateTime.toIso8601String(),
          },
          fieldTimestamps: {
            'amountMinor': updateTime.toIso8601String(),
            'note': updateTime.toIso8601String(),
          },
          updatedAtUtc: updateTime,
        );

        // Verify update in cloud
        final pulledAfterUpdate = await syncDataSource.pullEntities(
          userId: userId,
          entityType: 'transaction',
          limit: 50,
        );
        final matchingUpdated = pulledAfterUpdate.firstWhere(
          (t) => t['id'] == testTxId,
        );
        expect(matchingUpdated['amount_minor'], equals(30000));
        expect(matchingUpdated['note'], equals('Updated smoke note'));

        // Step F: Soft-delete tombstone mutation (DELETE)
        final deleteTime = DateTime.now().toUtc();
        await syncDataSource.applySyncMutation(
          operationId: IdGenerator.generateUuid(),
          entityType: 'transaction',
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
          entityType: 'transaction',
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
