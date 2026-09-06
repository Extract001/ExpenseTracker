import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import '../../core/auth/auth_types.dart';
import '../../core/auth/i_auth_service.dart';
import '../../core/errors/app_exception.dart';

/// Production implementation of [IAuthService] using Supabase GoTrue authentication.
///
/// Operates strictly with the public `anon` key. User authorization is derived
/// automatically from `auth.uid()` and verified server-side via Row-Level Security.
class AuthService implements IAuthService {
  final supa.SupabaseClient _supabase;
  final StreamController<AuthUserState> _stateController =
      StreamController<AuthUserState>.broadcast();

  StreamSubscription<supa.AuthState>? _authSub;
  bool _isDisposed = false;

  AuthService({required supa.SupabaseClient supabase}) : _supabase = supabase {
    _init();
  }

  void _init() {
    // Listen to Supabase auth state transitions
    _authSub = _supabase.auth.onAuthStateChange.listen((data) {
      if (_isDisposed) return;
      final user = data.session?.user;
      if (user != null) {
        _stateController.add(AuthUserState.authenticated(_mapUser(user)));
      } else {
        _stateController.add(const AuthUserState.unauthenticated());
      }
    });
  }

  @override
  Stream<AuthUserState> get authStateChanges => _stateController.stream;

  @override
  AuthUserState get currentAuthState {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      return AuthUserState.authenticated(_mapUser(user));
    }
    return const AuthUserState.unauthenticated();
  }

  @override
  AuthUser? get currentUser {
    final user = _supabase.auth.currentUser;
    return user != null ? _mapUser(user) : null;
  }

  @override
  bool get isAuthenticated => _supabase.auth.currentUser != null;

  @override
  Future<AuthUser?> getCurrentUser() async {
    final user = _supabase.auth.currentUser;
    return user != null ? _mapUser(user) : null;
  }

  @override
  Future<String?> getAccessToken() async {
    return _supabase.auth.currentSession?.accessToken;
  }

  @override
  Future<AuthUser> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    _stateController.add(const AuthUserState.authenticating());
    try {
      final response = await _supabase.auth.signUp(
        email: email.trim(),
        password: password,
        data: displayName != null ? {'display_name': displayName} : null,
      );

      final user = response.user;
      if (user == null) {
        throw const AuthFailureException('Sign up failed: User record is null');
      }

      final authUser = _mapUser(user, fallbackDisplayName: displayName);
      _stateController.add(AuthUserState.authenticated(authUser));
      return authUser;
    } on supa.AuthException catch (e) {
      final message = e.message;
      _stateController.add(AuthUserState.error(message));
      throw AuthFailureException(message, details: e);
    } catch (e) {
      _stateController.add(AuthUserState.error(e.toString()));
      throw AuthFailureException('Sign up failed: $e', details: e);
    }
  }

  @override
  Future<AuthUser> signInWithPassword({
    required String email,
    required String password,
  }) async {
    _stateController.add(const AuthUserState.authenticating());
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      final user = response.user;
      if (user == null) {
        throw const AuthFailureException('Sign in failed: User record is null');
      }

      final authUser = _mapUser(user);
      _stateController.add(AuthUserState.authenticated(authUser));
      return authUser;
    } on supa.AuthException catch (e) {
      final message = e.message;
      _stateController.add(AuthUserState.error(message));
      throw AuthFailureException(message, details: e);
    } catch (e) {
      _stateController.add(AuthUserState.error(e.toString()));
      throw AuthFailureException('Sign in failed: $e', details: e);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
      _stateController.add(const AuthUserState.unauthenticated());
    } on supa.AuthException catch (e) {
      throw AuthFailureException(e.message, details: e);
    } catch (e) {
      throw AuthFailureException('Sign out failed: $e', details: e);
    }
  }

  AuthUser _mapUser(supa.User user, {String? fallbackDisplayName}) {
    final meta = user.userMetadata;
    final displayName = meta?['display_name'] as String? ?? fallbackDisplayName;
    return AuthUser(
      id: user.id,
      email: user.email ?? '',
      displayName: displayName,
      createdAt: DateTime.tryParse(user.createdAt)?.toUtc(),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _authSub?.cancel();
    _authSub = null;
    _stateController.close();
  }
}
