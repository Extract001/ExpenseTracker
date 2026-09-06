import 'package:flutter/material.dart';
import '../../domain/entities/enums.dart';
import '../theme/app_spacing.dart';
import 'money_text.dart';

/// Hero visual amount display for account totals, monthly balances, and metrics.
class AmountDisplay extends StatelessWidget {
  final String label;
  final int amountMinor;
  final String? currencySymbol;
  final TransactionType? type;
  final String? subtitle;
  final TextStyle? amountStyle;
  final CrossAxisAlignment crossAxisAlignment;

  const AmountDisplay({
    super.key,
    required this.label,
    required this.amountMinor,
    this.currencySymbol,
    this.type,
    this.subtitle,
    this.amountStyle,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: theme.textTheme.bodyMedium?.color,
          ),
        ),
        AppSpacing.gapH4,
        MoneyText(
          amountMinor: amountMinor,
          currencySymbol: currencySymbol,
          type: type,
          style:
              amountStyle ??
              theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        if (subtitle != null) ...[
          AppSpacing.gapH4,
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodyMedium?.color,
            ),
          ),
        ],
      ],
    );
  }
}
