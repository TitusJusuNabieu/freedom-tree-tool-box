import 'package:flutter/foundation.dart';
import 'package:freedomtree_mobile/features/auth/auth_models.dart';
import 'package:freedomtree_mobile/features/auth/auth_repository.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Drives go_router's redirect logic via [ChangeNotifier] — when the API
/// client's interceptor calls [signOut] after a failed refresh, the router
/// reacts and sends the user back to /login.
class AuthController extends ChangeNotifier {
  AuthController(this._repository) {
    _restore();
  }

  final AuthRepository _repository;

  AuthStatus status = AuthStatus.unknown;
  CurrentUser? currentUser;

  Future<void> _restore() async {
    final hasToken = await _repository.isLoggedIn;
    if (!hasToken) {
      status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    // Restore from disk immediately — no network needed, works offline.
    final cached = await _repository.cachedUser;
    if (cached != null) {
      currentUser = cached;
      status = AuthStatus.authenticated;
      notifyListeners();

      // Refresh profile from server in the background. If offline this fails
      // silently — the cached profile is still used.
      _repository.fetchCurrentUser().then((fresh) {
        if (fresh != null) {
          currentUser = fresh;
          notifyListeners();
        }
      }).catchError((_) {});
      return;
    }

    // Token exists but no cached profile (e.g. first install after a wipe).
    // Must go online to get the user.
    final fresh = await _repository.fetchCurrentUser();
    currentUser = fresh;
    status = fresh != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final user = await _repository.login(username, password);
    currentUser = user;
    status = AuthStatus.authenticated;
    notifyListeners();
  }

  Future<void> signOut() async {
    await _repository.logout();
    currentUser = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void updateUser(CurrentUser user) {
    currentUser = user;
    notifyListeners();
  }
}
