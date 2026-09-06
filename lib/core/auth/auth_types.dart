/// Represents an authenticated user identity.
class AuthUser {
  final String id;
  final String email;
  final String? displayName;
  final DateTime? createdAt;

  const AuthUser({
    required this.id,
    required this.email,
    this.displayName,
    this.createdAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          email == other.email;

  @override
  int get hashCode => id.hashCode ^ email.hashCode;

  @override
  String toString() =>
      'AuthUser(id: $id, email: $email, displayName: $displayName)';
}

/// Represents an active auth session with tokens.
class AuthSession {
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final AuthUser user;

  const AuthSession({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    required this.user,
  });

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().toUtc().isAfter(expiresAt!);
  }
}

/// Status of the auth state.
enum AuthStatus { unauthenticated, authenticating, authenticated, error }

/// Auth state container.
class AuthUserState {
  final AuthStatus status;
  final AuthUser? user;
  final String? errorMessage;

  const AuthUserState({required this.status, this.user, this.errorMessage});

  const AuthUserState.unauthenticated()
    : status = AuthStatus.unauthenticated,
      user = null,
      errorMessage = null;

  const AuthUserState.authenticating()
    : status = AuthStatus.authenticating,
      user = null,
      errorMessage = null;

  const AuthUserState.authenticated(this.user)
    : status = AuthStatus.authenticated,
      errorMessage = null;

  const AuthUserState.error(String message)
    : status = AuthStatus.error,
      user = null,
      errorMessage = message;

  bool get isAuthenticated =>
      status == AuthStatus.authenticated && user != null;
}
