import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../../core/backup/backup_service.dart';
import '../../../core/backup/export_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/database/app_database.dart';
import '../../providers/app_state_provider.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extensions.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_text_field.dart';

enum ExportDateFilter { allTime, thisMonth, last30Days }

class ExportDataModal extends StatefulWidget {
  const ExportDataModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ExportDataModal(),
    );
  }

  @override
  State<ExportDataModal> createState() => _ExportDataModalState();
}

class _ExportDataModalState extends State<ExportDataModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // CSV Tab State
  ExportDateFilter _csvDateFilter = ExportDateFilter.allTime;
  bool _isExportingCsv = false;
  String? _csvResultPath;
  String? _csvContent;
  int? _csvRowCount;

  // JSON Tab State
  bool _encryptBackup = false;
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isExportingJson = false;
  String? _jsonResultPath;
  String? _jsonContent;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _exportCsv() async {
    setState(() {
      _isExportingCsv = true;
      _csvResultPath = null;
      _csvContent = null;
      _csvRowCount = null;
    });

    try {
      final db = context.read<AppDatabase?>() ?? AppDatabase();
      final exportService = context.read<ExportService?>() ?? ExportService(db);
      final userId =
          context.read<AppStateProvider?>()?.currentUserId ??
          AppConstants.defaultUserId;

      DateTime? startDate;
      DateTime? endDate;
      final now = DateTime.now();

      switch (_csvDateFilter) {
        case ExportDateFilter.allTime:
          startDate = null;
          endDate = null;
          break;
        case ExportDateFilter.thisMonth:
          startDate = DateTime(now.year, now.month, 1);
          endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
          break;
        case ExportDateFilter.last30Days:
          startDate = now.subtract(const Duration(days: 30));
          endDate = now;
          break;
      }

      final csvData = await exportService.exportTransactionsCsv(
        userId: userId,
        startDate: startDate,
        endDate: endDate,
      );

      final lines = csvData.split('\n').where((l) => l.trim().isNotEmpty);
      final count = lines.length > 1 ? lines.length - 1 : 0;

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${directory.path}/transactions_export_$timestamp.csv');
      await file.writeAsString(csvData);

      if (mounted) {
        setState(() {
          _isExportingCsv = false;
          _csvResultPath = file.path;
          _csvContent = csvData;
          _csvRowCount = count;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExportingCsv = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CSV Export failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _exportJson() async {
    if (_encryptBackup && _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an encryption password for the backup.'),
        ),
      );
      return;
    }

    setState(() {
      _isExportingJson = true;
      _jsonResultPath = null;
      _jsonContent = null;
    });

    try {
      final db = context.read<AppDatabase?>() ?? AppDatabase();
      final backupService = context.read<BackupService?>() ?? BackupService(db);
      final userId =
          context.read<AppStateProvider?>()?.currentUserId ??
          AppConstants.defaultUserId;

      final password = _encryptBackup ? _passwordController.text.trim() : null;

      final jsonData = await backupService.createFullBackup(
        password: password,
        userId: userId,
      );

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${directory.path}/expense_backup_$timestamp.json');
      await file.writeAsString(jsonData);

      if (mounted) {
        setState(() {
          _isExportingJson = false;
          _jsonResultPath = file.path;
          _jsonContent = jsonData;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExportingJson = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('JSON Backup failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.12),
                      borderRadius: AppRadius.card,
                    ),
                    child: const Icon(
                      Icons.file_download_outlined,
                      color: Colors.teal,
                      size: 24,
                    ),
                  ),
                  AppSpacing.gapW16,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Export Financial Data',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Save CSV spreadsheets or JSON backup archives',
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

            // Tab Bar
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(
                  icon: Icon(Icons.table_chart_outlined, size: 20),
                  text: 'CSV Spreadsheet',
                ),
                Tab(
                  icon: Icon(Icons.backup_outlined, size: 20),
                  text: 'JSON Backup',
                ),
              ],
            ),

            // Tab Views
            Flexible(
              child: TabBarView(
                controller: _tabController,
                children: [_buildCsvTab(context), _buildJsonTab(context)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCsvTab(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Date Range Filter',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        AppSpacing.gapH8,
        SegmentedButton<ExportDateFilter>(
          segments: const [
            ButtonSegment(
              value: ExportDateFilter.allTime,
              label: Text('All Time'),
            ),
            ButtonSegment(
              value: ExportDateFilter.thisMonth,
              label: Text('This Month'),
            ),
            ButtonSegment(
              value: ExportDateFilter.last30Days,
              label: Text('Last 30 Days'),
            ),
          ],
          selected: {_csvDateFilter},
          onSelectionChanged: (newSelection) {
            setState(() {
              _csvDateFilter = newSelection.first;
              _csvResultPath = null;
            });
          },
        ),
        AppSpacing.gapH16,
        Text(
          'Exports standard RFC 4180 CSV containing Date, Type, Category, Account, Amount, Currency, and Note.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodyMedium?.color,
          ),
        ),
        AppSpacing.gapH24,

        if (_csvResultPath != null) ...[
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: financeColors.income,
                      size: 22,
                    ),
                    AppSpacing.gapW8,
                    Text(
                      'CSV Exported Successfully!',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: financeColors.income,
                      ),
                    ),
                  ],
                ),
                AppSpacing.gapH8,
                Text(
                  'Total Transactions: $_csvRowCount',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AppSpacing.gapH4,
                Text(
                  'Saved to: $_csvResultPath',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
                AppSpacing.gapH12,
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Copy CSV Text',
                        variant: AppButtonVariant.outline,
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        onPressed: () {
                          if (_csvContent != null) {
                            Clipboard.setData(
                              ClipboardData(text: _csvContent!),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('CSV copied to clipboard!'),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          AppSpacing.gapH16,
        ],

        AppButton(
          label: _isExportingCsv ? 'Exporting...' : 'Export & Save CSV',
          isLoading: _isExportingCsv,
          icon: const Icon(Icons.file_download_rounded, size: 20),
          onPressed: _isExportingCsv ? null : _exportCsv,
        ),
      ],
    );
  }

  Widget _buildJsonTab(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Complete System Backup',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        AppSpacing.gapH4,
        Text(
          'Creates a full snapshot of accounts, categories, transactions, budgets, goals, and sync cursors.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodyMedium?.color,
          ),
        ),
        AppSpacing.gapH16,

        // Password Encryption Toggle
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Encrypt Backup with Password'),
          subtitle: const Text(
            'Secures archive using AES-256-GCM + PBKDF2 key derivation (100k iterations)',
          ),
          value: _encryptBackup,
          onChanged: (val) {
            setState(() {
              _encryptBackup = val;
              _jsonResultPath = null;
            });
          },
        ),

        if (_encryptBackup) ...[
          AppSpacing.gapH8,
          AppTextField(
            controller: _passwordController,
            label: 'Backup Password',
            hint: 'Enter strong password to encrypt file',
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
        ],
        AppSpacing.gapH20,

        if (_jsonResultPath != null) ...[
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: financeColors.income,
                      size: 22,
                    ),
                    AppSpacing.gapW8,
                    Text(
                      'Backup Created Successfully!',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: financeColors.income,
                      ),
                    ),
                  ],
                ),
                AppSpacing.gapH8,
                Text(
                  _encryptBackup
                      ? 'Format: AES-256-GCM Encrypted JSON'
                      : 'Format: Plain JSON with SHA-256 Checksum',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AppSpacing.gapH4,
                Text(
                  'Saved to: $_jsonResultPath',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
                AppSpacing.gapH12,
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Copy Backup JSON',
                        variant: AppButtonVariant.outline,
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        onPressed: () {
                          if (_jsonContent != null) {
                            Clipboard.setData(
                              ClipboardData(text: _jsonContent!),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Backup JSON copied to clipboard!',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          AppSpacing.gapH16,
        ],

        AppButton(
          label: _isExportingJson
              ? 'Generating Backup...'
              : 'Generate & Save Backup',
          isLoading: _isExportingJson,
          icon: const Icon(Icons.backup_rounded, size: 20),
          onPressed: _isExportingJson ? null : _exportJson,
        ),
      ],
    );
  }
}
