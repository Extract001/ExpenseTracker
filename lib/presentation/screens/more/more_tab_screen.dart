import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/currency_constants.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extensions.dart';
import '../../widgets/app_card.dart';
import '../../widgets/section_header.dart';
import '../accounts/accounts_screen.dart';
import '../categories/categories_screen.dart';
import '../goals/goals_screen.dart';
import '../recurring/recurring_transactions_screen.dart';
import 'app_lock_settings_modal.dart';
import 'export_data_modal.dart';
import 'import_data_modal.dart';

class MoreTabScreen extends StatelessWidget {
  const MoreTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;

    final settingsProvider = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings & More')),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          // 1. User & Encryption Status Hero Card
          AppCard(
            padding: AppSpacing.cardPadding,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.security_rounded,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                ),
                AppSpacing.gapW16,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Encrypted Local Storage',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      AppSpacing.gapH2,
                      Text(
                        'SQLCipher 256-bit AES • Isolated Context',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: financeColors.income,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.gapH24,

          // 2. Financial Entities Management
          const SectionHeader(title: 'Financial Management'),
          AppSpacing.gapH8,
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.account_balance_wallet_rounded,
                  iconColor: Colors.blue,
                  title: 'Accounts & Wallets',
                  subtitle: 'Manage bank accounts, cash, and cards',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AccountsScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.category_rounded,
                  iconColor: Colors.orange,
                  title: 'Categories',
                  subtitle: 'Custom income & expense categories',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CategoriesScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.savings_rounded,
                  iconColor: Colors.green,
                  title: 'Savings Goals',
                  subtitle: 'Track your personal saving targets',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const GoalsScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.repeat_rounded,
                  iconColor: Colors.purple,
                  title: 'Recurring Rules',
                  subtitle: 'Automated recurring transactions',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RecurringTransactionsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          AppSpacing.gapH24,

          // 3. Preferences & Appearance
          const SectionHeader(title: 'Preferences'),
          AppSpacing.gapH8,
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                // Theme Mode Selector
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: financeColors.surfaceVariant,
                          borderRadius: AppRadius.card,
                        ),
                        child: const Icon(Icons.palette_rounded, size: 20),
                      ),
                      AppSpacing.gapW16,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Appearance',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Choose theme preference',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      DropdownButton<ThemeMode>(
                        value: settingsProvider.themeMode,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(
                            value: ThemeMode.system,
                            child: Text('System'),
                          ),
                          DropdownMenuItem(
                            value: ThemeMode.light,
                            child: Text('Light'),
                          ),
                          DropdownMenuItem(
                            value: ThemeMode.dark,
                            child: Text('Dark'),
                          ),
                        ],
                        onChanged: (mode) {
                          if (mode != null) {
                            settingsProvider.setThemeMode(mode);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Currency Selector
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: financeColors.surfaceVariant,
                          borderRadius: AppRadius.card,
                        ),
                        child: const Icon(
                          Icons.currency_rupee_rounded,
                          size: 20,
                        ),
                      ),
                      AppSpacing.gapW16,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Base Currency',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Default financial denomination',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      DropdownButton<String>(
                        value:
                            CurrencyConstants.supportedCurrencies.any(
                              (c) => c.code == settingsProvider.currency,
                            )
                            ? settingsProvider.currency
                            : CurrencyConstants.defaultCurrencyCode,
                        underline: const SizedBox.shrink(),
                        items: CurrencyConstants.supportedCurrencies
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.code,
                                child: Text('${c.code} (${c.symbol})'),
                              ),
                            )
                            .toList(),
                        onChanged: (code) {
                          if (code != null) {
                            settingsProvider.setCurrency(code);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.gapH24,

          // 4. Data & Backups (CSV / JSON)
          const SectionHeader(title: 'Data & Backups'),
          AppSpacing.gapH8,
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.file_download_outlined,
                  iconColor: Colors.teal,
                  title: 'Export Data (CSV / JSON)',
                  subtitle: 'Export transactions for spreadsheets or backups',
                  onTap: () => ExportDataModal.show(context),
                ),
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.file_upload_outlined,
                  iconColor: Colors.indigo,
                  title: 'Import Data',
                  subtitle: 'Restore financial records from local file',
                  onTap: () => ImportDataModal.show(context),
                ),
              ],
            ),
          ),
          AppSpacing.gapH24,

          // 5. Security & App Lock
          const SectionHeader(title: 'Security'),
          AppSpacing.gapH8,
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.fingerprint_rounded,
                  iconColor: Colors.deepPurple,
                  title: 'Biometric & PIN Lock',
                  subtitle: 'Hardware-backed app lock security',
                  onTap: () => AppLockSettingsModal.show(context),
                ),
              ],
            ),
          ),
          AppSpacing.gapH32,

          // App Footer Info
          Center(
            child: Column(
              children: [
                Text(
                  'Expense Manager v1.0.0',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AppSpacing.gapH4,
                Text(
                  'Offline-First • Encrypted Drift Database',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.gapH32,
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: AppRadius.card,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            AppSpacing.gapW16,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: financeColors.cardBorder),
          ],
        ),
      ),
    );
  }
}
