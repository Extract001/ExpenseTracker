import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/backup/backup_service.dart';
import 'core/backup/export_service.dart';
import 'core/constants/app_constants.dart';
import 'core/network/connectivity_service.dart';
import 'core/security/app_lock_service.dart';
import 'core/security/secure_storage_service.dart';
import 'core/utils/app_logger.dart';
import 'data/auth/auth_service.dart';
import 'data/database/app_database.dart';
import 'data/repositories/account_repository.dart';
import 'data/repositories/budget_repository.dart';
import 'data/repositories/category_repository.dart';
import 'data/repositories/exchange_rate_repository.dart';
import 'data/repositories/goal_repository.dart';
import 'data/repositories/recurring_transaction_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/sync_repository.dart';
import 'data/repositories/transaction_repository.dart';
import 'data/sync/supabase_sync_remote_data_source.dart';
import 'data/sync/sync_coordinator.dart';
import 'presentation/navigation/app_router.dart';
import 'presentation/providers/app_providers.dart';
import 'presentation/providers/settings_provider.dart';
import 'presentation/screens/main_shell_screen.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/widgets/app_lock_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // 1. Initialize encrypted SQLCipher local database
    final db = AppDatabase();

    // 2. Initialize optional live Supabase backend from environment or saved secure credentials
    final secureStorageService = SecureStorageService();
    var supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
    var supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');

    if (supabaseUrl.isEmpty) {
      supabaseUrl = await secureStorageService.read('saved_supabase_url') ?? '';
    }
    if (supabaseAnonKey.isEmpty) {
      supabaseAnonKey =
          await secureStorageService.read('saved_supabase_anon_key') ?? '';
    }

    AuthService? authService;
    SyncCoordinator? syncCoordinator;

    if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
      try {
        // ignore: deprecated_member_use
        await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
        final client = Supabase.instance.client;
        authService = AuthService(supabase: client);
        final remoteDataSource = SupabaseSyncRemoteDataSource(supabase: client);
        final connectivityService = ConnectivityService();
        syncCoordinator = SyncCoordinator(
          db: db,
          connectivityService: connectivityService,
          remoteDataSource: remoteDataSource,
          authService: authService,
          getActiveUserId: () =>
              authService?.currentUser?.id ?? AppConstants.defaultUserId,
        );
      } catch (e) {
        AppLogger.warning('SUPABASE_INIT_ERROR', error: e);
      }
    }

    // 3. Instantiate domain repositories and security services
    final txRepo = TransactionRepository(db);
    final accRepo = AccountRepository(db);
    final catRepo = CategoryRepository(db);
    final budgetRepo = BudgetRepository(db);
    final goalRepo = GoalRepository(db);
    final recRepo = RecurringTransactionRepository(db);
    final settingsRepo = SettingsRepository(db);
    final syncRepo = SyncRepository(db);
    final rateRepo = ExchangeRateRepository(db);

    final backupService = BackupService(db);
    final exportService = ExportService(db);
    final appLockService = AppLockService(secureStorage: secureStorageService);
    await appLockService.initialize();

    // 4. Build comprehensive provider tree
    final providers = AppProviders.buildProviders(
      transactionRepository: txRepo,
      accountRepository: accRepo,
      categoryRepository: catRepo,
      budgetRepository: budgetRepo,
      goalRepository: goalRepo,
      recurringRepository: recRepo,
      settingsRepository: settingsRepo,
      syncRepository: syncRepo,
      exchangeRateRepository: rateRepo,
      syncCoordinator: syncCoordinator,
      authService: authService,
      initialUserId: authService?.currentUser?.id,
      db: db,
      backupService: backupService,
      exportService: exportService,
      appLockService: appLockService,
      secureStorageService: secureStorageService,
    );

    runApp(ExpenseTrackerApp(providers: providers));
  } catch (e, st) {
    AppLogger.error('Application Bootstrap Failed', error: e, stackTrace: st);
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_clock_rounded,
                      size: 64,
                      color: Colors.amber,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Security Fail-Safe Notice',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'The encrypted database could not be initialized securely. '
                      'To protect your financial data from permanent corruption, '
                      'access has been prevented.\n\n'
                      'Detail: ${AppLogger.sanitizeError(e)}',
                      style: const TextStyle(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ExpenseTrackerApp extends StatelessWidget {
  final Widget? home;
  final List<SingleChildWidget>? providers;

  const ExpenseTrackerApp({super.key, this.home, this.providers});

  @override
  Widget build(BuildContext context) {
    Widget app = Builder(
      builder: (context) {
        // Check if SettingsProvider is provided in context tree
        final settingsProvider = context.watch<SettingsProvider?>();
        final themeMode = settingsProvider?.themeMode ?? ThemeMode.system;

        return MaterialApp(
          title: 'Expense Tracker',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          onGenerateRoute: AppRouter.onGenerateRoute,
          home: AppLockGate(child: home ?? const MainShellScreen()),
        );
      },
    );

    if (providers != null && providers!.isNotEmpty) {
      return MultiProvider(providers: providers!, child: app);
    }
    return app;
  }
}
