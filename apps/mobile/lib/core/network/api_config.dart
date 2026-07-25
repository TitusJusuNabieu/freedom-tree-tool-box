/// Base URL for the Next.js API.
/// Production server is the default so the app works on real devices without
/// any build flags. Override with --dart-define=API_BASE_URL=... for local dev
/// (e.g. http://10.0.2.2:3000/api on Android emulator, http://localhost:3000/api on iOS sim).
String get apiBaseUrl {
  const override = String.fromEnvironment('API_BASE_URL');
  if (override.isNotEmpty) return override;
  return 'https://toolbox.freedomtree.ca/api';
}
