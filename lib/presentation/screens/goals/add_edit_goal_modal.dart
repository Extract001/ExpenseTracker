import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/date_time_utils.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/money_utils.dart';
import '../../../domain/entities/goal_entity.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/goal_provider.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extensions.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';

class AddEditGoalModal extends StatefulWidget {
  final GoalEntity? goalToEdit;

  const AddEditGoalModal({super.key, this.goalToEdit});

  static Future<void> show(BuildContext context, {GoalEntity? goalToEdit}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddEditGoalModal(goalToEdit: goalToEdit),
    );
  }

  @override
  State<AddEditGoalModal> createState() => _AddEditGoalModalState();
}

class _AddEditGoalModalState extends State<AddEditGoalModal> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _targetAmountController;
  late TextEditingController _currentAmountController;
  late DateTime _targetDate;
  late int _selectedColorValue;
  late int _selectedIconCodePoint;

  bool _isSaving = false;
  String? _errorMessage;

  static const List<int> _palette = [
    0xFF16A34A, // Green
    0xFF1A56DB, // Blue
    0xFFD97706, // Amber
    0xFF7C3AED, // Purple
    0xFFDC2626, // Red
    0xFF0D9488, // Teal
    0xFFDB2777, // Pink
    0xFFEA580C, // Orange
  ];

  static const List<IconData> _goalIcons = [
    Icons.savings_rounded,
    Icons.flight_takeoff_rounded,
    Icons.directions_car_rounded,
    Icons.home_rounded,
    Icons.school_rounded,
    Icons.favorite_rounded,
    Icons.laptop_mac_rounded,
    Icons.diamond_rounded,
  ];

  @override
  void initState() {
    super.initState();
    final edit = widget.goalToEdit;
    _nameController = TextEditingController(text: edit?.name ?? '');
    _targetAmountController = TextEditingController(
      text: edit != null ? (edit.targetAmount / 100).toStringAsFixed(2) : '',
    );
    _currentAmountController = TextEditingController(
      text: edit != null
          ? (edit.currentAmount / 100).toStringAsFixed(2)
          : '0.00',
    );
    _targetDate =
        edit?.targetDate ??
        DateTime.now().toUtc().add(const Duration(days: 180));
    _selectedColorValue = edit?.colorValue ?? _palette.first;
    _selectedIconCodePoint = edit?.iconCodePoint ?? _goalIcons.first.codePoint;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetAmountController.dispose();
    _currentAmountController.dispose();
    super.dispose();
  }

  Future<void> _pickTargetDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _targetDate = picked.toUtc());
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final targetMinor = MoneyUtils.parseToMinorUnits(
      _targetAmountController.text.trim(),
    );
    final currentMinor = MoneyUtils.parseToMinorUnits(
      _currentAmountController.text.trim(),
    );

    if (targetMinor <= 0) {
      setState(() => _errorMessage = 'Target amount must be greater than 0');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final appState = context.read<AppStateProvider>();
      final goalProvider = context.read<GoalProvider>();
      final nowUtc = DateTime.now().toUtc();

      if (widget.goalToEdit != null) {
        final updated = widget.goalToEdit!.copyWith(
          name: _nameController.text.trim(),
          targetAmount: targetMinor,
          currentAmount: currentMinor,
          targetDate: _targetDate,
          colorValue: _selectedColorValue,
          iconCodePoint: _selectedIconCodePoint,
          updatedAt: nowUtc,
        );
        await goalProvider.updateGoal(updated);
      } else {
        final newGoal = GoalEntity(
          id: IdGenerator.uuid(),
          userId: appState.currentUserId,
          name: _nameController.text.trim(),
          targetAmount: targetMinor,
          currentAmount: currentMinor,
          targetDate: _targetDate,
          colorValue: _selectedColorValue,
          iconCodePoint: _selectedIconCodePoint,
          createdAt: nowUtc,
          updatedAt: nowUtc,
        );
        await goalProvider.createGoal(newGoal);
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
    final isEditing = widget.goalToEdit != null;

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
                    isEditing ? 'Edit Savings Goal' : 'New Savings Goal',
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

              AppTextField(
                label: 'Goal Name',
                hint: 'e.g. Emergency Fund, New Car',
                controller: _nameController,
                prefixIcon: const Icon(Icons.flag_rounded, size: 20),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Goal name is required';
                  }
                  return null;
                },
              ),
              AppSpacing.gapH12,

              AppTextField(
                label: 'Target Amount (₹)',
                hint: '50000.00',
                controller: _targetAmountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                prefixIcon: const Icon(Icons.currency_rupee_rounded, size: 20),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Target amount is required';
                  }
                  return null;
                },
              ),
              AppSpacing.gapH12,

              AppTextField(
                label: 'Currently Saved (₹)',
                hint: '0.00',
                controller: _currentAmountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                prefixIcon: const Icon(Icons.savings_rounded, size: 20),
              ),
              AppSpacing.gapH12,

              // Target Date Selector
              Text(
                'Target Date',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              AppSpacing.gapH4,
              InkWell(
                onTap: _pickTargetDate,
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
                        DateTimeUtils.formatDate(_targetDate),
                        style: theme.textTheme.bodyLarge,
                      ),
                      const Icon(Icons.calendar_today_rounded, size: 18),
                    ],
                  ),
                ),
              ),
              AppSpacing.gapH16,

              // Color Palette Picker
              Text(
                'Goal Color',
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
                'Goal Icon',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              AppSpacing.gapH8,
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: _goalIcons.map((iconData) {
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
                label: isEditing ? 'Save Changes' : 'Create Goal',
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
