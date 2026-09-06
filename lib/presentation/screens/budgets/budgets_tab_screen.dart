import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/date_time_utils.dart';
import '../../providers/budget_provider.dart';
import '../../providers/category_provider.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extensions.dart';
import '../../widgets/amount_display.dart';
import '../../widgets/app_card.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_header.dart';
import 'add_edit_budget_modal.dart';

class BudgetsTabScreen extends StatefulWidget {
  const BudgetsTabScreen({super.key});

  @override
  State<BudgetsTabScreen> createState() => _BudgetsTabScreenState();
}

class _BudgetsTabScreenState extends State<BudgetsTabScreen> {
  late DateTime _currentMonth;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime.now().toUtc();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<BudgetProvider>().watchBudgetForSelectedMonth();
        context.read<CategoryProvider>().watchCategories();
      }
    });
  }

  void _changeMonth(int monthDelta) {
    setState(() {
      _currentMonth = DateTime.utc(
        _currentMonth.year,
        _currentMonth.month + monthDelta,
        1,
      );
    });
    final key = DateTimeUtils.toMonthKey(_currentMonth);
    context.read<BudgetProvider>().setSelectedMonth(key);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;

    final budgetProvider = context.watch<BudgetProvider>();
    final catProvider = context.watch<CategoryProvider>();

    final monthlyBudget = budgetProvider.monthlyBudget;
    final totalLimit = budgetProvider.totalBudgetLimitMinor;
    final totalSpent = budgetProvider.totalSpentMinor;
    final remaining = budgetProvider.remainingBudgetMinor;
    final progress = budgetProvider.budgetProgressPercentage;
    final isOver = budgetProvider.isOverBudget;
    final categoryBudgets = budgetProvider.categoryBudgets;

    final monthLabel = DateFormat('MMMM yyyy').format(_currentMonth);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets & Limits'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Set Budget',
            onPressed: () => AddEditBudgetModal.show(
              context,
              initialAmountMinor: totalLimit > 0 ? totalLimit : null,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => budgetProvider.loadBudgetForSelectedMonth(),
        child: ListView(
          padding: AppSpacing.screenPadding,
          children: [
            // Month Selector Bar
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () => _changeMonth(-1),
                  ),
                  Text(
                    monthLabel,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: () => _changeMonth(1),
                  ),
                ],
              ),
            ),
            AppSpacing.gapH16,

            if (monthlyBudget == null || totalLimit == 0) ...[
              AppCard(
                child: EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'No Budget for $monthLabel',
                  message:
                      'Set a monthly spending limit to control your expenses and prevent overspending.',
                  actionLabel: 'Set Monthly Budget',
                  onActionPressed: () => AddEditBudgetModal.show(context),
                ),
              ),
            ] else ...[
              // Overall Monthly Budget Hero Card
              AppCard(
                padding: AppSpacing.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Overall Monthly Budget',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          onPressed: () => AddEditBudgetModal.show(
                            context,
                            initialAmountMinor: totalLimit,
                          ),
                        ),
                      ],
                    ),
                    AppSpacing.gapH8,
                    AmountDisplay(
                      label: 'Budget Limit',
                      amountMinor: totalLimit,
                      amountStyle: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    AppSpacing.gapH16,
                    LinearProgressIndicator(
                      value: (progress / 100.0).clamp(0.0, 1.0),
                      backgroundColor: financeColors.surfaceVariant,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isOver
                            ? financeColors.expense
                            : theme.colorScheme.primary,
                      ),
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    AppSpacing.gapH16,
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Spent So Far',
                              style: theme.textTheme.bodySmall,
                            ),
                            AppSpacing.gapH2,
                            MoneyText(
                              amountMinor: totalSpent,
                              style: theme.textTheme.titleMedium?.copyWith(
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
                              isOver ? 'Over Budget By' : 'Remaining',
                              style: theme.textTheme.bodySmall,
                            ),
                            AppSpacing.gapH2,
                            MoneyText(
                              amountMinor: isOver
                                  ? (totalSpent - totalLimit)
                                  : remaining,
                              style: theme.textTheme.titleMedium?.copyWith(
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
              AppSpacing.gapH24,

              // Category Budgets Header
              SectionHeader(
                title: 'Category Budgets',
                actionLabel: 'Add Category Budget',
                onActionPressed: () =>
                    AddEditBudgetModal.show(context, isCategoryBudget: true),
              ),
              AppSpacing.gapH8,

              if (categoryBudgets.isEmpty)
                AppCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.pie_chart_outline_rounded,
                            size: 36,
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                          AppSpacing.gapH8,
                          const Text('No specific category limits set.'),
                          TextButton(
                            onPressed: () => AddEditBudgetModal.show(
                              context,
                              isCategoryBudget: true,
                            ),
                            child: const Text('Add Category Budget'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: categoryBudgets.length,
                  separatorBuilder: (_, __) => AppSpacing.gapH8,
                  itemBuilder: (context, index) {
                    final cb = categoryBudgets[index];
                    final cat = catProvider.getCategoryById(cb.categoryId);
                    final catSpent = budgetProvider.getSpentForCategory(
                      cb.categoryId,
                    );
                    final catProgress = cb.amount > 0
                        ? ((catSpent / cb.amount) * 100).clamp(0.0, 100.0)
                        : 0.0;
                    final isCatOver = catSpent > cb.amount;

                    final icon = cat != null
                        ? IconData(
                            cat.iconCodePoint,
                            fontFamily: 'MaterialIcons',
                          )
                        : Icons.category_rounded;
                    final color = cat != null
                        ? Color(cat.colorValue)
                        : theme.colorScheme.primary;

                    return AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CategoryIcon(
                                icon: icon,
                                color: color,
                                size: 36,
                                iconSize: 18,
                              ),
                              AppSpacing.gapW12,
                              Expanded(
                                child: Text(
                                  cat?.name ?? 'Category',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_rounded, size: 16),
                                onPressed: () => AddEditBudgetModal.show(
                                  context,
                                  initialCategoryId: cb.categoryId,
                                  initialAmountMinor: cb.amount,
                                  isCategoryBudget: true,
                                ),
                              ),
                            ],
                          ),
                          AppSpacing.gapH8,
                          LinearProgressIndicator(
                            value: (catProgress / 100.0).clamp(0.0, 1.0),
                            backgroundColor: financeColors.surfaceVariant,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isCatOver ? financeColors.expense : color,
                            ),
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          AppSpacing.gapH8,
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Spent: ₹${(catSpent / 100).toStringAsFixed(2)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isCatOver
                                      ? financeColors.expense
                                      : null,
                                  fontWeight: isCatOver
                                      ? FontWeight.w700
                                      : null,
                                ),
                              ),
                              Text(
                                'Limit: ₹${(cb.amount / 100).toStringAsFixed(2)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
            AppSpacing.gapH32,
          ],
        ),
      ),
    );
  }
}
