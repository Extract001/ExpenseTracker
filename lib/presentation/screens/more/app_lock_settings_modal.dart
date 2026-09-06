import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../../../core/security/app_lock_service.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extensions.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_text_field.dart';

class AppLockSettingsModal extends StatefulWidget {
  const AppLockSettingsModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AppLockSettingsModal(),
    );
  }

  @override
  State<AppLockSettingsModal> createState() => _AppLockSettingsModalState();
}

class _AppLockSettingsModalState extends State<AppLockSettingsModal> {
  bool _isLoading = true;
  bool _hasPin = false;
  bool _biometricsEnabled = false;
  bool _canCheckBiometrics = false;
  AppLockTimeout _selectedTimeout = AppLockTimeout.immediate;

  final _secureStorage = SecureStorageService();
  final _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final appLockService = context.read<AppLockService?>();
    final hasPin = await _secureStorage.hasAppPin();
    final biometricsEnabled = await _secureStorage.isBiometricsEnabled();

    bool canCheck = false;
    try {
      final isSupported = await _localAuth.isDeviceSupported();
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      canCheck = isSupported && canCheckBiometrics;
    } catch (_) {
      canCheck = false;
    }

    final timeout = appLockService?.lockTimeout ?? AppLockTimeout.immediate;

    if (mounted) {
      setState(() {
        _hasPin = hasPin;
        _biometricsEnabled = biometricsEnabled;
        _canCheckBiometrics = canCheck;
        _selectedTimeout = timeout;
        _isLoading = false;
      });
    }
  }

  Future<void> _setupPinDialog() async {
    final appLockService = context.read<AppLockService?>();
    final pinController = TextEditingController();
    final confirmPinController = TextEditingController();
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Set App Lock PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter a 4-to-6 digit PIN to secure your financial data.',
              ),
              AppSpacing.gapH16,
              AppTextField(
                controller: pinController,
                label: 'New PIN',
                hint: '4-6 digits',
                keyboardType: TextInputType.number,
                obscureText: true,
                prefixIcon: const Icon(Icons.pin_rounded),
              ),
              AppSpacing.gapH12,
              AppTextField(
                controller: confirmPinController,
                label: 'Confirm PIN',
                hint: 'Re-enter PIN',
                keyboardType: TextInputType.number,
                obscureText: true,
                prefixIcon: const Icon(Icons.check_rounded),
              ),
              if (dialogError != null) ...[
                AppSpacing.gapH8,
                Text(
                  dialogError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final pin = pinController.text.trim();
                final confirm = confirmPinController.text.trim();

                if (pin.length < 4 || pin.length > 6) {
                  setDialogState(() {
                    dialogError = 'PIN must be between 4 and 6 digits.';
                  });
                  return;
                }
                if (pin != confirm) {
                  setDialogState(() {
                    dialogError = 'PINs do not match.';
                  });
                  return;
                }

                await _secureStorage.setAppPin(pin);
                await appLockService?.initialize();

                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
                _loadState();
              },
              child: const Text('Save PIN'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _disablePinDialog() async {
    final appLockService = context.read<AppLockService?>();
    final pinController = TextEditingController();
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Disable App Lock'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter your current PIN to turn off App Lock.'),
              AppSpacing.gapH16,
              AppTextField(
                controller: pinController,
                label: 'Current PIN',
                keyboardType: TextInputType.number,
                obscureText: true,
                prefixIcon: const Icon(Icons.lock_open_rounded),
              ),
              if (dialogError != null) ...[
                AppSpacing.gapH8,
                Text(
                  dialogError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final pin = pinController.text.trim();
                final isValid = await _secureStorage.verifyAppPin(pin);
                if (!isValid) {
                  setDialogState(() {
                    dialogError = 'Incorrect PIN.';
                  });
                  return;
                }

                await _secureStorage.clearAppPin();
                await _secureStorage.setBiometricsEnabled(false);
                appLockService?.wipeSession();

                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
                _loadState();
              },
              child: const Text('Disable Lock'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testBiometrics() async {
    try {
      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Test Biometric Unlock for Expense Tracker',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              didAuth
                  ? 'Biometric verification successful!'
                  : 'Biometric verification failed or canceled.',
            ),
            backgroundColor: didAuth ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Biometric authentication error: $e'),
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
                      color: Colors.deepPurple.withValues(alpha: 0.12),
                      borderRadius: AppRadius.card,
                    ),
                    child: const Icon(
                      Icons.fingerprint_rounded,
                      color: Colors.deepPurple,
                      size: 24,
                    ),
                  ),
                  AppSpacing.gapW16,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Biometric & PIN Lock',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Secure app with hardware biometrics and PBKDF2 PIN',
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
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        // Status Card
                        AppCard(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                _hasPin
                                    ? Icons.lock_rounded
                                    : Icons.lock_open_rounded,
                                color: _hasPin
                                    ? financeColors.income
                                    : Colors.orange,
                                size: 28,
                              ),
                              AppSpacing.gapW16,
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _hasPin
                                          ? 'App Lock Active'
                                          : 'App Lock Not Configured',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    Text(
                                      _hasPin
                                          ? 'Protected with encrypted PIN hash'
                                          : 'Set a PIN to enable biometric and auto-lock protection',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        AppSpacing.gapH20,

                        // PIN Actions
                        if (!_hasPin) ...[
                          AppButton(
                            label: 'Set Up Security PIN',
                            icon: const Icon(Icons.pin_rounded, size: 20),
                            onPressed: _setupPinDialog,
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: AppButton(
                                  label: 'Change PIN',
                                  variant: AppButtonVariant.outline,
                                  icon: const Icon(
                                    Icons.edit_rounded,
                                    size: 18,
                                  ),
                                  onPressed: _setupPinDialog,
                                ),
                              ),
                              AppSpacing.gapW12,
                              Expanded(
                                child: AppButton(
                                  label: 'Disable Lock',
                                  variant: AppButtonVariant.destructive,
                                  icon: const Icon(
                                    Icons.lock_open_rounded,
                                    size: 18,
                                  ),
                                  onPressed: _disablePinDialog,
                                ),
                              ),
                            ],
                          ),
                          AppSpacing.gapH20,

                          // Biometrics Switch
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            secondary: const Icon(Icons.fingerprint_rounded),
                            title: const Text('Biometric Authentication'),
                            subtitle: Text(
                              _canCheckBiometrics
                                  ? 'Unlock using device Fingerprint or Face recognition'
                                  : 'Biometrics not available on this device',
                            ),
                            value: _biometricsEnabled,
                            onChanged: _canCheckBiometrics
                                ? (val) async {
                                    await _secureStorage.setBiometricsEnabled(
                                      val,
                                    );
                                    setState(() {
                                      _biometricsEnabled = val;
                                    });
                                  }
                                : null,
                          ),
                          AppSpacing.gapH12,

                          // Auto Lock Timeout Dropdown
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.timer_outlined),
                            title: const Text('Auto-Lock Timeout'),
                            subtitle: const Text(
                              'Require authentication after app goes to background',
                            ),
                            trailing: DropdownButton<AppLockTimeout>(
                              value: _selectedTimeout,
                              underline: const SizedBox.shrink(),
                              items: AppLockTimeout.values
                                  .map(
                                    (t) => DropdownMenuItem(
                                      value: t,
                                      child: Text(t.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (newTimeout) {
                                if (newTimeout != null) {
                                  context
                                      .read<AppLockService?>()
                                      ?.setLockTimeout(newTimeout);
                                  setState(() {
                                    _selectedTimeout = newTimeout;
                                  });
                                }
                              },
                            ),
                          ),
                          AppSpacing.gapH16,

                          if (_canCheckBiometrics && _biometricsEnabled) ...[
                            AppButton(
                              label: 'Test Biometric Sensor',
                              variant: AppButtonVariant.secondary,
                              icon: const Icon(
                                Icons.verified_user_rounded,
                                size: 18,
                              ),
                              onPressed: _testBiometrics,
                            ),
                          ],
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
