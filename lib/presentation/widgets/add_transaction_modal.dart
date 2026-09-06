import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/utils/date_time_utils.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/money_utils.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/transaction_entity.dart';
import '../providers/account_provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/category_provider.dart';
import '../providers/transaction_provider.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_extensions.dart';
import 'app_button.dart';
import 'app_text_field.dart';

/// Modal bottom sheet form for adding and editing transactions and transfers.
class AddTransactionModal extends StatefulWidget {
  final TransactionType initialType;
  final TransactionEntity? transactionToEdit;

  const AddTransactionModal({
    super.key,
    this.initialType = TransactionType.expense,
    this.transactionToEdit,
  });

  static Future<void> show(
    BuildContext context, {
    TransactionType initialType = TransactionType.expense,
    TransactionEntity? transactionToEdit,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddTransactionModal(
        initialType: initialType,
        transactionToEdit: transactionToEdit,
      ),
    );
  }

  @override
  State<AddTransactionModal> createState() => _AddTransactionModalState();
}

class _AddTransactionModalState extends State<AddTransactionModal> {
  final _formKey = GlobalKey<FormState>();

  late TransactionType _selectedType;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  String? _selectedCategoryId;
  String? _selectedAccountId;
  String? _selectedToAccountId; // for Transfer
  DateTime _selectedDate = DateTime.now();

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final edit = widget.transactionToEdit;
    if (edit != null) {
      _selectedType = edit.type;
      _amountController.text = (edit.amount / 100).toStringAsFixed(2);
      _noteController.text = edit.note;
      _selectedCategoryId = edit.categoryId;
      _selectedAccountId = edit.accountId;
      _selectedToAccountId = edit.toAccountId;
      _selectedDate = edit.date.toLocal();
    } else {
      _selectedType = widget.initialType;

      // Preselect first account and category if available
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final accProvider = context.read<AccountProvider>();
        final catProvider = context.read<CategoryProvider>();

        if (accProvider.accounts.isNotEmpty && _selectedAccountId == null) {
          setState(() {
            _selectedAccountId = accProvider.accounts.first.id;
            if (accProvider.accounts.length > 1) {
              _selectedToAccountId = accProvider.accounts[1].id;
            }
          });
        }

        final categories = _selectedType == TransactionType.income
            ? catProvider.incomeCategories
            : catProvider.expenseCategories;
        if (categories.isNotEmpty && _selectedCategoryId == null) {
          setState(() {
            _selectedCategoryId = categories.first.id;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onTypeChanged(TransactionType newType) {
    if (_selectedType == newType) return;
    setState(() {
      _selectedType = newType;
      _errorMessage = null;

      final catProvider = context.read<CategoryProvider>();
      final categories = _selectedType == TransactionType.income
          ? catProvider.incomeCategories
          : catProvider.expenseCategories;
      if (categories.isNotEmpty) {
        _selectedCategoryId = categories.first.id;
      } else {
        _selectedCategoryId = null;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _selectedDate.hour,
          _selectedDate.minute,
        );
      });
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    final amountMinor = MoneyUtils.parseToMinorUnits(
      _amountController.text.trim(),
    );
    if (amountMinor <= 0) {
      setState(() => _errorMessage = 'Please enter an amount greater than 0');
      return;
    }

    if (_selectedType == TransactionType.transfer) {
      if (_selectedAccountId == null || _selectedToAccountId == null) {
        setState(
          () => _errorMessage =
              'Please select both source and destination accounts',
        );
        return;
      }
      if (_selectedAccountId == _selectedToAccountId) {
        setState(
          () => _errorMessage =
              'Source and destination accounts must be different',
        );
        return;
      }
    } else {
      if (_selectedAccountId == null) {
        setState(() => _errorMessage = 'Please select an account');
        return;
      }
      if (_selectedCategoryId == null) {
        setState(() => _errorMessage = 'Please select a category');
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final appState = context.read<AppStateProvider>();
      final txProvider = context.read<TransactionProvider>();
      final nowUtc = DateTime.now().toUtc();
      final txDateUtc = _selectedDate.toUtc();

      if (widget.transactionToEdit != null) {
        final updated = widget.transactionToEdit!.copyWith(
          amount: amountMinor,
          type: _selectedType,
          categoryId:
              _selectedCategoryId ?? widget.transactionToEdit!.categoryId,
          accountId: _selectedAccountId!,
          toAccountId: _selectedToAccountId,
          note: _noteController.text.trim(),
          date: txDateUtc,
          updatedAt: nowUtc,
        );
        await txProvider.updateTransaction(updated);
      } else {
        if (_selectedType == TransactionType.transfer) {
          final accProvider = context.read<AccountProvider>();
          await accProvider.transferFunds(
            fromAccountId: _selectedAccountId!,
            toAccountId: _selectedToAccountId!,
            amountMinor: amountMinor,
            note: _noteController.text.trim(),
            date: txDateUtc,
          );
        } else {
          final tx = TransactionEntity(
            id: IdGenerator.uuid(),
            userId: appState.currentUserId,
            amount: amountMinor,
            type: _selectedType,
            categoryId: _selectedCategoryId!,
            accountId: _selectedAccountId!,
            note: _noteController.text.trim(),
            date: txDateUtc,
            createdAt: nowUtc,
            updatedAt: nowUtc,
          );
          await txProvider.createTransaction(tx);
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isEditing = widget.transactionToEdit != null;

    final accounts = context.watch<AccountProvider>().accounts;
    final catProvider = context.watch<CategoryProvider>();
    final categories = _selectedType == TransactionType.income
        ? catProvider.incomeCategories
        : catProvider.expenseCategories;

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
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Drag Handle & Title
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
                    isEditing ? 'Edit Transaction' : 'Add Transaction',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              AppSpacing.gapH16,

              // Segmented Type Selector (Expense | Income | Transfer)
              if (!isEditing) ...[
                Container(
                  decoration: BoxDecoration(
                    color: financeColors.surfaceVariant,
                    borderRadius: AppRadius.button,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TypeSegmentButton(
                          label: 'Expense',
                          isSelected: _selectedType == TransactionType.expense,
                          selectedColor: financeColors.expense,
                          onTap: () => _onTypeChanged(TransactionType.expense),
                        ),
                      ),
                      Expanded(
                        child: _TypeSegmentButton(
                          label: 'Income',
                          isSelected: _selectedType == TransactionType.income,
                          selectedColor: financeColors.income,
                          onTap: () => _onTypeChanged(TransactionType.income),
                        ),
                      ),
                      Expanded(
                        child: _TypeSegmentButton(
                          label: 'Transfer',
                          isSelected: _selectedType == TransactionType.transfer,
                          selectedColor: financeColors.transfer,
                          onTap: () => _onTypeChanged(TransactionType.transfer),
                        ),
                      ),
                    ],
                  ),
                ),
                AppSpacing.gapH16,
              ],

              // Amount Field
              AppTextField(
                label: 'Amount (₹)',
                hint: '0.00',
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                prefixIcon: const Icon(Icons.currency_rupee_rounded, size: 20),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Amount is required';
                  }
                  final minor = MoneyUtils.parseToMinorUnits(val.trim());
                  if (minor <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              AppSpacing.gapH12,

              // Category Selector (only for Expense and Income)
              if (_selectedType != TransactionType.transfer) ...[
                Text(
                  'Category',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AppSpacing.gapH4,
                if (categories.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: financeColors.surfaceVariant,
                      borderRadius: AppRadius.input,
                    ),
                    child: const Text('No categories available'),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCategoryId,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    items: categories
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedCategoryId = val),
                    validator: (val) =>
                        val == null ? 'Category is required' : null,
                  ),
                AppSpacing.gapH12,
              ],

              // Account Selector (Source Account)
              Text(
                _selectedType == TransactionType.transfer
                    ? 'From Account'
                    : 'Account',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              AppSpacing.gapH4,
              if (accounts.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: financeColors.surfaceVariant,
                    borderRadius: AppRadius.input,
                  ),
                  child: const Text(
                    'No accounts found. Create an account first.',
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _selectedAccountId,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  items: accounts
                      .map(
                        (a) =>
                            DropdownMenuItem(value: a.id, child: Text(a.name)),
                      )
                      .toList(),
                  onChanged: (val) => setState(() => _selectedAccountId = val),
                  validator: (val) =>
                      val == null ? 'Account is required' : null,
                ),
              AppSpacing.gapH12,

              // Destination Account Selector (only for Transfer)
              if (_selectedType == TransactionType.transfer) ...[
                Text(
                  'To Account',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AppSpacing.gapH4,
                DropdownButtonFormField<String>(
                  initialValue: _selectedToAccountId,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  items: accounts
                      .map(
                        (a) =>
                            DropdownMenuItem(value: a.id, child: Text(a.name)),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setState(() => _selectedToAccountId = val),
                  validator: (val) {
                    if (val == null) return 'Destination account is required';
                    if (val == _selectedAccountId) {
                      return 'Must be different from source account';
                    }
                    return null;
                  },
                ),
                AppSpacing.gapH12,
              ],

              // Date Picker Field
              Text(
                'Date',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              AppSpacing.gapH4,
              InkWell(
                onTap: _pickDate,
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
                        DateTimeUtils.formatDate(_selectedDate),
                        style: theme.textTheme.bodyLarge,
                      ),
                      const Icon(Icons.calendar_today_rounded, size: 18),
                    ],
                  ),
                ),
              ),
              AppSpacing.gapH12,

              // Note Input
              AppTextField(
                label: 'Note / Description',
                hint: 'e.g. Groceries at supermarket',
                controller: _noteController,
                maxLines: 2,
              ),
              AppSpacing.gapH16,

              // Error banner if any
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: financeColors.expenseContainer,
                    borderRadius: AppRadius.input,
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: financeColors.expense,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                AppSpacing.gapH16,
              ],

              // Submit Button
              AppButton(
                label: isEditing
                    ? 'Save Changes'
                    : (_selectedType == TransactionType.transfer
                          ? 'Transfer Funds'
                          : 'Save Transaction'),
                isLoading: _isSaving,
                onPressed: _submitForm,
                variant: AppButtonVariant.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeSegmentButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _TypeSegmentButton({
    required this.label,
    required this.isSelected,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.button,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? selectedColor : Colors.transparent,
          borderRadius: AppRadius.button,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : Theme.of(context).textTheme.bodyMedium?.color,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
