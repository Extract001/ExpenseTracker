import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/date_time_utils.dart';
import '../../../core/utils/money_utils.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/transaction_entity.dart';
import '../../providers/account_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extensions.dart';
import '../../widgets/add_transaction_modal.dart';
import '../../widgets/amount_display.dart';
import '../../widgets/app_card.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/confirmation_dialog.dart';

class TransactionDetailScreen extends StatelessWidget {
  final TransactionEntity transaction;

  const TransactionDetailScreen({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;

    final catProvider = context.watch<CategoryProvider>();
    final accProvider = context.watch<AccountProvider>();

    final category = catProvider.getCategoryById(transaction.categoryId);
    final account = accProvider.getAccountById(transaction.accountId);
    final toAccount = transaction.toAccountId != null
        ? accProvider.getAccountById(transaction.toAccountId!)
        : null;

    final icon = category != null
        ? IconData(category.iconCodePoint, fontFamily: 'MaterialIcons')
        : (transaction.type == TransactionType.transfer
              ? Icons.swap_horiz_rounded
              : Icons.receipt_long_rounded);

    final color = category != null
        ? Color(category.colorValue)
        : (transaction.type == TransactionType.income
              ? financeColors.income
              : (transaction.type == TransactionType.transfer
                    ? financeColors.transfer
                    : financeColors.expense));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Edit Transaction',
            onPressed: () {
              AddTransactionModal.show(context, transactionToEdit: transaction);
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Delete Transaction',
            onPressed: () => _confirmDelete(context, transaction),
          ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          // Hero Card with Icon & Amount
          AppCard(
            padding: AppSpacing.cardPadding,
            child: Column(
              children: [
                CategoryIcon(icon: icon, color: color, size: 64, iconSize: 32),
                AppSpacing.gapH12,
                if (transaction.note.isNotEmpty) ...[
                  Text(
                    transaction.note,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.gapH4,
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: AppRadius.pill,
                  ),
                  child: Text(
                    transaction.type.displayName,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                AppSpacing.gapH24,
                AmountDisplay(
                  label: 'Amount',
                  amountMinor: transaction.amount,
                  amountStyle: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: transaction.type == TransactionType.income
                        ? financeColors.income
                        : (transaction.type == TransactionType.expense
                              ? financeColors.expense
                              : financeColors.transfer),
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.gapH16,

          // Transaction Information Breakdown
          AppCard(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Transaction Information',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                AppSpacing.gapH16,

                // Transfer Display: From -> To
                if (transaction.type == TransactionType.transfer) ...[
                  _DetailRow(
                    label: 'From Account',
                    value: account?.name ?? 'Unknown Account',
                  ),
                  const Divider(),
                  _DetailRow(
                    label: 'To Account',
                    value: toAccount?.name ?? 'Unknown Account',
                  ),
                  const Divider(),
                ] else ...[
                  _DetailRow(
                    label: 'Category',
                    value: category?.name ?? 'Uncategorized',
                  ),
                  const Divider(),
                  _DetailRow(
                    label: 'Account',
                    value: account?.name ?? 'Unknown Account',
                  ),
                  const Divider(),
                ],

                _DetailRow(
                  label: 'Date',
                  value: DateTimeUtils.formatDate(transaction.date),
                ),
                const Divider(),
                _DetailRow(
                  label: 'Time',
                  value: DateTimeUtils.formatTime(transaction.date),
                ),
                if (transaction.note.isNotEmpty) ...[
                  const Divider(),
                  _DetailRow(label: 'Note', value: transaction.note),
                ],
                const Divider(),
                _DetailRow(
                  label: 'Created At',
                  value: DateTimeUtils.formatDate(transaction.createdAt),
                ),
                const Divider(),
                _DetailRow(
                  label: 'Last Modified',
                  value: DateTimeUtils.formatDate(transaction.updatedAt),
                ),
                const Divider(),
                _DetailRow(
                  label: 'Sync Status',
                  value: transaction.syncStatus.name.toUpperCase(),
                ),
              ],
            ),
          ),
          AppSpacing.gapH24,
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, TransactionEntity tx) {
    showDialog<void>(
      context: context,
      builder: (ctx) => ConfirmationDialog(
        title: 'Delete Transaction',
        message:
            'Are you sure you want to delete this transaction of ${MoneyUtils.format(tx.amount)}?',
        confirmLabel: 'Delete',
        isDestructive: true,
        onConfirm: () async {
          final nav = Navigator.of(context);
          await context.read<TransactionProvider>().deleteTransaction(tx.id);
          nav.pop(); // Pop confirmation dialog
          nav.pop(); // Pop details screen
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color,
            ),
          ),
          AppSpacing.gapW16,
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
