import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/date_time_utils.dart';
import '../../../domain/entities/enums.dart';
import '../../providers/account_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/add_transaction_modal.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/transaction_filter_modal.dart';
import '../../widgets/transaction_tile.dart';
import 'transaction_detail_screen.dart';

class TransactionsTabScreen extends StatefulWidget {
  const TransactionsTabScreen({super.key});

  @override
  State<TransactionsTabScreen> createState() => _TransactionsTabScreenState();
}

class _TransactionsTabScreenState extends State<TransactionsTabScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AccountProvider>().watchAccounts();
        context.read<CategoryProvider>().watchCategories();
        context.read<TransactionProvider>().loadTransactions();
      }
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<TransactionProvider>().loadMore();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txProvider = context.watch<TransactionProvider>();
    final catProvider = context.watch<CategoryProvider>();
    final accProvider = context.watch<AccountProvider>();

    final transactions = txProvider.transactions;
    final filter = txProvider.filter;
    final isLoadingInitial = txProvider.isLoadingInitial;
    final isLoadingMore = txProvider.isLoadingMore;
    final error = txProvider.error;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: filter.hasActiveFilters,
              child: const Icon(Icons.tune_rounded),
            ),
            tooltip: 'Filter transactions',
            onPressed: () => TransactionFilterModal.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add Transaction',
            onPressed: () => AddTransactionModal.show(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search transactions...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          txProvider.clearSearch();
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: (val) => txProvider.setSearchQuery(val),
            ),
          ),

          // Active Filter Chips
          if (filter.hasActiveFilters)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  if (filter.type != null) ...[
                    InputChip(
                      label: Text(filter.type!.displayName),
                      onDeleted: () => txProvider.updateFilter(clearType: true),
                    ),
                    AppSpacing.gapW8,
                  ],
                  if (filter.categoryId != null) ...[
                    InputChip(
                      label: Text(
                        catProvider.getCategoryById(filter.categoryId!)?.name ??
                            'Category',
                      ),
                      onDeleted: () =>
                          txProvider.updateFilter(clearCategory: true),
                    ),
                    AppSpacing.gapW8,
                  ],
                  if (filter.accountId != null) ...[
                    InputChip(
                      label: Text(
                        accProvider.getAccountById(filter.accountId!)?.name ??
                            'Account',
                      ),
                      onDeleted: () =>
                          txProvider.updateFilter(clearAccount: true),
                    ),
                    AppSpacing.gapW8,
                  ],
                  if (filter.startDate != null && filter.endDate != null) ...[
                    InputChip(
                      label: Text(
                        '${DateTimeUtils.formatDate(filter.startDate!)} - ${DateTimeUtils.formatDate(filter.endDate!)}',
                      ),
                      onDeleted: () => txProvider.updateFilter(
                        clearStartDate: true,
                        clearEndDate: true,
                      ),
                    ),
                    AppSpacing.gapW8,
                  ],
                  if (filter.minAmount != null || filter.maxAmount != null) ...[
                    InputChip(
                      label: Text(
                        '₹${(filter.minAmount ?? 0) / 100} - ₹${(filter.maxAmount ?? 0) / 100}',
                      ),
                      onDeleted: () => txProvider.updateFilter(
                        clearMinAmount: true,
                        clearMaxAmount: true,
                      ),
                    ),
                    AppSpacing.gapW8,
                  ],
                  TextButton(
                    onPressed: () => txProvider.resetFilter(),
                    child: const Text('Clear All'),
                  ),
                ],
              ),
            ),

          // Transaction List or States
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => txProvider.refresh(),
              child: _buildBody(
                context: context,
                isLoadingInitial: isLoadingInitial,
                isLoadingMore: isLoadingMore,
                error: error,
                transactions: transactions,
                catProvider: catProvider,
                accProvider: accProvider,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required bool isLoadingInitial,
    required bool isLoadingMore,
    required String? error,
    required List transactions,
    required CategoryProvider catProvider,
    required AccountProvider accProvider,
  }) {
    if (isLoadingInitial && transactions.isEmpty) {
      return const Padding(
        padding: AppSpacing.screenPadding,
        child: TransactionListSkeleton(itemCount: 8),
      );
    }

    if (error != null && transactions.isEmpty) {
      return Center(
        child: ErrorState(
          title: 'Failed to Load Transactions',
          message: error,
          onRetry: () => context.read<TransactionProvider>().loadTransactions(),
        ),
      );
    }

    if (transactions.isEmpty) {
      final hasFilter = context
          .read<TransactionProvider>()
          .filter
          .hasActiveFilters;
      return Center(
        child: EmptyState(
          icon: Icons.receipt_long_rounded,
          title: hasFilter ? 'No Matching Transactions' : 'No Transactions Yet',
          message: hasFilter
              ? 'Try resetting your search query or filters.'
              : 'Record your expenses, income, or transfers to start tracking your finances.',
          actionLabel: hasFilter ? 'Clear Filters' : 'Add Transaction',
          onActionPressed: () {
            if (hasFilter) {
              context.read<TransactionProvider>().resetFilter();
              _searchController.clear();
            } else {
              AddTransactionModal.show(context);
            }
          },
        ),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: AppSpacing.screenPadding,
      itemCount: transactions.length + (isLoadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == transactions.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          );
        }

        final tx = transactions[index];
        final category = catProvider.getCategoryById(tx.categoryId);
        final account = accProvider.getAccountById(tx.accountId);
        final toAccount = tx.toAccountId != null
            ? accProvider.getAccountById(tx.toAccountId!)
            : null;

        final accountLabel =
            tx.type == TransactionType.transfer && toAccount != null
            ? '${account?.name ?? 'Account'} → ${toAccount.name}'
            : account?.name;

        return TransactionTile(
          transaction: tx,
          categoryName: category?.name,
          accountName: accountLabel,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TransactionDetailScreen(transaction: tx),
              ),
            );
          },
        );
      },
    );
  }
}
