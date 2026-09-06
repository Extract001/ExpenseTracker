import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/currency_constants.dart';
import '../../../domain/entities/account_entity.dart';
import '../../providers/account_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/amount_display.dart';
import '../../widgets/app_card.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/money_text.dart';
import 'account_details_screen.dart';
import 'add_edit_account_modal.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
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

    final baseCurrency = context.select<SettingsProvider, String>(
      (s) => s.currency,
    );
    final baseSymbol = CurrencyConstants.getCurrency(baseCurrency).symbol;

    final accounts = context.watch<AccountProvider>().accounts;
    final totalNetWorth = context.select<AccountProvider, int>(
      (p) => p.totalNetWorthMinor,
    );
    final isLoading = context.select<AccountProvider, bool>((p) => p.isLoading);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add Account',
            onPressed: () => AddEditAccountModal.show(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AddEditAccountModal.show(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Account'),
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<AccountProvider>().loadAccounts(),
        child: ListView(
          padding: AppSpacing.screenPadding,
          children: [
            // Net Worth Summary Card
            AppCard(
              padding: AppSpacing.cardPadding,
              child: AmountDisplay(
                label: 'Total Net Worth',
                amountMinor: totalNetWorth,
                currencySymbol: baseSymbol,
                amountStyle: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            AppSpacing.gapH16,

            if (isLoading && accounts.isEmpty)
              const TransactionListSkeleton(itemCount: 4)
            else if (accounts.isEmpty)
              AppCard(
                child: EmptyState(
                  icon: Icons.account_balance_wallet_rounded,
                  title: 'No Accounts Yet',
                  message:
                      'Add your bank accounts, cash wallets, or credit cards to start tracking balances.',
                  actionLabel: 'Add First Account',
                  onActionPressed: () => AddEditAccountModal.show(context),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: accounts.length,
                separatorBuilder: (_, __) => AppSpacing.gapH8,
                itemBuilder: (context, index) {
                  final account = accounts[index];
                  final icon = IconData(
                    account.iconCodePoint,
                    fontFamily: 'MaterialIcons',
                  );
                  final color = Color(account.colorValue);
                  final accSymbol = CurrencyConstants.getCurrency(
                    account.currency,
                  ).symbol;

                  return AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              AccountDetailsScreen(accountId: account.id),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        CategoryIcon(
                          icon: icon,
                          color: color,
                          size: 48,
                          iconSize: 24,
                        ),
                        AppSpacing.gapW12,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                account.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              AppSpacing.gapH4,
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: AppRadius.pill,
                                ),
                                child: Text(
                                  account.type.displayName,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        AppSpacing.gapW12,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            MoneyText(
                              amountMinor: account.initialBalance,
                              currencySymbol: accSymbol,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, size: 20),
                          onSelected: (val) {
                            if (val == 'edit') {
                              AddEditAccountModal.show(
                                context,
                                accountToEdit: account,
                              );
                            } else if (val == 'delete') {
                              _confirmDelete(context, account);
                            }
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            AppSpacing.gapH40,
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, AccountEntity account) {
    showDialog<void>(
      context: context,
      builder: (ctx) => ConfirmationDialog(
        title: 'Delete Account',
        message:
            'Are you sure you want to delete "${account.name}"? Existing transactions will not be deleted.',
        confirmLabel: 'Delete',
        isDestructive: true,
        onConfirm: () async {
          await context.read<AccountProvider>().deleteAccount(account.id);
          if (ctx.mounted) {
            Navigator.of(ctx).pop();
          }
        },
      ),
    );
  }
}
