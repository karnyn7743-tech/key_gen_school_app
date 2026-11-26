import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'registry_service.dart';

class LicenseGeneratorService {
  static const String _permanentSalt = 'STUGRA_SCAN_SECRET_KEY_2026';
  static const String _privateSeedStorageKey = 'schoolapp_ed25519_private_seed_v1';
  static const int trialDays = 10;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final RegistryService _registry = RegistryService();
  final Ed25519 _ed25519 = Ed25519();

  String generatePermanentCode(String deviceId) {
    final cleanId = deviceId.trim();
    if (cleanId.isEmpty) throw Exception('معرّف الجهاز فارغ.');
    final digest = sha256
        .convert(utf8.encode(cleanId + _permanentSalt))
        .toString()
        .toUpperCase();
    return 'STUG-${digest.substring(0, 4)}-${digest.substring(4, 8)}';
  }

  Future<String> generateTrialCode(String deviceId, {int days = trialDays}) async {
    final cleanId = deviceId.trim();
    if (cleanId.isEmpty) throw Exception('معرّف الجهاز فارغ.');
    if (days < 1 || days > 10) throw Exception('مدة التجربة يجب أن تكون بين يوم و10 أيام.');
    if (await _registry.hasDevice(cleanId)) {
      throw Exception('هذا الجهاز سبق أن حصل على تجربة. لا يمكن إصدار تجربة أخرى له.');
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expires = now + (days * 24 * 60 * 60);
    final nonce = _randomBytes(16);
    final payload = jsonEncode({
      'v': 1,
      'd': cleanId,
      'iat': now,
      'exp': expires,
      'n': base64UrlEncode(nonce).replaceAll('=', ''),
    });
    final payloadBytes = utf8.encode(payload);
    final pair = await _loadOrCreateKeyPair();
    final signature = await _ed25519.sign(payloadBytes, keyPair: pair);
    final token = 'TRIAL2.'
        '${base64UrlEncode(payloadBytes).replaceAll('=', '')}.'
        '${base64UrlEncode(signature.bytes).replaceAll('=', '')}';

    // نسجل الجهاز قبل إظهار المفتاح حتى لا يصدر مفتاح ثانٍ عند تكرار الضغط.
    await _registry.add(
      deviceId: cleanId,
      issuedAt: now,
      expiresAt: expires,
      licenseId: base64UrlEncode(nonce).replaceAll('=', ''),
    );
    return token;
  }

  Future<String> recreateTrialCode(Map<String, dynamic> record) async {
    final deviceId = record['deviceId'];
    final issuedAt = record['issuedAt'];
    final expiresAt = record['expiresAt'];
    final licenseId = record['licenseId'];
    if (deviceId is! String || deviceId.trim().isEmpty ||
        issuedAt is! int || expiresAt is! int ||
        licenseId is! String || licenseId.isEmpty) {
      throw const FormatException('بيانات سجل التجربة لا تكفي لإعادة تكوين المفتاح.');
    }
    // ترتيب الحقول وصيغة JSON مطابقان تماماً لما استُخدما عند الإصدار الأصلي.
    final payload = jsonEncode({
      'v': 1,
      'd': deviceId,
      'iat': issuedAt,
      'exp': expiresAt,
      'n': licenseId,
    });
    final payloadBytes = utf8.encode(payload);
    final pair = await _loadOrCreateKeyPair();
    final signature = await _ed25519.sign(payloadBytes, keyPair: pair);
    return 'TRIAL2.'
        '${base64UrlEncode(payloadBytes).replaceAll('=', '')}.'
        '${base64UrlEncode(signature.bytes).replaceAll('=', '')}';
  }

  Future<String> getPublicKey() async {
    final pair = await _loadOrCreateKeyPair();
    final publicKey = await pair.extractPublicKey();
    return base64UrlEncode(publicKey.bytes).replaceAll('=', '');
  }

  Future<String> exportPrivateSeedForBackup() async {
    final pair = await _loadOrCreateKeyPair();
    final seed = await pair.extractPrivateKeyBytes();
    return base64Encode(seed);
  }

  Future<void> restorePrivateSeed(String encodedSeed) async {
    final seed = base64Decode(encodedSeed);
    if (seed.length != 32) {
      throw const FormatException('مفتاح التوقيع في النسخة الاحتياطية غير صالح.');
    }
    final pair = await _ed25519.newKeyPairFromSeed(seed);
    final publicKey = await pair.extractPublicKey();
    if (publicKey.bytes.length != 32) {
      throw const FormatException('تعذر التحقق من مفتاح التوقيع المستعاد.');
    }
    await _secureStorage.write(
      key: _privateSeedStorageKey,
      value: base64Encode(seed),
    );
  }

  Future<SimpleKeyPair> _loadOrCreateKeyPair() async {
    final saved = await _secureStorage.read(key: _privateSeedStorageKey);
    if (saved != null && saved.isNotEmpty) {
      final seed = base64Decode(saved);
      if (seed.length != 32) {
        throw const FormatException('مفتاح التوقيع المحلي تالف. استعد النسخة الاحتياطية.');
      }
      return _ed25519.newKeyPairFromSeed(seed);
    }

    final pair = await _ed25519.newKeyPair();
    final seed = await pair.extractPrivateKeyBytes();
    await _secureStorage.write(
      key: _privateSeedStorageKey,
      value: base64Encode(seed),
    );
    return pair;
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}
