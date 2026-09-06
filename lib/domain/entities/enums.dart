enum TransactionType {
  income,
  expense,
  transfer;

  String get displayName {
    switch (this) {
      case TransactionType.income:
        return 'Income';
      case TransactionType.expense:
        return 'Expense';
      case TransactionType.transfer:
        return 'Transfer';
    }
  }
}

enum AccountType {
  cash,
  bank,
  creditCard,
  wallet,
  savings;

  String get displayName {
    switch (this) {
      case AccountType.cash:
        return 'Cash';
      case AccountType.bank:
        return 'Bank Account';
      case AccountType.creditCard:
        return 'Credit Card';
      case AccountType.wallet:
        return 'Digital Wallet';
      case AccountType.savings:
        return 'Savings Account';
    }
  }
}

enum RecurrenceFrequency {
  daily,
  weekly,
  monthly,
  yearly;

  String get displayName {
    switch (this) {
      case RecurrenceFrequency.daily:
        return 'Daily';
      case RecurrenceFrequency.weekly:
        return 'Weekly';
      case RecurrenceFrequency.monthly:
        return 'Monthly';
      case RecurrenceFrequency.yearly:
        return 'Yearly';
    }
  }
}

enum SyncStatus { synced, pendingCreate, pendingUpdate, pendingDelete, failed }

enum SyncOperationType { create, update, delete }

enum EntityType {
  transaction,
  category,
  account,
  budget,
  categoryBudget,
  goal,
  recurringRule,
}
