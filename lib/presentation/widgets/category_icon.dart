import 'package:flutter/material.dart';
import '../theme/app_radius.dart';

/// Reusable category icon badge with customizable background color and glyph.
class CategoryIcon extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final Color? backgroundColor;
  final double size;
  final double iconSize;

  const CategoryIcon({
    super.key,
    required this.icon,
    this.color,
    this.backgroundColor,
    this.size = 40.0,
    this.iconSize = 20.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.primary;
    final effectiveBg =
        backgroundColor ?? effectiveColor.withValues(alpha: 0.12);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: AppRadius.card,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize, color: effectiveColor),
    );
  }
}
