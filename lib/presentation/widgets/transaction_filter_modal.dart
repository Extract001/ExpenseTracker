import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/utils/date_time_utils.dart';
import '../../core/utils/money_utils.dart';
import '../../domain/entities/enums.dart';
import '../providers/account_provider.dart';
import '../providers/category_provider.dart';
import '../providers/transaction_provider.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_extensions.dart';
import 'app_button.dart';
import 'app_text_field.dart';

class TransactionFilterModal extends StatefulWidget {
  const TransactionFilterModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const TransactionFilterModal(),
    );
  }

  @override
  State<TransactionFilterModal> createState() => _TransactionFilterModalState();
}

class _TransactionFilterModalState extends State<TransactionFilterModal> {
  TransactionType? _selectedType;
  String? _selectedCategoryId;
  String? _selectedAccountId;
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _minAmountController = TextEditingController();
  final TextEditingController _maxAmountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final filter = context.read<TransactionProvider>().filter;
    _selectedType = filter.type;
    _selectedCategoryId = filter.categoryId;
    _selectedAccountId = filter.accountId;
    _startDate = filter.startDate;
    _endDate = filter.endDate;
    if (filter.minAmount != null) {
      _minAmountController.text = (filter.minAmount! / 100).toStringAsFixed(2);
    }
    if (filter.maxAmount != null) {
      _maxAmountController.text = (filter.maxAmount! / 100).toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _minAmountController.dispose();
    _maxAmountController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start.toUtc();
        _endDate = picked.end.toUtc();
      });
    }
  }

  void _applyFilters() {
    final minAmount = _minAmountController.text.trim().isNotEmpty
        ? MoneyUtils.parseToMinorUnits(_minAmountController.text.trim())
        : null;
    final maxAmount = _maxAmountController.text.trim().isNotEmpty
        ? MoneyUtils.parseToMinorUnits(_maxAmountController.text.trim())
        : null;

    final newFilter = TransactionFilterState(
      type: _selectedType,
      categoryId: _selectedCategoryId,
      accountId: _selectedAccountId,
      startDate: _startDate,
      endDate: _endDate,
      minAmount: minAmount,
      maxAmount: maxAmount,
      searchQuery: context.read<TransactionProvider>().filter.searchQuery,
    );

    context.read<TransactionProvider>().setFilter(newFilter);
    Navigator.of(context).pop();
  }

  void _clearFilters() {
    context.read<TransactionProvider>().resetFilter();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final categories = context.watch<CategoryProvider>().categories;
    final accounts = context.watch<AccountProvider>().accounts;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.modalTop,
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: bottomInset + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: financeColors.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            AppSpacing.gapH16,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filter Transactions',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextButton(
                  onPressed: _clearFilters,
                  child: const Text('Reset All'),
                ),
              ],
            ),
            AppSpacing.gapH16,

            // Transaction Type Chips
            Text(
              'Transaction Type',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            AppSpacing.gapH8,
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All Types'),
                  selected: _selectedType == null,
                  onSelected: (_) => setState(() => _selectedType = null),
                ),
                ChoiceChip(
                  label: const Text('Expense'),
                  selected: _selectedType == TransactionType.expense,
                  onSelected: (_) =>
                      setState(() => _selectedType = TransactionType.expense),
                ),
                ChoiceChip(
                  label: const Text('Income'),
                  selected: _selectedType == TransactionType.income,
                  onSelected: (_) =>
                      setState(() => _selectedType = TransactionType.income),
                ),
                ChoiceChip(
                  label: const Text('Transfer'),
                  selected: _selectedType == TransactionType.transfer,
                  onSelected: (_) =>
                      setState(() => _selectedType = TransactionType.transfer),
                ),
              ],
            ),
            AppSpacing.gapH16,

            // Category Filter
            Text(
              'Category',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            AppSpacing.gapH4,
            DropdownButtonFormField<String?>(
              initialValue: _selectedCategoryId,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All Categories'),
                ),
                ...categories.map(
                  (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                ),
              ],
              onChanged: (val) => setState(() => _selectedCategoryId = val),
            ),
            AppSpacing.gapH16,

            // Account Filter
            Text(
              'Account',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            AppSpacing.gapH4,
            DropdownButtonFormField<String?>(
              initialValue: _selectedAccountId,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All Accounts'),
                ),
                ...accounts.map(
                  (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                ),
              ],
              onChanged: (val) => setState(() => _selectedAccountId = val),
            ),
            AppSpacing.gapH16,

            // Date Range Selector
            Text(
              'Date Range',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            AppSpacing.gapH4,
            InkWell(
              onTap: _pickDateRange,
              borderRadius: AppRadius.input,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: financeColors.surfaceVariant,
                  borderRadius: AppRadius.input,
                  border: Border.all(color: financeColors.cardBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _startDate != null && _endDate != null
                          ? '${DateTimeUtils.formatDate(_startDate!)} - ${DateTimeUtils.formatDate(_endDate!)}'
                          : 'All Time (No date filter)',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const Icon(Icons.date_range_rounded, size: 20),
                  ],
                ),
              ),
            ),
            AppSpacing.gapH16,

            // Amount Range
            Text(
              'Amount Range (₹)',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            AppSpacing.gapH4,
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'Min Amount',
                    hint: '0.00',
                    controller: _minAmountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}'),
                      ),
                    ],
                  ),
                ),
                AppSpacing.gapW12,
                Expanded(
                  child: AppTextField(
                    label: 'Max Amount',
                    hint: '10000.00',
                    controller: _maxAmountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            AppSpacing.gapH24,

            // Apply Button
            AppButton(
              label: 'Apply Filters',
              onPressed: _applyFilters,
              variant: AppButtonVariant.primary,
            ),
          ],
        ),
      ),
    );
  }
}
