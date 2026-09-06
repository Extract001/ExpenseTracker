class Validators {
  static String? validateAmount(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter an amount';
    }
    final cleaned = value.replaceAll(',', '').trim();
    final parsed = double.tryParse(cleaned);
    if (parsed == null || parsed <= 0) {
      return 'Amount must be greater than 0';
    }
    return null;
  }

  static String? validateNonEmpty(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return ' cannot be empty';
    }
    return null;
  }

  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  static String? validatePin(String? value, {int requiredLength = 4}) {
    if (value == null || value.trim().isEmpty) {
      return 'PIN is required';
    }
    if (value.length != requiredLength || int.tryParse(value) == null) {
      return 'PIN must be exactly  digits';
    }
    return null;
  }
}
