import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/date_time_utils.dart';
import '../../../domain/entities/goal_entity.dart';
import '../../providers/goal_provider.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extensions.dart';
import '../../widgets/app_card.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/money_text.dart';
import 'add_edit_goal_modal.dart';
import 'add_goal_progress_modal.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<GoalProvider>().watchGoals();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;

    final goalProvider = context.watch<GoalProvider>();
    final activeGoals = goalProvider.activeGoals;
    final completedGoals = goalProvider.completedGoals;
    final totalSaved = goalProvider.totalSavedMinor;
    final totalTarget = goalProvider.totalTargetMinor;
    final isLoading = goalProvider.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Savings Goals'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Active (${activeGoals.length})'),
            Tab(text: 'Completed (${completedGoals.length})'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'New Goal',
            onPressed: () => AddEditGoalModal.show(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AddEditGoalModal.show(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Goal'),
      ),
      body: Column(
        children: [
          // Total Savings Summary Header Card
          Padding(
            padding: const EdgeInsets.only(top: 16, left: 16, right: 16),
            child: AppCard(
              padding: AppSpacing.cardPadding,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total Saved', style: theme.textTheme.bodySmall),
                        AppSpacing.gapH2,
                        MoneyText(
                          amountMinor: totalSaved,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: financeColors.income,
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
                        Text('Total Target', style: theme.textTheme.bodySmall),
                        AppSpacing.gapH2,
                        MoneyText(
                          amountMinor: totalTarget,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Active Goals Tab
                _GoalListView(
                  goals: activeGoals,
                  isLoading: isLoading,
                  emptyTitle: 'No Active Goals',
                  emptyMessage:
                      'Set a savings target for a vacation, gadget, or rainy-day fund.',
                  onAdd: () => AddEditGoalModal.show(context),
                ),

                // Completed Goals Tab
                _GoalListView(
                  goals: completedGoals,
                  isLoading: isLoading,
                  emptyTitle: 'No Completed Goals Yet',
                  emptyMessage:
                      'Goals you achieve will be celebrated and stored here.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalListView extends StatelessWidget {
  final List<GoalEntity> goals;
  final bool isLoading;
  final String emptyTitle;
  final String emptyMessage;
  final VoidCallback? onAdd;

  const _GoalListView({
    required this.goals,
    required this.isLoading,
    required this.emptyTitle,
    required this.emptyMessage,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;

    if (isLoading && goals.isEmpty) {
      return const Padding(
        padding: AppSpacing.screenPadding,
        child: TransactionListSkeleton(itemCount: 4),
      );
    }

    if (goals.isEmpty) {
      return Padding(
        padding: AppSpacing.screenPadding,
        child: EmptyState(
          icon: Icons.savings_outlined,
          title: emptyTitle,
          message: emptyMessage,
          actionLabel: onAdd != null ? 'Create Goal' : null,
          onActionPressed: onAdd,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<GoalProvider>().loadGoals(),
      child: ListView.separated(
        padding: AppSpacing.screenPadding,
        itemCount: goals.length,
        separatorBuilder: (_, __) => AppSpacing.gapH12,
        itemBuilder: (context, index) {
          final goal = goals[index];
          final icon = IconData(
            goal.iconCodePoint,
            fontFamily: 'MaterialIcons',
          );
          final color = Color(goal.colorValue);
          final pct = (goal.progressPercentage * 100).clamp(0.0, 100.0);

          return AppCard(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CategoryIcon(
                      icon: icon,
                      color: color,
                      size: 44,
                      iconSize: 22,
                    ),
                    AppSpacing.gapW12,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            goal.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Target Date: ${DateTimeUtils.formatDate(goal.targetDate)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, size: 20),
                      onSelected: (val) {
                        if (val == 'edit') {
                          AddEditGoalModal.show(context, goalToEdit: goal);
                        } else if (val == 'delete') {
                          _confirmDelete(context, goal);
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_rounded, size: 18),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: Colors.red,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Delete',
                                style: TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                AppSpacing.gapH12,

                // Progress Bar
                LinearProgressIndicator(
                  value: goal.progressPercentage,
                  backgroundColor: financeColors.surfaceVariant,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    goal.isCompleted ? financeColors.income : color,
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
                        Text('Saved', style: theme.textTheme.bodySmall),
                        MoneyText(
                          amountMinor: goal.currentAmount,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: financeColors.income,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text('Progress', style: theme.textTheme.bodySmall),
                        Text(
                          '${pct.toStringAsFixed(0)}%',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Target', style: theme.textTheme.bodySmall),
                        MoneyText(
                          amountMinor: goal.targetAmount,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                if (!goal.isCompleted) ...[
                  AppSpacing.gapH12,
                  const Divider(),
                  AppSpacing.gapH8,
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          AddGoalProgressModal.show(context, goal: goal),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Funds to Goal'),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, GoalEntity goal) {
    showDialog<void>(
      context: context,
      builder: (ctx) => ConfirmationDialog(
        title: 'Delete Goal',
        message: 'Are you sure you want to delete "${goal.name}"?',
        confirmLabel: 'Delete',
        isDestructive: true,
        onConfirm: () async {
          await context.read<GoalProvider>().deleteGoal(goal.id);
          if (ctx.mounted) Navigator.of(ctx).pop();
        },
      ),
    );
  }
}
