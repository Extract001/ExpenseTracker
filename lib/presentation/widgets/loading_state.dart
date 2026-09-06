import 'package:flutter/material.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_extensions.dart';

/// Pulsing shimmer/skeleton placeholder for smooth loading states.
class LoadingSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const LoadingSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _animation = Tween<double>(
      begin: 0.35,
      end: 0.75,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final financeColors = context.financeColors;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: financeColors.surfaceVariant.withValues(
              alpha: _animation.value,
            ),
            borderRadius: widget.borderRadius ?? AppRadius.input,
          ),
        );
      },
    );
  }
}

/// Skeleton loader for transaction list.
class TransactionListSkeleton extends StatelessWidget {
  final int itemCount;

  const TransactionListSkeleton({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      separatorBuilder: (_, __) => AppSpacing.gapH8,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const LoadingSkeleton(
                width: 44,
                height: 44,
                borderRadius: AppRadius.card,
              ),
              AppSpacing.gapW12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    LoadingSkeleton(width: 140, height: 16),
                    AppSpacing.gapH4,
                    LoadingSkeleton(width: 90, height: 12),
                  ],
                ),
              ),
              AppSpacing.gapW12,
              const LoadingSkeleton(width: 70, height: 18),
            ],
          ),
        );
      },
    );
  }
}

/// Skeleton loader for dashboard summary card.
class DashboardCardSkeleton extends StatelessWidget {
  const DashboardCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: AppRadius.card,
        border: Border.all(color: context.financeColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          LoadingSkeleton(width: 100, height: 14),
          AppSpacing.gapH8,
          LoadingSkeleton(width: 180, height: 32),
          AppSpacing.gapH16,
          Divider(),
          AppSpacing.gapH16,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LoadingSkeleton(width: 70, height: 12),
                  AppSpacing.gapH4,
                  LoadingSkeleton(width: 100, height: 18),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  LoadingSkeleton(width: 70, height: 12),
                  AppSpacing.gapH4,
                  LoadingSkeleton(width: 100, height: 18),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
