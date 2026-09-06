import 'package:flutter/material.dart';
import '../../core/utils/date_time_utils.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/transaction_entity.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_extensions.dart';
import 'category_icon.dart';
import 'money_text.dart';

/// Highly scannable and accessible transaction list tile.
class TransactionTile extends StatelessWidget {
  final TransactionEntity transaction;
  final String? categoryName;
  final IconData? categoryIcon;
  final Color? categoryColor;
  final String? accountName;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TransactionTile({
    super.key,
    required this.transaction,
    this.categoryName,
    this.categoryIcon,
    this.categoryColor,
    this.accountName,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;

    // Determine default icon based on type
    IconData iconData = categoryIcon ?? Icons.receipt_long_rounded;
    Color iconColor = categoryColor ?? theme.colorScheme.primary;

    if (transaction.type == TransactionType.income) {
      iconData = categoryIcon ?? Icons.arrow_downward_rounded;
      iconColor = categoryColor ?? financeColors.income;
    } else if (transaction.type == TransactionType.expense) {
      iconData = categoryIcon ?? Icons.arrow_upward_rounded;
      iconColor = categoryColor ?? financeColors.expense;
    } else if (transaction.type == TransactionType.transfer) {
      iconData = Icons.swap_horiz_rounded;
      iconColor = financeColors.transfer;
    }

    final displayTitle = transaction.note.isNotEmpty
        ? transaction.note
        : (categoryName ??
              (transaction.type == TransactionType.transfer
                  ? 'Transfer'
                  : 'Transaction'));

    final subParts = <String>[];
    if (categoryName != null && transaction.note.isNotEmpty) {
      subParts.add(categoryName!);
    }
    if (accountName != null) {
      subParts.add(accountName!);
    }
    final formattedDate = DateTimeUtils.formatDate(transaction.date);
    subParts.add(formattedDate);

    final subtitleText = subParts.join(' • ');

    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.card,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: AppRadius.card,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CategoryIcon(
                icon: iconData,
                color: iconColor,
                size: 44,
                iconSize: 22,
              ),
              AppSpacing.gapW12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    AppSpacing.gapH4,
                    Text(
                      subtitleText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AppSpacing.gapW12,
              MoneyText(
                amountMinor: transaction.amount,
                type: transaction.type,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
