import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/date_time_utils.dart';
import '../../../domain/entities/enums.dart';
import '../../providers/category_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extensions.dart';
import '../../widgets/amount_display.dart';
import '../../widgets/app_card.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_header.dart';

enum AnalyticsPeriod { thisMonth, lastMonth, thisYear }

class AnalyticsTabScreen extends StatefulWidget {
  const AnalyticsTabScreen({super.key});

  @override
  State<AnalyticsTabScreen> createState() => _AnalyticsTabScreenState();
}

class _AnalyticsTabScreenState extends State<AnalyticsTabScreen> {
  AnalyticsPeriod _selectedPeriod = AnalyticsPeriod.thisMonth;
  int _touchedPieIndex = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPeriodData();
    });
  }

  void _loadPeriodData() {
    final now = DateTime.now().toUtc();
    DateTime start;
    DateTime end;

    switch (_selectedPeriod) {
      case AnalyticsPeriod.thisMonth:
        start = DateTimeUtils.startOfMonthUtc(now);
        end = DateTimeUtils.endOfMonthUtc(now);
        break;
      case AnalyticsPeriod.lastMonth:
        final lastMonthDate = DateTime.utc(now.year, now.month - 1, 1);
        start = DateTimeUtils.startOfMonthUtc(lastMonthDate);
        end = DateTimeUtils.endOfMonthUtc(lastMonthDate);
        break;
      case AnalyticsPeriod.thisYear:
        start = DateTime.utc(now.year, 1, 1);
        end = DateTime.utc(now.year, 12, 31, 23, 59, 59);
        break;
    }

    final txProvider = context.read<TransactionProvider>();
    txProvider.loadTotals(startDateUtc: start, endDateUtc: end);
    txProvider.updateFilter(startDate: start, endDate: end);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;

    final txProvider = context.watch<TransactionProvider>();
    final catProvider = context.watch<CategoryProvider>();

    final totalIncome = txProvider.totalIncomeMinor;
    final totalExpense = txProvider.totalExpenseMinor;
    final netCashFlow = totalIncome - totalExpense;
    final transactions = txProvider.transactions;

    // Filter expense transactions to calculate category breakdown
    final expenseTransactions = transactions
        .where((t) => t.type == TransactionType.expense)
        .toList();

    // Group expense transactions by category
    final Map<String, int> categoryTotals = {};
    for (final tx in expenseTransactions) {
      categoryTotals[tx.categoryId] =
          (categoryTotals[tx.categoryId] ?? 0) + tx.amount;
    }

    final sortedCategoryIds = categoryTotals.keys.toList()
      ..sort((a, b) => categoryTotals[b]!.compareTo(categoryTotals[a]!));

    final hasData = totalIncome > 0 || totalExpense > 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics & Insights')),
      body: RefreshIndicator(
        onRefresh: () async {
          _loadPeriodData();
        },
        child: ListView(
          padding: AppSpacing.screenPadding,
          children: [
            // Period Selector Segmented Chips
            Container(
              decoration: BoxDecoration(
                color: financeColors.surfaceVariant,
                borderRadius: AppRadius.button,
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: _PeriodChip(
                      label: 'This Month',
                      isSelected: _selectedPeriod == AnalyticsPeriod.thisMonth,
                      onTap: () {
                        setState(
                          () => _selectedPeriod = AnalyticsPeriod.thisMonth,
                        );
                        _loadPeriodData();
                      },
                    ),
                  ),
                  Expanded(
                    child: _PeriodChip(
                      label: 'Last Month',
                      isSelected: _selectedPeriod == AnalyticsPeriod.lastMonth,
                      onTap: () {
                        setState(
                          () => _selectedPeriod = AnalyticsPeriod.lastMonth,
                        );
                        _loadPeriodData();
                      },
                    ),
                  ),
                  Expanded(
                    child: _PeriodChip(
                      label: 'This Year',
                      isSelected: _selectedPeriod == AnalyticsPeriod.thisYear,
                      onTap: () {
                        setState(
                          () => _selectedPeriod = AnalyticsPeriod.thisYear,
                        );
                        _loadPeriodData();
                      },
                    ),
                  ),
                ],
              ),
            ),
            AppSpacing.gapH16,

            // Cash Flow Summary Card
            AppCard(
              padding: AppSpacing.cardPadding,
              child: Column(
                children: [
                  AmountDisplay(
                    label: 'Net Cash Flow',
                    amountMinor: netCashFlow,
                    amountStyle: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: netCashFlow >= 0
                          ? financeColors.income
                          : financeColors.expense,
                    ),
                  ),
                  AppSpacing.gapH16,
                  const Divider(),
                  AppSpacing.gapH16,
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Income',
                              style: theme.textTheme.bodySmall,
                            ),
                            AppSpacing.gapH2,
                            MoneyText(
                              amountMinor: totalIncome,
                              type: TransactionType.income,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 36,
                        width: 1,
                        color: financeColors.cardBorder,
                      ),
                      AppSpacing.gapW16,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Expenses',
                              style: theme.textTheme.bodySmall,
                            ),
                            AppSpacing.gapH2,
                            MoneyText(
                              amountMinor: totalExpense,
                              type: TransactionType.expense,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            AppSpacing.gapH24,

            if (!hasData) ...[
              AppCard(
                child: EmptyState(
                  icon: Icons.pie_chart_outline_rounded,
                  title: 'No Data for Selected Period',
                  message:
                      'Transactions recorded for this period will appear in the financial breakdown.',
                ),
              ),
            ] else ...[
              // Spending by Category Pie Chart
              if (totalExpense > 0 && sortedCategoryIds.isNotEmpty) ...[
                const SectionHeader(title: 'Spending by Category'),
                AppSpacing.gapH8,
                AppCard(
                  padding: AppSpacing.cardPadding,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 200,
                        child: PieChart(
                          PieChartData(
                            pieTouchData: PieTouchData(
                              touchCallback: (event, pieTouchResponse) {
                                setState(() {
                                  if (!event.isInterestedForInteractions ||
                                      pieTouchResponse == null ||
                                      pieTouchResponse.touchedSection == null) {
                                    _touchedPieIndex = -1;
                                    return;
                                  }
                                  _touchedPieIndex = pieTouchResponse
                                      .touchedSection!
                                      .touchedSectionIndex;
                                });
                              },
                            ),
                            sectionsSpace: 2,
                            centerSpaceRadius: 40,
                            sections: List.generate(sortedCategoryIds.length, (
                              i,
                            ) {
                              final isTouched = i == _touchedPieIndex;
                              final catId = sortedCategoryIds[i];
                              final cat = catProvider.getCategoryById(catId);
                              final amount = categoryTotals[catId]!;
                              final percentage = (amount / totalExpense) * 100;
                              final radius = isTouched ? 60.0 : 50.0;
                              final color = cat != null
                                  ? Color(cat.colorValue)
                                  : financeColors.surfaceVariant;

                              return PieChartSectionData(
                                color: color,
                                value: amount.toDouble(),
                                title: '${percentage.toStringAsFixed(0)}%',
                                radius: radius,
                                titleStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                      AppSpacing.gapH16,
                      const Divider(),
                      AppSpacing.gapH8,

                      // Category Breakdown List
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: sortedCategoryIds.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final catId = sortedCategoryIds[index];
                          final cat = catProvider.getCategoryById(catId);
                          final amount = categoryTotals[catId]!;
                          final percentage = (amount / totalExpense) * 100;
                          final color = cat != null
                              ? Color(cat.colorValue)
                              : financeColors.surfaceVariant;
                          final icon = cat != null
                              ? IconData(
                                  cat.iconCodePoint,
                                  fontFamily: 'MaterialIcons',
                                )
                              : Icons.category_rounded;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                CategoryIcon(
                                  icon: icon,
                                  color: color,
                                  size: 36,
                                  iconSize: 18,
                                ),
                                AppSpacing.gapW12,
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cat?.name ?? 'Other',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      Text(
                                        '${percentage.toStringAsFixed(1)}% of total',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                MoneyText(
                                  amountMinor: amount,
                                  type: TransactionType.expense,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ],
            AppSpacing.gapH32,
          ],
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.button,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: AppRadius.button,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : theme.textTheme.bodyMedium?.color,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
