class DefaultCategoryItem {
  final String id;
  final String name;
  final String type; // 'income' or 'expense'
  final int iconCodePoint;
  final int colorValue;

  const DefaultCategoryItem({
    required this.id,
    required this.name,
    required this.type,
    required this.iconCodePoint,
    required this.colorValue,
  });
}

class DefaultCategories {
  static const List<DefaultCategoryItem> expenses = [
    DefaultCategoryItem(
      id: 'cat_food',
      name: 'Food & Dining',
      type: 'expense',
      iconCodePoint: 0xe532, // restaurant
      colorValue: 0xFFF97316, // Orange
    ),
    DefaultCategoryItem(
      id: 'cat_travel',
      name: 'Travel & Transport',
      type: 'expense',
      iconCodePoint: 0xe1d5, // directions_car
      colorValue: 0xFF3B82F6, // Blue
    ),
    DefaultCategoryItem(
      id: 'cat_shopping',
      name: 'Shopping',
      type: 'expense',
      iconCodePoint: 0xe59c, // shopping_bag
      colorValue: 0xFFEC4899, // Pink
    ),
    DefaultCategoryItem(
      id: 'cat_bills',
      name: 'Bills & Utilities',
      type: 'expense',
      iconCodePoint: 0xe525, // receipt_long
      colorValue: 0xFF8B5CF6, // Purple
    ),
    DefaultCategoryItem(
      id: 'cat_rent',
      name: 'Rent & Housing',
      type: 'expense',
      iconCodePoint: 0xe318, // home
      colorValue: 0xFF14B8A6, // Teal
    ),
    DefaultCategoryItem(
      id: 'cat_entertainment',
      name: 'Entertainment',
      type: 'expense',
      iconCodePoint: 0xe40f, // movie
      colorValue: 0xFFEF4444, // Red
    ),
    DefaultCategoryItem(
      id: 'cat_health',
      name: 'Health & Medical',
      type: 'expense',
      iconCodePoint: 0xe3e3, // medical_services
      colorValue: 0xFF10B981, // Emerald
    ),
    DefaultCategoryItem(
      id: 'cat_education',
      name: 'Education',
      type: 'expense',
      iconCodePoint: 0xe559, // school
      colorValue: 0xFF6366F1, // Indigo
    ),
    DefaultCategoryItem(
      id: 'cat_subscription',
      name: 'Subscriptions',
      type: 'expense',
      iconCodePoint: 0xe60a, // subscriptions
      colorValue: 0xFFA855F7, // Purple
    ),
    DefaultCategoryItem(
      id: 'cat_other_expense',
      name: 'Other Expense',
      type: 'expense',
      iconCodePoint: 0xe3d8, // more_horiz
      colorValue: 0xFF64748B, // Slate
    ),
  ];

  static const List<DefaultCategoryItem> incomes = [
    DefaultCategoryItem(
      id: 'cat_salary',
      name: 'Salary',
      type: 'income',
      iconCodePoint: 0xe040, // account_balance_wallet
      colorValue: 0xFF10B981, // Green
    ),
    DefaultCategoryItem(
      id: 'cat_freelance',
      name: 'Freelance',
      type: 'income',
      iconCodePoint: 0xe3f7, // laptop
      colorValue: 0xFF3B82F6, // Blue
    ),
    DefaultCategoryItem(
      id: 'cat_business',
      name: 'Business',
      type: 'income',
      iconCodePoint: 0xe104, // business_center
      colorValue: 0xFFF59E0B, // Amber
    ),
    DefaultCategoryItem(
      id: 'cat_investment',
      name: 'Investment',
      type: 'income',
      iconCodePoint: 0xe66c, // trending_up
      colorValue: 0xFF8B5CF6, // Purple
    ),
    DefaultCategoryItem(
      id: 'cat_gift',
      name: 'Gifts & Awards',
      type: 'income',
      iconCodePoint: 0xe1e0, // card_giftcard
      colorValue: 0xFFEC4899, // Pink
    ),
    DefaultCategoryItem(
      id: 'cat_other_income',
      name: 'Other Income',
      type: 'income',
      iconCodePoint: 0xe040, // add_circle
      colorValue: 0xFF64748B, // Slate
    ),
  ];
}
