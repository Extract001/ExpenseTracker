import 'dart:async';
import '../../core/auth/auth_types.dart';
import '../../core/auth/i_auth_service.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';

/// In-memory implementation of [IAuthService] for headless unit and integration tests.
class FakeAuthService implements IAuthService {
  final StreamController<AuthUserState> _stateController =
      StreamController<AuthUserState>.broadcast();

  final Map<String, _FakeUserRecord> _users = {};
  AuthUser? _currentUser;
  String? _accessToken;
  bool _isDisposed = false;

  /// Optional hook to simulate network errors.
  bool simulateNetworkError = false;

  /// Optional custom error message.
  String? simulatedErrorMessage;

  FakeAuthService({AuthUser? initialUser}) {
    if (initialUser != null) {
      _currentUser = initialUser;
      _accessToken = 'fake_token_${initialUser.id}';
      _users[initialUser.email.toLowerCase()] = _FakeUserRecord(
        user: initialUser,
        password: 'Password123!',
      );
    }
  }

  @override
  Stream<AuthUserState> get authStateChanges => _stateController.stream;

  @override
  AuthUserState get currentAuthState => _currentUser != null
      ? AuthUserState.authenticated(_currentUser!)
      : const AuthUserState.unauthenticated();

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  bool get isAuthenticated => _currentUser != null;

  @override
  Future<AuthUser?> getCurrentUser() async {
    _checkDisposed();
    return _currentUser;
  }

  @override
  Future<String?> getAccessToken() async {
    _checkDisposed();
    return _accessToken;
  }

  @override
  Future<AuthUser> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    _checkDisposed();
    _stateController.add(const AuthUserState.authenticating());

    if (simulateNetworkError) {
      const err = 'Network unavailable';
      _stateController.add(const AuthUserState.error(err));
      throw const NetworkException(err);
    }

    if (simulatedErrorMessage != null) {
      final err = simulatedErrorMessage!;
      _stateController.add(AuthUserState.error(err));
      throw ValidationException(err);
    }

    final normalizedEmail = email.trim().toLowerCase();
    if (_users.containsKey(normalizedEmail)) {
      const err = 'User already registered with this email.';
      _stateController.add(const AuthUserState.error(err));
      throw const ValidationException(err);
    }

    if (password.length < 6) {
      const err = 'Password must be at least 6 characters.';
      _stateController.add(const AuthUserState.error(err));
      throw const ValidationException(err);
    }

    final userId = IdGenerator.uuid();
    final user = AuthUser(
      id: userId,
      email: email.trim(),
      displayName: displayName ?? email.split('@').first,
      createdAt: DateTime.now().toUtc(),
    );

    _users[normalizedEmail] = _FakeUserRecord(user: user, password: password);
    _currentUser = user;
    _accessToken =
        'fake_jwt_${user.id}_${DateTime.now().millisecondsSinceEpoch}';

    final authState = AuthUserState.authenticated(user);
    _stateController.add(authState);
    return user;
  }

  @override
  Future<AuthUser> signInWithPassword({
    required String email,
    required String password,
  }) async {
    _checkDisposed();
    _stateController.add(const AuthUserState.authenticating());

    if (simulateNetworkError) {
      const err = 'Network unavailable';
      _stateController.add(const AuthUserState.error(err));
      throw const NetworkException(err);
    }

    if (simulatedErrorMessage != null) {
      final err = simulatedErrorMessage!;
      _stateController.add(AuthUserState.error(err));
      throw ValidationException(err);
    }

    final normalizedEmail = email.trim().toLowerCase();
    final record = _users[normalizedEmail];

    if (record == null || record.password != password) {
      const err = 'Invalid email or password.';
      _stateController.add(const AuthUserState.error(err));
      throw const ValidationException(err);
    }

    _currentUser = record.user;
    _accessToken =
        'fake_jwt_${record.user.id}_${DateTime.now().millisecondsSinceEpoch}';

    final authState = AuthUserState.authenticated(record.user);
    _stateController.add(authState);
    return record.user;
  }

  @override
  Future<void> signOut() async {
    _checkDisposed();
    _currentUser = null;
    _accessToken = null;
    _stateController.add(const AuthUserState.unauthenticated());
  }

  /// Directly sets active session for test harness setup.
  void setSession(AuthUser? user, {String? token}) {
    _currentUser = user;
    _accessToken = token ?? (user != null ? 'fake_jwt_${user.id}' : null);
    if (user != null) {
      _users[user.email.toLowerCase()] = _FakeUserRecord(
        user: user,
        password: 'Password123!',
      );
      _stateController.add(AuthUserState.authenticated(user));
    } else {
      _stateController.add(const AuthUserState.unauthenticated());
    }
  }

  void _checkDisposed() {
    if (_isDisposed) {
      throw StateError('FakeAuthService is disposed');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _stateController.close();
  }
}

class _FakeUserRecord {
  final AuthUser user;
  final String password;

  const _FakeUserRecord({required this.user, required this.password});
}
