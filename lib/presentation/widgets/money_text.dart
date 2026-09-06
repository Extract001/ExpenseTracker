import 'package:flutter/material.dart';
import '../../core/utils/money_utils.dart';
import '../../domain/entities/enums.dart';
import '../theme/app_theme_extensions.dart';

/// Highly accessible and precise money text widget rendering integer minor-unit amounts.
/// Strictly avoids binary floating point arithmetic and uses tabular figures.
class MoneyText extends StatelessWidget {
  final int amountMinor;
  final String? currencySymbol;
  final TransactionType? type;
  final bool showSign;
  final TextStyle? style;
  final Color? color;
  final TextAlign? textAlign;
  final int decimalDigits;

  const MoneyText({
    super.key,
    required this.amountMinor,
    this.currencySymbol,
    this.type,
    this.showSign = false,
    this.style,
    this.color,
    this.textAlign,
    this.decimalDigits = 2,
  });

  @override
  Widget build(BuildContext context) {
    final financeColors = context.financeColors;
    final theme = Theme.of(context);

    // Determine semantic color
    Color effectiveColor;
    if (color != null) {
      effectiveColor = color!;
    } else if (type == TransactionType.income) {
      effectiveColor = financeColors.income;
    } else if (type == TransactionType.expense) {
      effectiveColor = financeColors.expense;
    } else if (type == TransactionType.transfer) {
      effectiveColor = financeColors.transfer;
    } else {
      effectiveColor = theme.textTheme.bodyLarge?.color ?? Colors.black;
    }

    // Determine sign prefix and formatted string
    final bool shouldPrefixSign = showSign || type != null;
    String prefix = '';
    if (shouldPrefixSign) {
      if (type == TransactionType.income || amountMinor > 0 && showSign) {
        prefix = '+ ';
      } else if (type == TransactionType.expense || amountMinor < 0) {
        prefix = '- ';
      }
    }

    final formattedPlain = MoneyUtils.format(
      amountMinor.abs(),
      currencySymbol: currencySymbol ?? '₹',
      decimalDigits: decimalDigits,
      showSign: false,
    );

    final displayString = '$prefix$formattedPlain';

    final effectiveStyle = (style ?? theme.textTheme.bodyLarge)?.copyWith(
      color: effectiveColor,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Text(
      displayString,
      style: effectiveStyle,
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
