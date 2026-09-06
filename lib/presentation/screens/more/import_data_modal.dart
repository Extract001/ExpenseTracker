import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/backup/backup_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/database/app_database.dart';
import '../../providers/account_provider.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/currency_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/recurring_transaction_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extensions.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';

class ImportDataModal extends StatefulWidget {
  const ImportDataModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ImportDataModal(),
    );
  }

  @override
  State<ImportDataModal> createState() => _ImportDataModalState();
}

class _ImportDataModalState extends State<ImportDataModal> {
  final _jsonController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isRestoring = false;
  String? _errorMessage;

  @override
  void dispose() {
    _jsonController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() {
        _jsonController.text = data.text!;
        _errorMessage = null;
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Clipboard is empty')));
      }
    }
  }

  Future<void> _restoreData() async {
    final jsonText = _jsonController.text.trim();
    if (jsonText.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter or paste the backup JSON content.';
      });
      return;
    }

    setState(() {
      _isRestoring = true;
      _errorMessage = null;
    });

    try {
      final db = context.read<AppDatabase?>() ?? AppDatabase();
      final backupService = context.read<BackupService?>() ?? BackupService(db);
      final userId =
          context.read<AppStateProvider?>()?.currentUserId ??
          AppConstants.defaultUserId;
      final password = _passwordController.text.trim().isNotEmpty
          ? _passwordController.text.trim()
          : null;

      await backupService.restoreFromBackup(
        jsonText,
        password: password,
        targetUserId: userId,
        allowCrossUserRestore: true,
      );

      if (mounted) {
        // Refresh all providers so UI immediately renders the restored data
        context.read<TransactionProvider?>()?.reset(reload: true);
        context.read<AccountProvider?>()?.reset(reload: true);
        context.read<CategoryProvider?>()?.reset(reload: true);
        context.read<BudgetProvider?>()?.reset(reload: true);
        context.read<GoalProvider?>()?.reset(reload: true);
        context.read<RecurringTransactionProvider?>()?.reset(reload: true);
        context.read<SettingsProvider?>()?.reset(reload: true);
        context.read<CurrencyProvider?>()?.refreshRatesOnline();

        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Backup restored successfully! All financial records refreshed.',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRestoring = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;
    final mediaQuery = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.85),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: financeColors.cardBorder,
                    borderRadius: AppRadius.pill,
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.12),
                        borderRadius: AppRadius.card,
                      ),
                      child: const Icon(
                        Icons.file_upload_outlined,
                        color: Colors.indigo,
                        size: 24,
                      ),
                    ),
                    AppSpacing.gapW16,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Import & Restore Data',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Restore financial records from backup JSON',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Body
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'Paste Backup JSON Payload',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    AppSpacing.gapH4,
                    Text(
                      'The backup will be validated against database integrity rules before updating your records.',
                      style: theme.textTheme.bodySmall,
                    ),
                    AppSpacing.gapH12,

                    // JSON Input Area
                    TextField(
                      controller: _jsonController,
                      minLines: 4,
                      maxLines: 7,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            '{\n  "metadata": { ... },\n  "data": { ... }\n}',
                        border: OutlineInputBorder(
                          borderRadius: AppRadius.card,
                        ),
                        suffixIcon: IconButton(
                          tooltip: 'Paste from clipboard',
                          icon: const Icon(Icons.paste_rounded),
                          onPressed: _pasteFromClipboard,
                        ),
                      ),
                    ),
                    AppSpacing.gapH16,

                    // Password Field
                    AppTextField(
                      controller: _passwordController,
                      label: 'Decryption Password (Optional)',
                      hint: 'Required if backup was encrypted with a password',
                      obscureText: _obscurePassword,
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    AppSpacing.gapH16,

                    // Error Box
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: financeColors.expenseContainer,
                          borderRadius: AppRadius.card,
                          border: Border.all(
                            color: financeColors.expense.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: financeColors.expense,
                              size: 20,
                            ),
                            AppSpacing.gapW8,
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: financeColors.expense,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      AppSpacing.gapH16,
                    ],

                    AppButton(
                      label: _isRestoring
                          ? 'Validating & Restoring...'
                          : 'Restore & Merge Backup',
                      isLoading: _isRestoring,
                      icon: const Icon(Icons.cloud_download_rounded, size: 20),
                      onPressed: _isRestoring ? null : _restoreData,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
