import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/date_time_utils.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/money_utils.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/recurring_transaction_entity.dart';
import '../../providers/account_provider.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/recurring_transaction_provider.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extensions.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';

class AddEditRecurringModal extends StatefulWidget {
  final RecurringTransactionEntity? ruleToEdit;

  const AddEditRecurringModal({super.key, this.ruleToEdit});

  static Future<void> show(
    BuildContext context, {
    RecurringTransactionEntity? ruleToEdit,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddEditRecurringModal(ruleToEdit: ruleToEdit),
    );
  }

  @override
  State<AddEditRecurringModal> createState() => _AddEditRecurringModalState();
}

class _AddEditRecurringModalState extends State<AddEditRecurringModal> {
  final _formKey = GlobalKey<FormState>();

  late TransactionType _selectedType;
  late RecurrenceFrequency _selectedFrequency;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  String? _selectedCategoryId;
  String? _selectedAccountId;
  DateTime _startDate = DateTime.now();

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final edit = widget.ruleToEdit;
    if (edit != null) {
      _selectedType = edit.type;
      _selectedFrequency = edit.frequency;
      _amountController.text = (edit.amount / 100).toStringAsFixed(2);
      _noteController.text = edit.note;
      _selectedCategoryId = edit.categoryId;
      _selectedAccountId = edit.accountId;
      _startDate = edit.startDate.toLocal();
    } else {
      _selectedType = TransactionType.expense;
      _selectedFrequency = RecurrenceFrequency.monthly;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final accProvider = context.read<AccountProvider>();
        final catProvider = context.read<CategoryProvider>();

        if (accProvider.accounts.isNotEmpty && _selectedAccountId == null) {
          setState(() {
            _selectedAccountId = accProvider.accounts.first.id;
          });
        }

        final categories = catProvider.expenseCategories;
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

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final amountMinor = MoneyUtils.parseToMinorUnits(
      _amountController.text.trim(),
    );
    if (amountMinor <= 0) {
      setState(() => _errorMessage = 'Amount must be greater than 0');
      return;
    }

    if (_selectedCategoryId == null) {
      setState(() => _errorMessage = 'Please select a category');
      return;
    }

    if (_selectedAccountId == null) {
      setState(() => _errorMessage = 'Please select an account');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final appState = context.read<AppStateProvider>();
      final recurringProvider = context.read<RecurringTransactionProvider>();
      final nowUtc = DateTime.now().toUtc();
      final startDateUtc = _startDate.toUtc();

      if (widget.ruleToEdit != null) {
        final updated = widget.ruleToEdit!.copyWith(
          amount: amountMinor,
          type: _selectedType,
          categoryId: _selectedCategoryId!,
          accountId: _selectedAccountId!,
          note: _noteController.text.trim(),
          frequency: _selectedFrequency,
          startDate: startDateUtc,
          updatedAt: nowUtc,
        );
        await recurringProvider.updateRule(updated);
      } else {
        final newRule = RecurringTransactionEntity(
          id: IdGenerator.uuid(),
          userId: appState.currentUserId,
          amount: amountMinor,
          type: _selectedType,
          categoryId: _selectedCategoryId!,
          accountId: _selectedAccountId!,
          note: _noteController.text.trim(),
          frequency: _selectedFrequency,
          startDate: startDateUtc,
          nextDate: startDateUtc,
          isActive: true,
          createdAt: nowUtc,
          updatedAt: nowUtc,
        );
        await recurringProvider.createRule(newRule);
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
    final isEditing = widget.ruleToEdit != null;

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
                    isEditing ? 'Edit Recurring Rule' : 'New Recurring Rule',
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

              // Type Selector (Expense | Income)
              Container(
                decoration: BoxDecoration(
                  color: financeColors.surfaceVariant,
                  borderRadius: AppRadius.button,
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() {
                          _selectedType = TransactionType.expense;
                          final cats = catProvider.expenseCategories;
                          _selectedCategoryId = cats.isNotEmpty
                              ? cats.first.id
                              : null;
                        }),
                        borderRadius: AppRadius.button,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedType == TransactionType.expense
                                ? financeColors.expense
                                : Colors.transparent,
                            borderRadius: AppRadius.button,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Expense',
                            style: TextStyle(
                              color: _selectedType == TransactionType.expense
                                  ? Colors.white
                                  : theme.textTheme.bodyMedium?.color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() {
                          _selectedType = TransactionType.income;
                          final cats = catProvider.incomeCategories;
                          _selectedCategoryId = cats.isNotEmpty
                              ? cats.first.id
                              : null;
                        }),
                        borderRadius: AppRadius.button,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedType == TransactionType.income
                                ? financeColors.income
                                : Colors.transparent,
                            borderRadius: AppRadius.button,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Income',
                            style: TextStyle(
                              color: _selectedType == TransactionType.income
                                  ? Colors.white
                                  : theme.textTheme.bodyMedium?.color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AppSpacing.gapH16,

              // Amount
              AppTextField(
                label: 'Recurring Amount (₹)',
                hint: '1500.00',
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
                  return null;
                },
              ),
              AppSpacing.gapH12,

              // Frequency Dropdown
              Text(
                'Recurrence Frequency',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              AppSpacing.gapH4,
              DropdownButtonFormField<RecurrenceFrequency>(
                initialValue: _selectedFrequency,
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                items: RecurrenceFrequency.values
                    .map(
                      (f) => DropdownMenuItem(
                        value: f,
                        child: Text(f.displayName),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedFrequency = val);
                },
              ),
              AppSpacing.gapH12,

              // Category Selector
              Text(
                'Category',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              AppSpacing.gapH4,
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
                      (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _selectedCategoryId = val),
                validator: (val) => val == null ? 'Category is required' : null,
              ),
              AppSpacing.gapH12,

              // Account Selector
              Text(
                'Account',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              AppSpacing.gapH4,
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
                      (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _selectedAccountId = val),
                validator: (val) => val == null ? 'Account is required' : null,
              ),
              AppSpacing.gapH12,

              // Start Date Picker
              Text(
                'Start / Next Execution Date',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              AppSpacing.gapH4,
              InkWell(
                onTap: _pickStartDate,
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
                        DateTimeUtils.formatDate(_startDate),
                        style: theme.textTheme.bodyLarge,
                      ),
                      const Icon(Icons.calendar_today_rounded, size: 18),
                    ],
                  ),
                ),
              ),
              AppSpacing.gapH12,

              // Note Field
              AppTextField(
                label: 'Note / Label',
                hint: 'e.g. Netflix Subscription, House Rent',
                controller: _noteController,
                maxLines: 2,
              ),
              AppSpacing.gapH20,

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

              AppButton(
                label: isEditing ? 'Save Changes' : 'Create Recurring Rule',
                isLoading: _isSaving,
                onPressed: _save,
                variant: AppButtonVariant.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
