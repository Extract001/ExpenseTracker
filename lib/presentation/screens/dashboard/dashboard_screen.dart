import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/currency_constants.dart';
import '../../../domain/entities/enums.dart';
import '../../providers/account_provider.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extensions.dart';
import '../../widgets/add_transaction_modal.dart';
import '../../widgets/amount_display.dart';
import '../../widgets/app_card.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_header.dart';
import '../../widgets/transaction_tile.dart';
import '../accounts/accounts_screen.dart';
import '../goals/goals_screen.dart';
import '../transactions/transaction_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onNavigateToTransactions;
  final VoidCallback? onNavigateToBudgets;

  const DashboardScreen({
    super.key,
    this.onNavigateToTransactions,
    this.onNavigateToBudgets,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AccountProvider>().watchAccounts();
        context.read<CategoryProvider>().watchCategories();
        context.read<TransactionProvider>().watchRecentTransactions();
        context.read<TransactionProvider>().loadTotals();
        context.read<BudgetProvider>().watchBudgetForSelectedMonth();
        context.read<GoalProvider>().watchGoals();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Consumer<AppStateProvider>(
          builder: (context, appState, _) {
            final userName = appState.currentUserId == 'local_guest_user'
                ? 'Personal'
                : appState.currentUserId;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Hello, $userName',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Expense Manager',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Accounts',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AccountsScreen()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final txProvider = context.read<TransactionProvider>();
          final accProvider = context.read<AccountProvider>();
          final budgetProvider = context.read<BudgetProvider>();
          final goalProvider = context.read<GoalProvider>();
          await Future.wait([
            txProvider.loadTransactions(),
            txProvider.loadTotals(),
            accProvider.loadAccounts(),
            budgetProvider.loadBudgetForSelectedMonth(),
            goalProvider.loadGoals(),
          ]);
        },
        child: ListView(
          padding: AppSpacing.screenPadding,
          children: [
            // 1. Net Worth Summary Card
            _buildNetWorthSummaryCard(context),
            AppSpacing.gapH16,

            // 2. Quick Actions Row (Expense, Income, Transfer)
            _buildQuickActionsRow(context),
            AppSpacing.gapH24,

            // 3. Accounts Overview Horizontal Carousel
            _buildAccountsOverview(context),
            AppSpacing.gapH24,

            // 4. Budget Summary Card
            _buildBudgetSummary(context),
            AppSpacing.gapH24,

            // 5. Savings Goals Summary Card
            _buildGoalsSummary(context),
            AppSpacing.gapH24,

            // 6. Recent Transactions Section Header
            SectionHeader(
              title: 'Recent Transactions',
              actionLabel: 'See All',
              onActionPressed: widget.onNavigateToTransactions,
            ),
            AppSpacing.gapH8,

            // Recent Transactions List
            _buildRecentTransactionsList(context),
            AppSpacing.gapH32,
          ],
        ),
      ),
    );
  }

  Widget _buildNetWorthSummaryCard(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;

    final baseCurrency = context.select<SettingsProvider, String>(
      (s) => s.currency,
    );
    final currSymbol = CurrencyConstants.getCurrency(baseCurrency).symbol;

    final netWorthMinor = context.select<AccountProvider, int>(
      (acc) => acc.totalNetWorthMinor,
    );
    final incomeMinor = context.select<TransactionProvider, int>(
      (tx) => tx.totalIncomeMinor,
    );
    final expenseMinor = context.select<TransactionProvider, int>(
      (tx) => tx.totalExpenseMinor,
    );

    return AppCard(
      padding: AppSpacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AmountDisplay(
            label: 'Total Net Worth',
            amountMinor: netWorthMinor,
            currencySymbol: currSymbol,
            amountStyle: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          AppSpacing.gapH16,
          const Divider(),
          AppSpacing.gapH16,
          Row(
            children: [
              // Income summary
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: financeColors.incomeContainer,
                        borderRadius: AppRadius.card,
                      ),
                      child: Icon(
                        Icons.arrow_downward_rounded,
                        size: 16,
                        color: financeColors.income,
                      ),
                    ),
                    AppSpacing.gapW8,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Income', style: theme.textTheme.bodySmall),
                          MoneyText(
                            amountMinor: incomeMinor,
                            currencySymbol: currSymbol,
                            type: TransactionType.income,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Divider
              Container(height: 36, width: 1, color: financeColors.cardBorder),
              AppSpacing.gapW16,

              // Expense summary
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: financeColors.expenseContainer,
                        borderRadius: AppRadius.card,
                      ),
                      child: Icon(
                        Icons.arrow_upward_rounded,
                        size: 16,
                        color: financeColors.expense,
                      ),
                    ),
                    AppSpacing.gapW8,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Expenses', style: theme.textTheme.bodySmall),
                          MoneyText(
                            amountMinor: expenseMinor,
                            currencySymbol: currSymbol,
                            type: TransactionType.expense,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsRow(BuildContext context) {
    final financeColors = context.financeColors;

    return Row(
      children: [
        Expanded(
          child: _QuickActionButton(
            label: 'Expense',
            icon: Icons.remove_rounded,
            color: financeColors.expense,
            bgColor: financeColors.expenseContainer,
            onTap: () => AddTransactionModal.show(
              context,
              initialType: TransactionType.expense,
            ),
          ),
        ),
        AppSpacing.gapW12,
        Expanded(
          child: _QuickActionButton(
            label: 'Income',
            icon: Icons.add_rounded,
            color: financeColors.income,
            bgColor: financeColors.incomeContainer,
            onTap: () => AddTransactionModal.show(
              context,
              initialType: TransactionType.income,
            ),
          ),
        ),
        AppSpacing.gapW12,
        Expanded(
          child: _QuickActionButton(
            label: 'Transfer',
            icon: Icons.swap_horiz_rounded,
            color: financeColors.transfer,
            bgColor: financeColors.transferContainer,
            onTap: () => AddTransactionModal.show(
              context,
              initialType: TransactionType.transfer,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountsOverview(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = context.watch<AccountProvider>().accounts;

    if (accounts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Accounts Overview',
          actionLabel: 'Manage',
          onActionPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AccountsScreen()),
            );
          },
        ),
        AppSpacing.gapH8,
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: accounts.length,
            separatorBuilder: (_, __) => AppSpacing.gapW12,
            itemBuilder: (context, index) {
              final acc = accounts[index];
              final icon = IconData(
                acc.iconCodePoint,
                fontFamily: 'MaterialIcons',
              );
              final color = Color(acc.colorValue);

              return AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CategoryIcon(
                      icon: icon,
                      color: color,
                      size: 40,
                      iconSize: 20,
                    ),
                    AppSpacing.gapW12,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          acc.name,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        AppSpacing.gapH2,
                        MoneyText(
                          amountMinor: acc.initialBalance,
                          currencySymbol: CurrencyConstants.getCurrency(
                            acc.currency,
                          ).symbol,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBudgetSummary(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;
    final budgetProvider = context.watch<BudgetProvider>();

    final monthlyBudget = budgetProvider.monthlyBudget;
    if (monthlyBudget == null || budgetProvider.totalBudgetLimitMinor == 0) {
      return const SizedBox.shrink();
    }

    final limitMinor = budgetProvider.totalBudgetLimitMinor;
    final spentMinor = budgetProvider.totalSpentMinor;
    final remainingMinor = budgetProvider.remainingBudgetMinor;
    final progress = budgetProvider.budgetProgressPercentage;
    final isOver = budgetProvider.isOverBudget;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Monthly Budget',
          actionLabel: 'Details',
          onActionPressed: widget.onNavigateToBudgets,
        ),
        AppSpacing.gapH8,
        AppCard(
          padding: AppSpacing.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Budget Progress',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${progress.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: isOver
                          ? financeColors.expense
                          : theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              AppSpacing.gapH8,
              LinearProgressIndicator(
                value: (progress / 100.0).clamp(0.0, 1.0),
                backgroundColor: financeColors.surfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isOver ? financeColors.expense : theme.colorScheme.primary,
                ),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              AppSpacing.gapH12,
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Spent', style: theme.textTheme.bodySmall),
                      MoneyText(
                        amountMinor: spentMinor,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isOver ? financeColors.expense : null,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isOver ? 'Over Budget' : 'Remaining',
                        style: theme.textTheme.bodySmall,
                      ),
                      MoneyText(
                        amountMinor: isOver
                            ? (spentMinor - limitMinor)
                            : remainingMinor,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isOver
                              ? financeColors.expense
                              : financeColors.income,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGoalsSummary(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;
    final goalProvider = context.watch<GoalProvider>();
    final activeGoals = goalProvider.activeGoals;

    if (activeGoals.isEmpty) return const SizedBox.shrink();

    final totalSaved = goalProvider.totalSavedMinor;
    final totalTarget = goalProvider.totalTargetMinor;
    final progress = totalTarget > 0
        ? ((totalSaved / totalTarget) * 100.0).clamp(0.0, 100.0)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Savings Goals',
          actionLabel: 'View All',
          onActionPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GoalsScreen()),
            );
          },
        ),
        AppSpacing.gapH8,
        AppCard(
          padding: AppSpacing.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${activeGoals.length} Active Goals',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${progress.toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: financeColors.income,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              AppSpacing.gapH8,
              LinearProgressIndicator(
                value: (progress / 100.0).clamp(0.0, 1.0),
                backgroundColor: financeColors.surfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(financeColors.income),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              AppSpacing.gapH12,
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Saved', style: theme.textTheme.bodySmall),
                      MoneyText(
                        amountMinor: totalSaved,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: financeColors.income,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Target', style: theme.textTheme.bodySmall),
                      MoneyText(
                        amountMinor: totalTarget,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentTransactionsList(BuildContext context) {
    final txProvider = context.watch<TransactionProvider>();
    final catProvider = context.watch<CategoryProvider>();
    final accProvider = context.watch<AccountProvider>();

    if (txProvider.isLoadingInitial && txProvider.recentTransactions.isEmpty) {
      return const TransactionListSkeleton(itemCount: 4);
    }

    if (txProvider.error != null && txProvider.recentTransactions.isEmpty) {
      return ErrorState(
        message: txProvider.error!,
        onRetry: () => txProvider.loadTransactions(),
      );
    }

    final recents = txProvider.recentTransactions;
    if (recents.isEmpty) {
      return AppCard(
        child: EmptyState(
          title: 'No transactions yet',
          message:
              'Add your first transaction to start tracking your expenses.',
          actionLabel: 'Add Transaction',
          onActionPressed: () => AddTransactionModal.show(context),
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: recents.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, index) {
          final tx = recents[index];
          final category = catProvider.getCategoryById(tx.categoryId);
          final account = accProvider.getAccountById(tx.accountId);
          final toAccount = tx.toAccountId != null
              ? accProvider.getAccountById(tx.toAccountId!)
              : null;

          final accountLabel =
              tx.type == TransactionType.transfer && toAccount != null
              ? '${account?.name ?? 'Account'} → ${toAccount.name}'
              : account?.name;

          return TransactionTile(
            transaction: tx,
            categoryName: category?.name,
            accountName: accountLabel,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TransactionDetailScreen(transaction: tx),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.card,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.card,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: bgColor.withValues(alpha: 0.6),
            borderRadius: AppRadius.card,
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              AppSpacing.gapH4,
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
