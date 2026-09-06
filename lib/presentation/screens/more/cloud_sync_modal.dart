import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../../../core/auth/auth_types.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../core/sync/i_sync_coordinator.dart';
import '../../../data/auth/auth_service.dart';
import '../../../data/database/app_database.dart';
import '../../../data/sync/supabase_sync_remote_data_source.dart';
import '../../../data/sync/sync_coordinator.dart';
import '../../providers/account_provider.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/currency_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/recurring_transaction_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extensions.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_text_field.dart';

class CloudSyncModal extends StatefulWidget {
  const CloudSyncModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CloudSyncModal(),
    );
  }

  @override
  State<CloudSyncModal> createState() => _CloudSyncModalState();
}

class _CloudSyncModalState extends State<CloudSyncModal> {
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _secureStorage = SecureStorageService();

  bool _isConfigured = false;
  bool _isSignedIn = false;
  String? _userEmail;
  bool _isLoading = false;
  bool _isSyncing = false;
  bool _showConfigForm = false;
  bool _isSignUpMode = false;
  String? _statusMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCurrentStatus();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentStatus() async {
    final savedUrl = await _secureStorage.read('saved_supabase_url') ?? '';
    final savedKey = await _secureStorage.read('saved_supabase_anon_key') ?? '';

    _urlController.text = savedUrl;
    _keyController.text = savedKey;

    bool isConfigured = false;
    bool isSignedIn = false;
    String? email;

    try {
      final client = supa.Supabase.instance.client;
      isConfigured = true;
      final user = client.auth.currentUser;
      if (user != null) {
        isSignedIn = true;
        email = user.email;
      }
    } catch (_) {
      isConfigured = savedUrl.isNotEmpty && savedKey.isNotEmpty;
    }

    if (mounted) {
      setState(() {
        _isConfigured = isConfigured;
        _isSignedIn = isSignedIn;
        _userEmail = email;
        _showConfigForm = !isConfigured;
      });
    }
  }

  Future<void> _connectSupabase() async {
    final url = _urlController.text.trim();
    final key = _keyController.text.trim();

    if (url.isEmpty || key.isEmpty) {
      setState(() {
        _errorMessage = 'Please provide both Supabase URL and Anon Public Key.';
      });
      return;
    }

    final db = context.read<AppDatabase?>() ?? AppDatabase();
    final syncProvider = context.read<SyncProvider?>();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = 'Connecting to Supabase...';
    });

    try {
      await _secureStorage.write('saved_supabase_url', url);
      await _secureStorage.write('saved_supabase_anon_key', key);

      try {
        // ignore: deprecated_member_use
        await supa.Supabase.initialize(url: url, anonKey: key);
      } catch (_) {
        // May already be initialized
      }

      final client = supa.Supabase.instance.client;
      final authService = AuthService(supabase: client);
      final remoteDataSource = SupabaseSyncRemoteDataSource(supabase: client);
      final connectivityService = ConnectivityService();

      final coordinator = SyncCoordinator(
        db: db,
        connectivityService: connectivityService,
        remoteDataSource: remoteDataSource,
        authService: authService,
        getActiveUserId: () =>
            authService.currentUser?.id ?? AppConstants.defaultUserId,
      );

      syncProvider?.updateCoordinator(coordinator);

      if (mounted) {
        setState(() {
          _isConfigured = true;
          _showConfigForm = false;
          _isLoading = false;
          _statusMessage = 'Connected to Supabase Project!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Connection failed: $e';
        });
      }
    }
  }

  Future<void> _handleAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both email and password.';
      });
      return;
    }

    final db = context.read<AppDatabase?>() ?? AppDatabase();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = _isSignUpMode ? 'Creating account...' : 'Signing in...';
    });

    try {
      final client = supa.Supabase.instance.client;
      final authService = AuthService(supabase: client);

      final AuthUser user;
      if (_isSignUpMode) {
        user = await authService.signUp(email: email, password: password);
      } else {
        user = await authService.signInWithPassword(
          email: email,
          password: password,
        );
      }

      // 1. Migrate all offline records from default_user_id to the authenticated user ID
      final remoteDataSource = SupabaseSyncRemoteDataSource(supabase: client);
      final connectivityService = ConnectivityService();
      final coordinator = SyncCoordinator(
        db: db,
        connectivityService: connectivityService,
        remoteDataSource: remoteDataSource,
        authService: authService,
        getActiveUserId: () => user.id,
      );

      await coordinator.migrateGuestData(
        guestUserId: AppConstants.defaultUserId,
        targetUserId: user.id,
      );

      // 2. Switch user in app state & reload providers
      if (mounted) {
        context.read<AppStateProvider?>()?.switchUser(user.id);
        context.read<TransactionProvider?>()?.reset(reload: true);
        context.read<AccountProvider?>()?.reset(reload: true);
        context.read<CategoryProvider?>()?.reset(reload: true);
        context.read<BudgetProvider?>()?.reset(reload: true);
        context.read<GoalProvider?>()?.reset(reload: true);
        context.read<RecurringTransactionProvider?>()?.reset(reload: true);
        context.read<SettingsProvider?>()?.reset(reload: true);
        context.read<CurrencyProvider?>()?.refreshRatesOnline();

        // 3. Immediately trigger initial synchronization
        final syncResult = await coordinator.synchronize();

        setState(() {
          _isSignedIn = true;
          _userEmail = user.email;
          _isLoading = false;
          _statusMessage =
              'Signed in! Synchronized: ${syncResult.pushedCount} pushed, ${syncResult.pulledCount} pulled.';
        });
      }
    } catch (e) {
      if (mounted) {
        String msg = e.toString().replaceFirst('Exception: ', '');
        if (msg.contains('SocketException') ||
            msg.contains('Failed host lookup') ||
            msg.contains('errno = 7')) {
          msg =
              'Network Error: Unable to reach your Supabase project. Please make sure Wi-Fi/Mobile Data is turned ON and the URL is spelled correctly.';
        } else if (msg.contains('Invalid login credentials')) {
          msg =
              'Invalid email or password. If you have not created an account yet, tap "Need an account? Create Account" below.';
        } else if (msg.contains('Email not confirmed')) {
          msg =
              'Email not confirmed. Please check your inbox or disable email confirmation in your Supabase Dashboard under Authentication -> Providers -> Email.';
        }
        setState(() {
          _isLoading = false;
          _errorMessage = msg;
        });
      }
    }
  }

  Future<void> _syncNow() async {
    setState(() {
      _isSyncing = true;
      _statusMessage = 'Synchronizing with Supabase...';
      _errorMessage = null;
    });

    try {
      final coordinator = context.read<ISyncCoordinator?>();
      if (coordinator != null) {
        final result = await coordinator.synchronize(force: true);
        if (mounted) {
          context.read<TransactionProvider?>()?.reset(reload: true);
          context.read<AccountProvider?>()?.reset(reload: true);
          context.read<CategoryProvider?>()?.reset(reload: true);
          context.read<BudgetProvider?>()?.reset(reload: true);
          context.read<GoalProvider?>()?.reset(reload: true);
          context.read<RecurringTransactionProvider?>()?.reset(reload: true);

          setState(() {
            _isSyncing = false;
            _statusMessage =
                'Sync completed: ${result.pushedCount} pushed, ${result.pulledCount} pulled.';
          });
        }
      } else {
        setState(() {
          _isSyncing = false;
          _errorMessage =
              'Sync coordinator not initialized. Please connect Supabase first.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _errorMessage = 'Sync failed: $e';
        });
      }
    }
  }

  Future<void> _signOut() async {
    try {
      final client = supa.Supabase.instance.client;
      await client.auth.signOut();
      if (mounted) {
        context.read<AppStateProvider?>()?.switchUser(
          AppConstants.defaultUserId,
        );
        setState(() {
          _isSignedIn = false;
          _userEmail = null;
          _statusMessage = 'Signed out. Switched to offline mode.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Sign out error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final financeColors = context.financeColors;
    final mediaQuery = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.88),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.12),
                        borderRadius: AppRadius.card,
                      ),
                      child: const Icon(
                        Icons.cloud_sync_rounded,
                        color: Colors.green,
                        size: 24,
                      ),
                    ),
                    AppSpacing.gapW16,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Supabase Cloud Sync',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Synchronize transactions with your cloud database',
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
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Status Card
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            _isSignedIn
                                ? Icons.cloud_done_rounded
                                : (_isConfigured
                                      ? Icons.cloud_queue_rounded
                                      : Icons.cloud_off_rounded),
                            color: _isSignedIn
                                ? financeColors.income
                                : (_isConfigured
                                      ? Colors.blue
                                      : Colors.orange),
                            size: 28,
                          ),
                          AppSpacing.gapW16,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isSignedIn
                                      ? 'Cloud Sync Active'
                                      : (_isConfigured
                                            ? 'Supabase Connected'
                                            : 'Local Offline Mode'),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  _isSignedIn
                                      ? 'Signed in as $_userEmail'
                                      : (_isConfigured
                                            ? 'Sign in below to start syncing records'
                                            : 'Configure Supabase credentials to enable sync'),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppSpacing.gapH16,

                    // Messages
                    if (_statusMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: financeColors.incomeContainer,
                          borderRadius: AppRadius.card,
                        ),
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                            color: financeColors.income,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      AppSpacing.gapH16,
                    ],

                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: financeColors.expenseContainer,
                          borderRadius: AppRadius.card,
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: financeColors.expense,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      AppSpacing.gapH16,
                    ],

                    // Section 1: Signed In State
                    if (_isSignedIn) ...[
                      AppButton(
                        label: _isSyncing ? 'Syncing...' : 'Sync Cloud Now',
                        isLoading: _isSyncing,
                        icon: const Icon(Icons.sync_rounded, size: 20),
                        onPressed: _isSyncing ? null : _syncNow,
                      ),
                      AppSpacing.gapH12,
                      AppButton(
                        label: 'Sign Out of Cloud',
                        variant: AppButtonVariant.outline,
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        onPressed: _signOut,
                      ),
                    ]
                    // Section 2: Configured but Not Signed In
                    else if (_isConfigured && !_showConfigForm) ...[
                      Text(
                        _isSignUpMode
                            ? 'Create Cloud Account'
                            : 'Sign In to Supabase',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      AppSpacing.gapH4,
                      Text(
                        'Your offline expenses will automatically migrate to your cloud account.',
                        style: theme.textTheme.bodySmall,
                      ),
                      AppSpacing.gapH12,

                      AppTextField(
                        controller: _emailController,
                        label: 'Email',
                        hint: 'you@example.com',
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: const Icon(Icons.email_outlined),
                      ),
                      AppSpacing.gapH12,

                      AppTextField(
                        controller: _passwordController,
                        label: 'Password',
                        hint: 'Minimum 6 characters',
                        obscureText: true,
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                      ),
                      AppSpacing.gapH16,

                      AppButton(
                        label: _isLoading
                            ? 'Please wait...'
                            : (_isSignUpMode ? 'Sign Up & Sync' : 'Sign In & Sync'),
                        isLoading: _isLoading,
                        onPressed: _isLoading ? null : _handleAuth,
                      ),
                      AppSpacing.gapH8,

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isSignUpMode
                                ? 'Already have an account?'
                                : 'Need an account?',
                            style: theme.textTheme.bodySmall,
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _isSignUpMode = !_isSignUpMode;
                                _errorMessage = null;
                              });
                            },
                            child: Text(
                              _isSignUpMode ? 'Sign In' : 'Create Account',
                            ),
                          ),
                        ],
                      ),
                      AppSpacing.gapH8,
                      Center(
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _showConfigForm = true;
                            });
                          },
                          icon: const Icon(Icons.settings_outlined, size: 16),
                          label: const Text('Change Supabase Project Keys'),
                        ),
                      ),
                    ]
                    // Section 3: Configuration Form
                    else ...[
                      Text(
                        'Configure Supabase Project',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      AppSpacing.gapH4,
                      Text(
                        'Found in your Supabase Dashboard under Project Settings -> API',
                        style: theme.textTheme.bodySmall,
                      ),
                      AppSpacing.gapH12,

                      AppTextField(
                        controller: _urlController,
                        label: 'Project URL',
                        hint: 'https://xyz.supabase.co',
                        keyboardType: TextInputType.url,
                        prefixIcon: const Icon(Icons.link_rounded),
                      ),
                      AppSpacing.gapH12,

                      AppTextField(
                        controller: _keyController,
                        label: 'Public Anon Key',
                        hint: 'eyJhbGciOiJIUzI1NiIsIn...',
                        maxLines: 2,
                        prefixIcon: const Icon(Icons.key_rounded),
                      ),
                      AppSpacing.gapH16,

                      AppButton(
                        label: _isLoading
                            ? 'Connecting...'
                            : 'Save & Connect Supabase',
                        isLoading: _isLoading,
                        icon: const Icon(Icons.check_circle_outline, size: 20),
                        onPressed: _isLoading ? null : _connectSupabase,
                      ),

                      if (_isConfigured) ...[
                        AppSpacing.gapH8,
                        Center(
                          child: TextButton(
                            onPressed: () {
                              setState(() {
                                _showConfigForm = false;
                              });
                            },
                            child: const Text('Back to Login'),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
