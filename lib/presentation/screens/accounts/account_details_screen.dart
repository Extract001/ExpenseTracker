import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/date_time_utils.dart';
import '../../../domain/entities/account_entity.dart';
import '../../providers/account_provider.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/amount_display.dart';
import '../../widgets/app_card.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/money_text.dart';
import 'add_edit_account_modal.dart';

class AccountDetailsScreen extends StatefulWidget {
  final String accountId;

  const AccountDetailsScreen({super.key, required this.accountId});

  @override
  State<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AccountProvider>().watchAccounts();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final account = context.select<AccountProvider, AccountEntity?>(
      (p) => p.getAccountById(widget.accountId),
    );

    if (account == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Account Details')),
        body: const Center(child: Text('Account not found')),
      );
    }

    final accountIcon = IconData(
      account.iconCodePoint,
      fontFamily: 'MaterialIcons',
    );
    final accountColor = Color(account.colorValue);

    return Scaffold(
      appBar: AppBar(
        title: Text(account.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Edit Account',
            onPressed: () =>
                AddEditAccountModal.show(context, accountToEdit: account),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Delete Account',
            onPressed: () => _confirmDelete(context, account),
          ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          // Header Card with Icon & Type
          AppCard(
            padding: AppSpacing.cardPadding,
            child: Column(
              children: [
                CategoryIcon(
                  icon: accountIcon,
                  color: accountColor,
                  size: 64,
                  iconSize: 32,
                ),
                AppSpacing.gapH12,
                Text(
                  account.name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                AppSpacing.gapH4,
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accountColor.withValues(alpha: 0.15),
                    borderRadius: AppRadius.pill,
                  ),
                  child: Text(
                    account.type.displayName,
                    style: TextStyle(
                      color: accountColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                AppSpacing.gapH24,
                AmountDisplay(
                  label: 'Account Balance',
                  amountMinor: account.initialBalance,
                  amountStyle: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.gapH16,

          // Account Metadata Details Card
          AppCard(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account Information',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                AppSpacing.gapH16,
                _DetailRow(
                  label: 'Account Type',
                  value: account.type.displayName,
                ),
                const Divider(),
                _DetailRow(
                  label: 'Initial Balance',
                  customValue: MoneyText(
                    amountMinor: account.initialBalance,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Divider(),
                _DetailRow(label: 'Currency', value: account.currency),
                const Divider(),
                _DetailRow(
                  label: 'Created Date',
                  value: DateTimeUtils.formatDate(account.createdAt),
                ),
                const Divider(),
                _DetailRow(
                  label: 'Last Updated',
                  value: DateTimeUtils.formatDate(account.updatedAt),
                ),
                const Divider(),
                _DetailRow(
                  label: 'Sync Status',
                  value: account.syncStatus.name.toUpperCase(),
                ),
              ],
            ),
          ),
          AppSpacing.gapH24,
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, AccountEntity account) {
    showDialog<void>(
      context: context,
      builder: (ctx) => ConfirmationDialog(
        title: 'Delete Account',
        message:
            'Are you sure you want to delete "${account.name}"? Existing transactions referencing this account will be preserved.',
        confirmLabel: 'Delete',
        isDestructive: true,
        onConfirm: () async {
          final nav = Navigator.of(context);
          await context.read<AccountProvider>().deleteAccount(account.id);
          nav.pop(); // Pop dialog
          nav.pop(); // Pop details screen back to list
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? customValue;

  const _DetailRow({required this.label, this.value, this.customValue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color,
            ),
          ),
          if (customValue != null)
            customValue!
          else if (value != null)
            Text(
              value!,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
