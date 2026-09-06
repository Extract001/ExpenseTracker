import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/money_utils.dart';
import '../../providers/budget_provider.dart';
import '../../providers/category_provider.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extensions.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';

class AddEditBudgetModal extends StatefulWidget {
  final String? initialCategoryId;
  final int? initialAmountMinor;
  final bool isCategoryBudget;

  const AddEditBudgetModal({
    super.key,
    this.initialCategoryId,
    this.initialAmountMinor,
    this.isCategoryBudget = false,
  });

  static Future<void> show(
    BuildContext context, {
    String? initialCategoryId,
    int? initialAmountMinor,
    bool isCategoryBudget = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddEditBudgetModal(
        initialCategoryId: initialCategoryId,
        initialAmountMinor: initialAmountMinor,
        isCategoryBudget: isCategoryBudget,
      ),
    );
  }

  @override
  State<AddEditBudgetModal> createState() => _AddEditBudgetModalState();
}

class _AddEditBudgetModalState extends State<AddEditBudgetModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountController;
  String? _selectedCategoryId;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.initialAmountMinor != null
          ? (widget.initialAmountMinor! / 100).toStringAsFixed(2)
          : '',
    );
    _selectedCategoryId = widget.initialCategoryId;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final amountMinor = MoneyUtils.parseToMinorUnits(
      _amountController.text.trim(),
    );
    if (amountMinor <= 0) {
      setState(() => _errorMessage = 'Please enter a budget greater than 0');
      return;
    }

    if (widget.isCategoryBudget && _selectedCategoryId == null) {
      setState(() => _errorMessage = 'Please select a category');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final budgetProvider = context.read<BudgetProvider>();
      if (widget.isCategoryBudget) {
        await budgetProvider.setCategoryBudget(
          categoryId: _selectedCategoryId!,
          limitAmountMinor: amountMinor,
        );
      } else {
        await budgetProvider.setMonthlyBudget(amountMinor: amountMinor);
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
    final categories = context.watch<CategoryProvider>().expenseCategories;

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
                    widget.isCategoryBudget
                        ? 'Set Category Budget'
                        : 'Set Monthly Budget',
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

              if (widget.isCategoryBudget) ...[
                Text(
                  'Expense Category',
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
                        (c) =>
                            DropdownMenuItem(value: c.id, child: Text(c.name)),
                      )
                      .toList(),
                  onChanged: (val) => setState(() => _selectedCategoryId = val),
                  validator: (val) =>
                      val == null ? 'Please select a category' : null,
                ),
                AppSpacing.gapH16,
              ],

              AppTextField(
                label: 'Budget Limit (₹)',
                hint: '10000.00',
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
                    return 'Budget amount is required';
                  }
                  final minor = MoneyUtils.parseToMinorUnits(val.trim());
                  if (minor <= 0) return 'Enter a valid amount';
                  return null;
                },
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
                label: 'Save Budget',
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
