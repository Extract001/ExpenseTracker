import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_extensions.dart';

enum AppButtonVariant { primary, secondary, outline, text, destructive }

/// Accessible, responsive button component following Material 3 guidelines.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool isLoading;
  final Widget? icon;
  final double? width;
  final double minHeight;
  final EdgeInsetsGeometry? padding;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.width,
    this.minHeight = 48.0,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;

    Color backgroundColor;
    Color foregroundColor;
    BorderSide? borderSide;

    switch (variant) {
      case AppButtonVariant.primary:
        backgroundColor = theme.colorScheme.primary;
        foregroundColor = theme.colorScheme.onPrimary;
        borderSide = null;
        break;
      case AppButtonVariant.secondary:
        backgroundColor = financeColors.surfaceVariant;
        foregroundColor = theme.textTheme.bodyLarge?.color ?? Colors.black;
        borderSide = BorderSide(color: financeColors.cardBorder, width: 1);
        break;
      case AppButtonVariant.outline:
        backgroundColor = Colors.transparent;
        foregroundColor = theme.colorScheme.primary;
        borderSide = BorderSide(color: theme.colorScheme.primary, width: 1.5);
        break;
      case AppButtonVariant.text:
        backgroundColor = Colors.transparent;
        foregroundColor = theme.colorScheme.primary;
        borderSide = null;
        break;
      case AppButtonVariant.destructive:
        backgroundColor = financeColors.expenseContainer;
        foregroundColor = financeColors.expense;
        borderSide = BorderSide(
          color: financeColors.expense.withValues(alpha: 0.3),
          width: 1,
        );
        break;
    }

    final effectivePadding = padding ?? AppSpacing.buttonPaddingCompact;

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null && !isLoading) ...[icon!, AppSpacing.gapW8],
        if (isLoading) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
            ),
          ),
          AppSpacing.gapW8,
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              color: foregroundColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );

    return SizedBox(
      width: width,
      height: minHeight,
      child: Material(
        color: onPressed == null
            ? AppColors.disabled.withValues(alpha: 0.2)
            : backgroundColor,
        borderRadius: AppRadius.button,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: AppRadius.button,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.button,
              border: borderSide != null
                  ? Border.fromBorderSide(borderSide)
                  : null,
            ),
            padding: effectivePadding,
            alignment: Alignment.center,
            child: content,
          ),
        ),
      ),
    );
  }
}
