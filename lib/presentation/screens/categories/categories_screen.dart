import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/entities/category_entity.dart';
import '../../../domain/entities/enums.dart';
import '../../providers/category_provider.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extensions.dart';
import '../../widgets/app_card.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_state.dart';
import 'add_edit_category_modal.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<CategoryProvider>().watchCategories();
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
    final catProvider = context.watch<CategoryProvider>();
    final expenseCats = catProvider.expenseCategories;
    final incomeCats = catProvider.incomeCategories;
    final archivedCats = catProvider.archivedCategories;
    final isLoading = catProvider.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Expense (${expenseCats.length})'),
            Tab(text: 'Income (${incomeCats.length})'),
            Tab(text: 'Archived (${archivedCats.length})'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add Category',
            onPressed: () => AddEditCategoryModal.show(
              context,
              initialType: _tabController.index == 1
                  ? TransactionType.income
                  : TransactionType.expense,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AddEditCategoryModal.show(
          context,
          initialType: _tabController.index == 1
              ? TransactionType.income
              : TransactionType.expense,
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Category'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Expense Tab
          _CategoryListView(
            categories: expenseCats,
            isLoading: isLoading,
            emptyTitle: 'No Expense Categories',
            emptyMessage:
                'Create an expense category to organize your spending.',
            onAdd: () => AddEditCategoryModal.show(
              context,
              initialType: TransactionType.expense,
            ),
          ),

          // Income Tab
          _CategoryListView(
            categories: incomeCats,
            isLoading: isLoading,
            emptyTitle: 'No Income Categories',
            emptyMessage:
                'Create an income category to organize your earnings.',
            onAdd: () => AddEditCategoryModal.show(
              context,
              initialType: TransactionType.income,
            ),
          ),

          // Archived Tab
          _CategoryListView(
            categories: archivedCats,
            isLoading: isLoading,
            emptyTitle: 'No Archived Categories',
            emptyMessage: 'Archived categories will appear here.',
            isArchivedTab: true,
          ),
        ],
      ),
    );
  }
}

class _CategoryListView extends StatelessWidget {
  final List<CategoryEntity> categories;
  final bool isLoading;
  final String emptyTitle;
  final String emptyMessage;
  final VoidCallback? onAdd;
  final bool isArchivedTab;

  const _CategoryListView({
    required this.categories,
    required this.isLoading,
    required this.emptyTitle,
    required this.emptyMessage,
    this.onAdd,
    this.isArchivedTab = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;

    if (isLoading && categories.isEmpty) {
      return const Padding(
        padding: AppSpacing.screenPadding,
        child: TransactionListSkeleton(itemCount: 5),
      );
    }

    if (categories.isEmpty) {
      return Padding(
        padding: AppSpacing.screenPadding,
        child: EmptyState(
          icon: Icons.category_rounded,
          title: emptyTitle,
          message: emptyMessage,
          actionLabel: onAdd != null ? 'Add Category' : null,
          onActionPressed: onAdd,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<CategoryProvider>().loadCategories(),
      child: ListView.separated(
        padding: AppSpacing.screenPadding,
        itemCount: categories.length,
        separatorBuilder: (_, __) => AppSpacing.gapH8,
        itemBuilder: (context, index) {
          final cat = categories[index];
          final icon = IconData(cat.iconCodePoint, fontFamily: 'MaterialIcons');
          final color = Color(cat.colorValue);

          return AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            onTap: () =>
                AddEditCategoryModal.show(context, categoryToEdit: cat),
            child: Row(
              children: [
                CategoryIcon(icon: icon, color: color, size: 44, iconSize: 22),
                AppSpacing.gapW12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cat.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      AppSpacing.gapH4,
                      Row(
                        children: [
                          if (cat.isSystem)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: AppRadius.pill,
                              ),
                              child: Text(
                                'System',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if (cat.isArchived)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: financeColors.warning.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: AppRadius.pill,
                              ),
                              child: Text(
                                'Archived',
                                style: TextStyle(
                                  color: financeColors.warning,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  onSelected: (val) {
                    if (val == 'edit') {
                      AddEditCategoryModal.show(context, categoryToEdit: cat);
                    } else if (val == 'archive') {
                      _confirmArchive(context, cat);
                    } else if (val == 'delete') {
                      _confirmDelete(context, cat);
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
                    if (!cat.isSystem && !cat.isArchived)
                      const PopupMenuItem(
                        value: 'archive',
                        child: Row(
                          children: [
                            Icon(Icons.archive_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Archive'),
                          ],
                        ),
                      ),
                    if (!cat.isSystem)
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

  void _confirmArchive(BuildContext context, CategoryEntity category) {
    showDialog<void>(
      context: context,
      builder: (ctx) => ConfirmationDialog(
        title: 'Archive Category',
        message:
            'Are you sure you want to archive "${category.name}"? It will no longer appear when creating new transactions.',
        confirmLabel: 'Archive',
        onConfirm: () async {
          await context.read<CategoryProvider>().archiveCategory(category.id);
          if (ctx.mounted) Navigator.of(ctx).pop();
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, CategoryEntity category) {
    showDialog<void>(
      context: context,
      builder: (ctx) => ConfirmationDialog(
        title: 'Delete Category',
        message:
            'Are you sure you want to delete "${category.name}"? Existing transactions will retain their historical records.',
        confirmLabel: 'Delete',
        isDestructive: true,
        onConfirm: () async {
          await context.read<CategoryProvider>().deleteCategory(category.id);
          if (ctx.mounted) Navigator.of(ctx).pop();
        },
      ),
    );
  }
}
