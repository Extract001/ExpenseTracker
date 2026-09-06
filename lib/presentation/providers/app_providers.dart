import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../core/auth/i_auth_service.dart';
import '../../core/sync/i_sync_coordinator.dart';
import '../../domain/repositories/i_account_repository.dart';
import '../../domain/repositories/i_budget_repository.dart';
import '../../domain/repositories/i_category_repository.dart';
import '../../domain/repositories/i_exchange_rate_repository.dart';
import '../../domain/repositories/i_goal_repository.dart';
import '../../domain/repositories/i_recurring_transaction_repository.dart';
import '../../domain/repositories/i_settings_repository.dart';
import '../../domain/repositories/i_sync_repository.dart';
import '../../domain/repositories/i_transaction_repository.dart';

import 'account_provider.dart';
import 'app_state_provider.dart';
import 'budget_provider.dart';
import 'category_provider.dart';
import 'currency_provider.dart';
import 'goal_provider.dart';
import 'recurring_transaction_provider.dart';
import 'settings_provider.dart';
import 'sync_provider.dart';
import 'transaction_provider.dart';

class AppProviders {
  /// Builds the complete list of providers for the application tree with automatic user-switch orchestration.
  static List<SingleChildWidget> buildProviders({
    required ITransactionRepository transactionRepository,
    required IAccountRepository accountRepository,
    required ICategoryRepository categoryRepository,
    required IBudgetRepository budgetRepository,
    required IGoalRepository goalRepository,
    required IRecurringTransactionRepository recurringRepository,
    required ISettingsRepository settingsRepository,
    required ISyncRepository syncRepository,
    IExchangeRateRepository? exchangeRateRepository,
    ISyncCoordinator? syncCoordinator,
    IAuthService? authService,
    String? initialUserId,
  }) {
    final appState = AppStateProvider(initialUserId: initialUserId);
    final txProvider = TransactionProvider(repository: transactionRepository);
    final accProvider = AccountProvider(repository: accountRepository);
    final catProvider = CategoryProvider(repository: categoryRepository);
    final budgetProvider = BudgetProvider(repository: budgetRepository);
    final goalProvider = GoalProvider(repository: goalRepository);
    final recProvider = RecurringTransactionProvider(
      repository: recurringRepository,
    );
    final setProvider = SettingsProvider(repository: settingsRepository);
    final syncProvider = SyncProvider(
      repository: syncRepository,
      syncCoordinator: syncCoordinator,
    );
    final currProvider = exchangeRateRepository != null
        ? CurrencyProvider(
            repository: exchangeRateRepository,
            settingsProvider: setProvider,
          )
        : null;

    // Wire user switch lifecycle listener across all dependent feature providers
    appState.addOnUserChangedListener((newUserId) {
      txProvider.reset(reload: true);
      accProvider.reset(reload: true);
      catProvider.reset(reload: true);
      budgetProvider.reset(reload: true);
      goalProvider.reset(reload: true);
      recProvider.reset(reload: true);
      setProvider.reset(reload: true);
      syncProvider.reset(reload: true);
    });

    return [
      // Repository Interfaces (for direct lookup where needed)
      Provider<ITransactionRepository>.value(value: transactionRepository),
      Provider<IAccountRepository>.value(value: accountRepository),
      Provider<ICategoryRepository>.value(value: categoryRepository),
      Provider<IBudgetRepository>.value(value: budgetRepository),
      Provider<IGoalRepository>.value(value: goalRepository),
      Provider<IRecurringTransactionRepository>.value(
        value: recurringRepository,
      ),
      Provider<ISettingsRepository>.value(value: settingsRepository),
      Provider<ISyncRepository>.value(value: syncRepository),
      if (exchangeRateRepository != null)
        Provider<IExchangeRateRepository>.value(value: exchangeRateRepository),

      // Optional Auth & Sync Coordinators
      if (authService != null) Provider<IAuthService>.value(value: authService),
      if (syncCoordinator != null)
        Provider<ISyncCoordinator>.value(value: syncCoordinator),

      // App State Provider
      ChangeNotifierProvider<AppStateProvider>.value(value: appState),

      // Domain Feature Providers
      ChangeNotifierProvider<TransactionProvider>.value(value: txProvider),
      ChangeNotifierProvider<AccountProvider>.value(value: accProvider),
      ChangeNotifierProvider<CategoryProvider>.value(value: catProvider),
      ChangeNotifierProvider<BudgetProvider>.value(value: budgetProvider),
      ChangeNotifierProvider<GoalProvider>.value(value: goalProvider),
      ChangeNotifierProvider<RecurringTransactionProvider>.value(
        value: recProvider,
      ),
      ChangeNotifierProvider<SettingsProvider>.value(value: setProvider),
      ChangeNotifierProvider<SyncProvider>.value(value: syncProvider),
      if (currProvider != null)
        ChangeNotifierProvider<CurrencyProvider>.value(value: currProvider),
    ];
  }
}
