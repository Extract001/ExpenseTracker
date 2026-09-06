import 'package:expense_tracker/core/auth/auth_types.dart';
import 'package:expense_tracker/core/errors/app_exception.dart';
import 'package:expense_tracker/data/auth/fake_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthService & FakeAuthService Tests', () {
    late FakeAuthService authService;

    setUp(() {
      authService = FakeAuthService();
    });

    tearDown(() {
      authService.dispose();
    });

    test('Initial state is unauthenticated', () async {
      expect(authService.isAuthenticated, isFalse);
      expect(authService.currentUser, isNull);
      expect(authService.currentAuthState.status, AuthStatus.unauthenticated);
      expect(await authService.getCurrentUser(), isNull);
      expect(await authService.getAccessToken(), isNull);
    });

    test(
      'Sign up creates new user, sets token, and emits authenticated state',
      () async {
        final states = <AuthUserState>[];
        final sub = authService.authStateChanges.listen(states.add);

        final user = await authService.signUp(
          email: 'user@example.com',
          password: 'Password123!',
          displayName: 'John Doe',
        );

        expect(user.id, isNotEmpty);
        expect(user.email, 'user@example.com');
        expect(user.displayName, 'John Doe');
        expect(authService.isAuthenticated, isTrue);
        expect(authService.currentUser, equals(user));
        expect(await authService.getAccessToken(), isNotNull);

        await pumpEventQueue();
        expect(
          states.any((s) => s.status == AuthStatus.authenticating),
          isTrue,
        );
        expect(
          states.any(
            (s) => s.status == AuthStatus.authenticated && s.user == user,
          ),
          isTrue,
        );

        await sub.cancel();
      },
    );

    test('Sign up with existing email throws ValidationException', () async {
      await authService.signUp(
        email: 'existing@example.com',
        password: 'Password123!',
      );

      expect(
        () => authService.signUp(
          email: 'existing@example.com',
          password: 'AnotherPassword123!',
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('Sign in with valid credentials restores user session', () async {
      await authService.signUp(
        email: 'signin@example.com',
        password: 'SecretPassword123!',
        displayName: 'Alice',
      );
      await authService.signOut();
      expect(authService.isAuthenticated, isFalse);

      final signedInUser = await authService.signInWithPassword(
        email: 'signin@example.com',
        password: 'SecretPassword123!',
      );

      expect(signedInUser.email, 'signin@example.com');
      expect(signedInUser.displayName, 'Alice');
      expect(authService.isAuthenticated, isTrue);
    });

    test('Sign in with invalid password throws ValidationException', () async {
      await authService.signUp(
        email: 'wrongpass@example.com',
        password: 'CorrectPassword123!',
      );
      await authService.signOut();

      expect(
        () => authService.signInWithPassword(
          email: 'wrongpass@example.com',
          password: 'WrongPassword123!',
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('Sign out clears active session and emits unauthenticated', () async {
      await authService.signUp(
        email: 'logout@example.com',
        password: 'Password123!',
      );
      expect(authService.isAuthenticated, isTrue);

      await authService.signOut();
      expect(authService.isAuthenticated, isFalse);
      expect(authService.currentUser, isNull);
      expect(await authService.getAccessToken(), isNull);
    });

    test('Network failure simulation throws NetworkException', () async {
      authService.simulateNetworkError = true;

      expect(
        () => authService.signUp(
          email: 'net@example.com',
          password: 'Password123!',
        ),
        throwsA(isA<NetworkException>()),
      );
    });

    test('AuthUser equality and hashing', () {
      final u1 = AuthUser(id: 'u1', email: 'test@example.com');
      final u2 = AuthUser(id: 'u1', email: 'test@example.com');
      final u3 = AuthUser(id: 'u2', email: 'other@example.com');

      expect(u1, equals(u2));
      expect(u1.hashCode, equals(u2.hashCode));
      expect(u1, isNot(equals(u3)));
    });

    test('AuthSession expiry check', () {
      final user = AuthUser(id: 'u1', email: 'test@example.com');
      final activeSession = AuthSession(
        accessToken: 'tok1',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        user: user,
      );
      final expiredSession = AuthSession(
        accessToken: 'tok2',
        expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
        user: user,
      );

      expect(activeSession.isExpired, isFalse);
      expect(expiredSession.isExpired, isTrue);
    });
  });
}
