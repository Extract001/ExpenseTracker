import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/date_time_utils.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/recurring_transaction_entity.dart';
import '../../providers/account_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/recurring_transaction_provider.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extensions.dart';
import '../../widgets/app_card.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/money_text.dart';
import 'add_edit_recurring_modal.dart';

class RecurringTransactionsScreen extends StatefulWidget {
  const RecurringTransactionsScreen({super.key});

  @override
  State<RecurringTransactionsScreen> createState() =>
      _RecurringTransactionsScreenState();
}

class _RecurringTransactionsScreenState
    extends State<RecurringTransactionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<RecurringTransactionProvider>().watchRules();
        context.read<CategoryProvider>().watchCategories();
        context.read<AccountProvider>().watchAccounts();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _processDueRules() async {
    final count = await context
        .read<RecurringTransactionProvider>()
        .processDueRecurringRules();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count > 0
                ? 'Generated $count recurring transaction(s).'
                : 'No recurring transactions are due right now.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final recurringProvider = context.watch<RecurringTransactionProvider>();
    final activeRules = recurringProvider.activeRules;
    final pausedRules = recurringProvider.pausedRules;
    final isLoading = recurringProvider.isLoading;
    final isProcessing = recurringProvider.isProcessingDue;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring Transactions'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Active (${activeRules.length})'),
            Tab(text: 'Paused (${pausedRules.length})'),
          ],
        ),
        actions: [
          IconButton(
            icon: isProcessing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_circle_outline_rounded),
            tooltip: 'Process Due Rules Now',
            onPressed: isProcessing ? null : _processDueRules,
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'New Recurring Rule',
            onPressed: () => AddEditRecurringModal.show(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AddEditRecurringModal.show(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Rule'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Active Rules Tab
          _RecurringListView(
            rules: activeRules,
            isLoading: isLoading,
            emptyTitle: 'No Active Recurring Rules',
            emptyMessage:
                'Set up recurring rules for rent, salaries, subscriptions, and utility bills.',
            onAdd: () => AddEditRecurringModal.show(context),
          ),

          // Paused Rules Tab
          _RecurringListView(
            rules: pausedRules,
            isLoading: isLoading,
            emptyTitle: 'No Paused Rules',
            emptyMessage: 'Rules you pause temporarily will be displayed here.',
          ),
        ],
      ),
    );
  }
}

class _RecurringListView extends StatelessWidget {
  final List<RecurringTransactionEntity> rules;
  final bool isLoading;
  final String emptyTitle;
  final String emptyMessage;
  final VoidCallback? onAdd;

  const _RecurringListView({
    required this.rules,
    required this.isLoading,
    required this.emptyTitle,
    required this.emptyMessage,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;

    final catProvider = context.watch<CategoryProvider>();
    final accProvider = context.watch<AccountProvider>();

    if (isLoading && rules.isEmpty) {
      return const Padding(
        padding: AppSpacing.screenPadding,
        child: TransactionListSkeleton(itemCount: 4),
      );
    }

    if (rules.isEmpty) {
      return Padding(
        padding: AppSpacing.screenPadding,
        child: EmptyState(
          icon: Icons.repeat_rounded,
          title: emptyTitle,
          message: emptyMessage,
          actionLabel: onAdd != null ? 'Create Rule' : null,
          onActionPressed: onAdd,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<RecurringTransactionProvider>().loadRules(),
      child: ListView.separated(
        padding: AppSpacing.screenPadding,
        itemCount: rules.length,
        separatorBuilder: (_, __) => AppSpacing.gapH8,
        itemBuilder: (context, index) {
          final rule = rules[index];
          final cat = catProvider.getCategoryById(rule.categoryId);
          final acc = accProvider.getAccountById(rule.accountId);

          final icon = cat != null
              ? IconData(cat.iconCodePoint, fontFamily: 'MaterialIcons')
              : Icons.repeat_rounded;
          final color = cat != null
              ? Color(cat.colorValue)
              : (rule.type == TransactionType.income
                    ? financeColors.income
                    : financeColors.expense);

          return AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            onTap: () => AddEditRecurringModal.show(context, ruleToEdit: rule),
            child: Row(
              children: [
                CategoryIcon(icon: icon, color: color, size: 44, iconSize: 22),
                AppSpacing.gapW12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rule.note.isNotEmpty
                            ? rule.note
                            : (cat?.name ?? 'Recurring Rule'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      AppSpacing.gapH2,
                      Text(
                        '${rule.frequency.displayName} • ${acc?.name ?? 'Account'}',
                        style: theme.textTheme.bodySmall,
                      ),
                      AppSpacing.gapH2,
                      Text(
                        'Next: ${DateTimeUtils.formatDate(rule.nextDate)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                AppSpacing.gapW8,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MoneyText(
                      amountMinor: rule.amount,
                      type: rule.type,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    AppSpacing.gapH4,
                    Switch.adaptive(
                      value: rule.isActive,
                      onChanged: (val) {
                        context
                            .read<RecurringTransactionProvider>()
                            .toggleActive(rule.id, val);
                      },
                    ),
                  ],
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  onSelected: (val) {
                    if (val == 'edit') {
                      AddEditRecurringModal.show(context, ruleToEdit: rule);
                    } else if (val == 'delete') {
                      _confirmDelete(context, rule);
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
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, RecurringTransactionEntity rule) {
    showDialog<void>(
      context: context,
      builder: (ctx) => ConfirmationDialog(
        title: 'Delete Recurring Rule',
        message:
            'Are you sure you want to delete this rule? Existing transactions generated by this rule will remain.',
        confirmLabel: 'Delete',
        isDestructive: true,
        onConfirm: () async {
          await context.read<RecurringTransactionProvider>().deleteRule(
            rule.id,
          );
          if (ctx.mounted) Navigator.of(ctx).pop();
        },
      ),
    );
  }
}
