import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// مفاتيح API مشفّرة عبر Android Keystore (EncryptedSharedPreferences).
/// ممنوع طباعة المفاتيح أو تسجيلها أو تضمينها في الكود.
class ApiKeyStore {
  static const youtube = 'youtube';
  static const uspto = 'uspto_patentsearch';
  static const openai = 'openai';
  static const newsapi = 'newsapi';
  static const reddit = 'reddit';
  static const x = 'x';

  static const providers = <String, String>{
    youtube: 'YouTube Data API v3',
    uspto: 'USPTO PatentSearch API',
    openai: 'OpenAI',
    newsapi: 'NewsAPI',
    reddit: 'Reddit',
    x: 'X (Twitter)',
  };

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String _k(String provider) => 'apikey_$provider';

  Future<String?> read(String provider) => _storage.read(key: _k(provider));

  Future<void> write(String provider, String value) =>
      _storage.write(key: _k(provider), value: value.trim());

  Future<void> delete(String provider) => _storage.delete(key: _k(provider));

  static String hint(String value) =>
      value.length <= 4 ? '••••' : '••••${value.substring(value.length - 4)}';
}
