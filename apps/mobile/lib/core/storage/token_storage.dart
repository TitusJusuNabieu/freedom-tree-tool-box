import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps flutter_secure_storage (Keychain on iOS, EncryptedSharedPreferences
/// on Android) for the access/refresh token pair and user profile cache.
/// The user profile cache is what makes offline startup possible — the app
/// restores the session from disk without a network round-trip.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'ft_access_token';
  static const _refreshTokenKey = 'ft_refresh_token';
  static const _userJsonKey = 'ft_user_json';

  Future<void> save({required String accessToken, required String refreshToken}) async {
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: accessToken),
      _storage.write(key: _refreshTokenKey, value: refreshToken),
    ]);
  }

  Future<void> saveAccessToken(String accessToken) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
  }

  Future<void> saveUserJson(String json) => _storage.write(key: _userJsonKey, value: json);
  Future<String?> get cachedUserJson => _storage.read(key: _userJsonKey);

  Future<String?> get accessToken => _storage.read(key: _accessTokenKey);
  Future<String?> get refreshToken => _storage.read(key: _refreshTokenKey);

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _userJsonKey),
    ]);
  }
}
