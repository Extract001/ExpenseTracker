import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/app_lock_service.dart';
import '../../core/security/secure_storage_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  String _enteredPin = '';
  String? _errorMessage;
  bool _isAuthenticatingBiometrics = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPromptBiometrics();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final appLockService = context.read<AppLockService?>();
    if (appLockService == null) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      appLockService.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      appLockService.onAppResumed();
      if (appLockService.isLocked) {
        _checkAndPromptBiometrics();
      }
    }
  }

  Future<void> _checkAndPromptBiometrics() async {
    final appLockService = context.read<AppLockService?>();
    if (appLockService == null || !appLockService.isLocked) return;

    final secureStorage = SecureStorageService();
    final isBiometricsEnabled = await secureStorage.isBiometricsEnabled();
    if (!isBiometricsEnabled) return;

    if (_isAuthenticatingBiometrics) return;
    _isAuthenticatingBiometrics = true;

    try {
      final unlocked = await appLockService.unlockWithBiometrics();
      if (unlocked && mounted) {
        setState(() {
          _enteredPin = '';
          _errorMessage = null;
        });
      }
    } catch (_) {
      // Fall back silently to PIN pad
    } finally {
      _isAuthenticatingBiometrics = false;
    }
  }

  void _onDigitPressed(String digit) async {
    if (_enteredPin.length >= 6) return;

    final newPin = '$_enteredPin$digit';
    setState(() {
      _enteredPin = newPin;
      _errorMessage = null;
    });

    if (newPin.length >= 4) {
      final appLockService = context.read<AppLockService?>();
      if (appLockService != null) {
        try {
          final success = await appLockService.unlockWithPin(newPin);
          if (success) {
            setState(() {
              _enteredPin = '';
              _errorMessage = null;
            });
          } else {
            setState(() {
              _enteredPin = '';
              _errorMessage = 'Incorrect PIN. Try again.';
            });
          }
        } catch (e) {
          setState(() {
            _enteredPin = '';
            _errorMessage = e.toString().replaceFirst('Exception: ', '');
          });
        }
      }
    }
  }

  void _onBackspacePressed() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _errorMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLockService = context.watch<AppLockService?>();
    final isLocked = appLockService?.isLocked ?? false;

    if (!isLocked) {
      return widget.child;
    }

    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Lock Icon
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_rounded,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
              ),
              AppSpacing.gapH24,

              Text(
                'Expense Tracker Locked',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              AppSpacing.gapH8,
              Text(
                'Enter your PIN to access financial records',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
              AppSpacing.gapH32,

              // PIN Indicators
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final isFilled = index < _enteredPin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled
                          ? theme.colorScheme.primary
                          : theme.colorScheme.primary.withValues(alpha: 0.18),
                      border: Border.all(
                        color: theme.colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                  );
                }),
              ),
              AppSpacing.gapH16,

              // Error Message
              if (_errorMessage != null)
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),

              const Spacer(flex: 3),

              // Keypad
              _buildKeypad(theme),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad(ThemeData theme) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildKeypadButton('1', theme),
            _buildKeypadButton('2', theme),
            _buildKeypadButton('3', theme),
          ],
        ),
        AppSpacing.gapH16,
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildKeypadButton('4', theme),
            _buildKeypadButton('5', theme),
            _buildKeypadButton('6', theme),
          ],
        ),
        AppSpacing.gapH16,
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildKeypadButton('7', theme),
            _buildKeypadButton('8', theme),
            _buildKeypadButton('9', theme),
          ],
        ),
        AppSpacing.gapH16,
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Biometric button
            IconButton(
              iconSize: 32,
              icon: const Icon(Icons.fingerprint_rounded),
              color: theme.colorScheme.primary,
              onPressed: _checkAndPromptBiometrics,
            ),
            _buildKeypadButton('0', theme),
            // Backspace button
            IconButton(
              iconSize: 28,
              icon: const Icon(Icons.backspace_outlined),
              color: AppColors.disabled,
              onPressed: _onBackspacePressed,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeypadButton(String digit, ThemeData theme) {
    return InkWell(
      onTap: () => _onDigitPressed(digit),
      borderRadius: AppRadius.pill,
      child: Container(
        width: 68,
        height: 68,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
        ),
        child: Text(
          digit,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
