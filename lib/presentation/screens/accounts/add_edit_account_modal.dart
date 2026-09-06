import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/currency_constants.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/money_utils.dart';
import '../../../domain/entities/account_entity.dart';
import '../../../domain/entities/enums.dart';
import '../../providers/account_provider.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extensions.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';

class AddEditAccountModal extends StatefulWidget {
  final AccountEntity? accountToEdit;

  const AddEditAccountModal({super.key, this.accountToEdit});

  static Future<void> show(
    BuildContext context, {
    AccountEntity? accountToEdit,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddEditAccountModal(accountToEdit: accountToEdit),
    );
  }

  @override
  State<AddEditAccountModal> createState() => _AddEditAccountModalState();
}

class _AddEditAccountModalState extends State<AddEditAccountModal> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _balanceController;
  late AccountType _selectedType;
  late int _selectedColorValue;
  late int _selectedIconCodePoint;

  bool _isSaving = false;
  String? _errorMessage;

  static const List<int> _palette = [
    0xFF1A56DB, // Blue
    0xFF16A34A, // Green
    0xFFDC2626, // Red
    0xFFD97706, // Amber
    0xFF7C3AED, // Purple
    0xFF0D9488, // Teal
    0xFFDB2777, // Pink
    0xFF4B5563, // Grey
  ];

  static const List<IconData> _accountIcons = [
    Icons.account_balance_wallet_rounded,
    Icons.account_balance_rounded,
    Icons.credit_card_rounded,
    Icons.payments_rounded,
    Icons.savings_rounded,
    Icons.storefront_rounded,
  ];

  @override
  void initState() {
    super.initState();
    final edit = widget.accountToEdit;
    _nameController = TextEditingController(text: edit?.name ?? '');
    _balanceController = TextEditingController(
      text: edit != null
          ? (edit.initialBalance / 100).toStringAsFixed(2)
          : '0.00',
    );
    _selectedType = edit?.type ?? AccountType.bank;
    _selectedColorValue = edit?.colorValue ?? _palette.first;
    _selectedIconCodePoint =
        edit?.iconCodePoint ?? _accountIcons.first.codePoint;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final appState = context.read<AppStateProvider>();
      final settings = context.read<SettingsProvider>();
      final accProvider = context.read<AccountProvider>();

      final balanceMinor = MoneyUtils.parseToMinorUnits(
        _balanceController.text.trim(),
      );
      final nowUtc = DateTime.now().toUtc();

      if (widget.accountToEdit != null) {
        final updated = widget.accountToEdit!.copyWith(
          name: _nameController.text.trim(),
          type: _selectedType,
          initialBalance: balanceMinor,
          colorValue: _selectedColorValue,
          iconCodePoint: _selectedIconCodePoint,
          updatedAt: nowUtc,
        );
        await accProvider.updateAccount(updated);
      } else {
        final newAccount = AccountEntity(
          id: IdGenerator.uuid(),
          userId: appState.currentUserId,
          name: _nameController.text.trim(),
          type: _selectedType,
          initialBalance: balanceMinor,
          currency: settings.currency.isNotEmpty
              ? settings.currency
              : CurrencyConstants.defaultCurrencyCode,
          colorValue: _selectedColorValue,
          iconCodePoint: _selectedIconCodePoint,
          createdAt: nowUtc,
          updatedAt: nowUtc,
        );
        await accProvider.createAccount(newAccount);
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
    final isEditing = widget.accountToEdit != null;

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
                    isEditing ? 'Edit Account' : 'Add Account',
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

              // Name Field
              AppTextField(
                label: 'Account Name',
                hint: 'e.g. HDFC Bank, Cash Wallet',
                controller: _nameController,
                prefixIcon: const Icon(Icons.account_balance_rounded, size: 20),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Account name is required';
                  }
                  return null;
                },
              ),
              AppSpacing.gapH12,

              // Account Type Dropdown
              Text(
                'Account Type',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              AppSpacing.gapH4,
              DropdownButtonFormField<AccountType>(
                initialValue: _selectedType,
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                items: AccountType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(type.displayName),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedType = val);
                  }
                },
              ),
              AppSpacing.gapH12,

              // Initial / Base Balance Field
              AppTextField(
                label: 'Initial Balance (₹)',
                hint: '0.00',
                controller: _balanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                prefixIcon: const Icon(Icons.currency_rupee_rounded, size: 20),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Balance is required';
                  }
                  return null;
                },
              ),
              AppSpacing.gapH16,

              // Color Palette Picker
              Text(
                'Account Color',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              AppSpacing.gapH8,
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: _palette.map((colorVal) {
                  final isSelected = _selectedColorValue == colorVal;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColorValue = colorVal),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(colorVal),
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(
                                color: theme.colorScheme.onSurface,
                                width: 3,
                              )
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 20,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
              AppSpacing.gapH16,

              // Icon Picker
              Text(
                'Account Icon',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              AppSpacing.gapH8,
              Wrap(
                spacing: 12,
                children: _accountIcons.map((iconData) {
                  final isSelected =
                      _selectedIconCodePoint == iconData.codePoint;
                  return GestureDetector(
                    onTap: () => setState(
                      () => _selectedIconCodePoint = iconData.codePoint,
                    ),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Color(_selectedColorValue).withValues(alpha: 0.2)
                            : financeColors.surfaceVariant,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(
                                color: Color(_selectedColorValue),
                                width: 2,
                              )
                            : null,
                      ),
                      child: Icon(
                        iconData,
                        color: isSelected
                            ? Color(_selectedColorValue)
                            : theme.textTheme.bodyMedium?.color,
                        size: 22,
                      ),
                    ),
                  );
                }).toList(),
              ),
              AppSpacing.gapH20,

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

              // Save Button
              AppButton(
                label: isEditing ? 'Save Changes' : 'Create Account',
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
