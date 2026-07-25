import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:freedomtree_mobile/core/storage/token_storage.dart';
import 'package:freedomtree_mobile/features/auth/auth_models.dart';

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Handles login/logout against the mobile JWT endpoints (/api/auth/login etc.)
/// The user profile is cached to disk after login so the app can restore the
/// session without a network round-trip — enabling fully offline operation
/// after the first successful sign-in.
class AuthRepository {
  AuthRepository({required Dio dio, required TokenStorage tokenStorage})
      : _dio = dio,
        _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  Future<CurrentUser> login(String username, String password) async {
    try {
      final response = await _dio.post('/auth/login', data: {
        'username': username,
        'password': password,
      });
      await _tokenStorage.save(
        accessToken: response.data['accessToken'] as String,
        refreshToken: response.data['refreshToken'] as String,
      );
      final userJson = response.data['user'] as Map<String, dynamic>;
      // Cache profile so future startups work offline.
      await _tokenStorage.saveUserJson(jsonEncode(userJson));
      return CurrentUser.fromJson(userJson);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw AuthException('Invalid username or password.');
      }
      throw AuthException('Could not reach the server. Check your connection and try again.');
    }
  }

  Future<void> logout() async {
    final refreshToken = await _tokenStorage.refreshToken;
    if (refreshToken != null) {
      try {
        await _dio.post('/auth/logout', data: {'refreshToken': refreshToken});
      } catch (_) {
        // best-effort server-side revoke; clear local tokens regardless
      }
    }
    await _tokenStorage.clear();
  }

  /// Returns the cached user profile saved to disk — never makes a network call.
  /// Returns null only if the user has never logged in on this device.
  Future<CurrentUser?> get cachedUser async {
    final raw = await _tokenStorage.cachedUserJson;
    if (raw == null) return null;
    try {
      return CurrentUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Fetches fresh profile from server and updates the local cache.
  /// Returns null silently on any network error — callers should not
  /// block the user flow on this result.
  Future<CurrentUser?> fetchCurrentUser() async {
    final token = await _tokenStorage.accessToken;
    if (token == null) return null;
    try {
      final response = await _dio.get('/auth/me');
      final userJson = response.data as Map<String, dynamic>;
      await _tokenStorage.saveUserJson(jsonEncode(userJson));
      return CurrentUser.fromJson(userJson);
    } catch (_) {
      return null;
    }
  }

  Future<bool> get isLoggedIn async => (await _tokenStorage.accessToken) != null;
}
