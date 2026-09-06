import 'package:flutter/material.dart';

import '../../../domain/entities/transaction_entity.dart';
import '../screens/accounts/account_details_screen.dart';
import '../screens/accounts/accounts_screen.dart';
import '../screens/categories/categories_screen.dart';
import '../screens/goals/goals_screen.dart';
import '../screens/main_shell_screen.dart';
import '../screens/recurring/recurring_transactions_screen.dart';
import '../screens/transactions/transaction_detail_screen.dart';

/// Centralized route definitions and router configuration for Expense Tracker.
class AppRouter {
  static const String shell = '/';
  static const String accounts = '/accounts';
  static const String accountDetails = '/accounts/detail';
  static const String categories = '/categories';
  static const String transactionDetails = '/transactions/detail';
  static const String goals = '/goals';
  static const String recurring = '/recurring';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case shell:
        return MaterialPageRoute(
          builder: (_) => const MainShellScreen(),
          settings: settings,
        );

      case accounts:
        return MaterialPageRoute(
          builder: (_) => const AccountsScreen(),
          settings: settings,
        );

      case accountDetails:
        final accountId = settings.arguments as String? ?? '';
        return MaterialPageRoute(
          builder: (_) => AccountDetailsScreen(accountId: accountId),
          settings: settings,
        );

      case categories:
        return MaterialPageRoute(
          builder: (_) => const CategoriesScreen(),
          settings: settings,
        );

      case transactionDetails:
        final tx = settings.arguments as TransactionEntity;
        return MaterialPageRoute(
          builder: (_) => TransactionDetailScreen(transaction: tx),
          settings: settings,
        );

      case goals:
        return MaterialPageRoute(
          builder: (_) => const GoalsScreen(),
          settings: settings,
        );

      case recurring:
        return MaterialPageRoute(
          builder: (_) => const RecurringTransactionsScreen(),
          settings: settings,
        );

      default:
        return MaterialPageRoute(
          builder: (_) => const MainShellScreen(),
          settings: settings,
        );
    }
  }
}
