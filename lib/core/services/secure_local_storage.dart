import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [LocalStorage] backed by `flutter_secure_storage` (Keychain on
/// iOS/macOS, Keystore-backed EncryptedSharedPreferences on Android)
/// instead of supabase_flutter's own default, which persists the
/// session/refresh token in plain SharedPreferences.
///
/// `flutter_secure_storage` was already a declared pubspec dependency
/// — added, per its own comment, for exactly this purpose — but was
/// never actually wired into `Supabase.initialize()`, so every session
/// was sitting in plaintext regardless. See
/// SupabaseService.initialize() for where this gets used, and why it's
/// only used on the platforms where secure storage is reliable without
/// extra native setup.
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage() : super();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // supabase_flutter's own SharedPreferencesLocalStorage uses this
  // same key name — keeping it identical means a user upgrading from
  // the old plaintext storage to this one doesn't get silently signed
  // out; gotrue reads whichever store you hand it, so nothing else
  // needs to change.
  static const _key = 'supabase.auth.token';

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() {
    return _storage.read(key: _key);
  }

  @override
  Future<bool> hasAccessToken() async {
    return (await _storage.read(key: _key)) != null;
  }

  @override
  Future<void> persistSession(String persistSessionString) {
    return _storage.write(key: _key, value: persistSessionString);
  }

  @override
  Future<void> removePersistedSession() {
    return _storage.delete(key: _key);
  }
}
