import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/id_generator.dart';
import '../../../domain/entities/category_entity.dart';
import '../../../domain/entities/enums.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/category_provider.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extensions.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';

class AddEditCategoryModal extends StatefulWidget {
  final CategoryEntity? categoryToEdit;
  final TransactionType initialType;

  const AddEditCategoryModal({
    super.key,
    this.categoryToEdit,
    this.initialType = TransactionType.expense,
  });

  static Future<void> show(
    BuildContext context, {
    CategoryEntity? categoryToEdit,
    TransactionType initialType = TransactionType.expense,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddEditCategoryModal(
        categoryToEdit: categoryToEdit,
        initialType: initialType,
      ),
    );
  }

  @override
  State<AddEditCategoryModal> createState() => _AddEditCategoryModalState();
}

class _AddEditCategoryModalState extends State<AddEditCategoryModal> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TransactionType _selectedType;
  late int _selectedColorValue;
  late int _selectedIconCodePoint;

  bool _isSaving = false;
  String? _errorMessage;

  static const List<int> _palette = [
    0xFFDC2626, // Red
    0xFF16A34A, // Green
    0xFF1A56DB, // Blue
    0xFFD97706, // Amber
    0xFF7C3AED, // Purple
    0xFF0D9488, // Teal
    0xFFDB2777, // Pink
    0xFF4B5563, // Grey
    0xFFEA580C, // Orange
    0xFF0284C7, // Sky
  ];

  static const List<IconData> _categoryIcons = [
    Icons.restaurant_rounded,
    Icons.shopping_bag_rounded,
    Icons.directions_car_rounded,
    Icons.home_rounded,
    Icons.movie_rounded,
    Icons.health_and_safety_rounded,
    Icons.school_rounded,
    Icons.flight_rounded,
    Icons.account_balance_wallet_rounded,
    Icons.work_rounded,
    Icons.savings_rounded,
    Icons.card_giftcard_rounded,
  ];

  @override
  void initState() {
    super.initState();
    final edit = widget.categoryToEdit;
    _nameController = TextEditingController(text: edit?.name ?? '');
    _selectedType = edit?.type ?? widget.initialType;
    _selectedColorValue = edit?.colorValue ?? _palette.first;
    _selectedIconCodePoint =
        edit?.iconCodePoint ?? _categoryIcons.first.codePoint;
  }

  @override
  void dispose() {
    _nameController.dispose();
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
      final catProvider = context.read<CategoryProvider>();
      final nowUtc = DateTime.now().toUtc();

      if (widget.categoryToEdit != null) {
        final updated = widget.categoryToEdit!.copyWith(
          name: _nameController.text.trim(),
          type: _selectedType,
          colorValue: _selectedColorValue,
          iconCodePoint: _selectedIconCodePoint,
          updatedAt: nowUtc,
        );
        await catProvider.updateCategory(updated);
      } else {
        final newCategory = CategoryEntity(
          id: IdGenerator.uuid(),
          userId: appState.currentUserId,
          name: _nameController.text.trim(),
          iconCodePoint: _selectedIconCodePoint,
          colorValue: _selectedColorValue,
          type: _selectedType,
          isSystem: false,
          isArchived: false,
          createdAt: nowUtc,
          updatedAt: nowUtc,
        );
        await catProvider.createCategory(newCategory);
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
    final isEditing = widget.categoryToEdit != null;
    final isSystem = widget.categoryToEdit?.isSystem ?? false;

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
                    isEditing ? 'Edit Category' : 'Add Category',
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
              if (!isSystem) ...[
                Container(
                  decoration: BoxDecoration(
                    color: financeColors.surfaceVariant,
                    borderRadius: AppRadius.button,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TypeButton(
                          label: 'Expense',
                          isSelected: _selectedType == TransactionType.expense,
                          selectedColor: financeColors.expense,
                          onTap: () => setState(
                            () => _selectedType = TransactionType.expense,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _TypeButton(
                          label: 'Income',
                          isSelected: _selectedType == TransactionType.income,
                          selectedColor: financeColors.income,
                          onTap: () => setState(
                            () => _selectedType = TransactionType.income,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                AppSpacing.gapH16,
              ],

              // Category Name Field
              AppTextField(
                label: 'Category Name',
                hint: 'e.g. Groceries, Freelance',
                controller: _nameController,
                prefixIcon: const Icon(Icons.category_rounded, size: 20),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Category name is required';
                  }
                  return null;
                },
              ),
              AppSpacing.gapH16,

              // Color Palette Picker
              Text(
                'Category Color',
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
                'Category Icon',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              AppSpacing.gapH8,
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: _categoryIcons.map((iconData) {
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
                label: isEditing ? 'Save Changes' : 'Create Category',
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

class _TypeButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _TypeButton({
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
