import 'auth_types.dart';

/// Contract for application authentication and identity management.
abstract class IAuthService {
  /// Stream emitting real-time changes to authentication state.
  Stream<AuthUserState> get authStateChanges;

  /// Current synchronous auth state.
  AuthUserState get currentAuthState;

  /// Currently authenticated user, or `null` if unauthenticated.
  AuthUser? get currentUser;

  /// Whether a user is currently signed in.
  bool get isAuthenticated;

  /// Resolves the current user asynchronously (restoring persisted session if necessary).
  Future<AuthUser?> getCurrentUser();

  /// Retrieves the current valid JWT access token for cloud API requests.
  Future<String?> getAccessToken();

  /// Registers a new user account with email and password.
  Future<AuthUser> signUp({
    required String email,
    required String password,
    String? displayName,
  });

  /// Authenticates an existing user with email and password.
  Future<AuthUser> signInWithPassword({
    required String email,
    required String password,
  });

  /// Authenticates anonymously with Supabase to obtain an auth.uid() token for cloud sync.
  Future<AuthUser> signInAnonymously();

  /// Signs out the active user and terminates the cloud session.
  Future<void> signOut();

  /// Cleans up subscriptions and resources.
  void dispose();
}
