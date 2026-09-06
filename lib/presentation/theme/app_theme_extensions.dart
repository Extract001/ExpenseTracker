import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Theme extension for finance-specific domain colors that react to Light and Dark mode.
@immutable
class FinanceColors extends ThemeExtension<FinanceColors> {
  final Color income;
  final Color incomeContainer;
  final Color expense;
  final Color expenseContainer;
  final Color transfer;
  final Color transferContainer;
  final Color warning;
  final Color warningContainer;
  final Color success;
  final Color cardBorder;
  final Color surfaceVariant;
  final Color textTertiary;

  const FinanceColors({
    required this.income,
    required this.incomeContainer,
    required this.expense,
    required this.expenseContainer,
    required this.transfer,
    required this.transferContainer,
    required this.warning,
    required this.warningContainer,
    required this.success,
    required this.cardBorder,
    required this.surfaceVariant,
    required this.textTertiary,
  });

  static const FinanceColors light = FinanceColors(
    income: AppColors.income,
    incomeContainer: AppColors.incomeContainerLight,
    expense: AppColors.expense,
    expenseContainer: AppColors.expenseContainerLight,
    transfer: AppColors.transfer,
    transferContainer: AppColors.transferContainerLight,
    warning: AppColors.warning,
    warningContainer: AppColors.warningContainerLight,
    success: AppColors.success,
    cardBorder: AppColors.borderLight,
    surfaceVariant: AppColors.surfaceVariantLight,
    textTertiary: AppColors.textTertiaryLight,
  );

  static const FinanceColors dark = FinanceColors(
    income: AppColors.income,
    incomeContainer: AppColors.incomeContainerDark,
    expense: AppColors.expense,
    expenseContainer: AppColors.expenseContainerDark,
    transfer: AppColors.transfer,
    transferContainer: AppColors.transferContainerDark,
    warning: AppColors.warning,
    warningContainer: AppColors.warningContainerDark,
    success: AppColors.success,
    cardBorder: AppColors.borderDark,
    surfaceVariant: AppColors.surfaceVariantDark,
    textTertiary: AppColors.textTertiaryDark,
  );

  @override
  FinanceColors copyWith({
    Color? income,
    Color? incomeContainer,
    Color? expense,
    Color? expenseContainer,
    Color? transfer,
    Color? transferContainer,
    Color? warning,
    Color? warningContainer,
    Color? success,
    Color? cardBorder,
    Color? surfaceVariant,
    Color? textTertiary,
  }) {
    return FinanceColors(
      income: income ?? this.income,
      incomeContainer: incomeContainer ?? this.incomeContainer,
      expense: expense ?? this.expense,
      expenseContainer: expenseContainer ?? this.expenseContainer,
      transfer: transfer ?? this.transfer,
      transferContainer: transferContainer ?? this.transferContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      success: success ?? this.success,
      cardBorder: cardBorder ?? this.cardBorder,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      textTertiary: textTertiary ?? this.textTertiary,
    );
  }

  @override
  FinanceColors lerp(ThemeExtension<FinanceColors>? other, double t) {
    if (other is! FinanceColors) return this;
    return FinanceColors(
      income: Color.lerp(income, other.income, t)!,
      incomeContainer: Color.lerp(incomeContainer, other.incomeContainer, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      expenseContainer: Color.lerp(
        expenseContainer,
        other.expenseContainer,
        t,
      )!,
      transfer: Color.lerp(transfer, other.transfer, t)!,
      transferContainer: Color.lerp(
        transferContainer,
        other.transferContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      success: Color.lerp(success, other.success, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
    );
  }
}

extension FinanceColorsContext on BuildContext {
  FinanceColors get financeColors =>
      Theme.of(this).extension<FinanceColors>() ?? FinanceColors.light;
}
