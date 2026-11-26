import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'license_generator_service.dart';
import 'registry_service.dart';

class BackupService {
  final LicenseGeneratorService _generator = LicenseGeneratorService();
  final RegistryService _registry = RegistryService();

  Future<String> createEncryptedBackup(String password) async {
    if (password.length < 8) {
      throw Exception('كلمة المرور قصيرة جداً.');
    }
    final payload = {
      'format': 'schoolapp-keygen-backup',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'privateSeed': await _generator.exportPrivateSeedForBackup(),
      'registry': await _registry.readAll(),
      'permanentRegistry': await _registry.readPermanentAll(),
    };
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final key = await _deriveKey(password, salt);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: key,
      nonce: nonce,
    );
    return jsonEncode({
      'format': 'schoolapp-keygen-encrypted',
      'version': 1,
      'kdf': 'PBKDF2-HMAC-SHA256-210000',
      'cipher': 'AES-256-GCM',
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }

  Future<void> restoreEncryptedBackup(String backupText, String password) async {
    final outer = jsonDecode(backupText);
    if (outer is! Map || outer['format'] != 'schoolapp-keygen-encrypted' ||
        outer['version'] != 1) {
      throw const FormatException('ملف النسخة الاحتياطية غير معروف أو غير مدعوم.');
    }

    final salt = base64Decode(outer['salt'] as String);
    final nonce = base64Decode(outer['nonce'] as String);
    final cipherText = base64Decode(outer['ciphertext'] as String);
    final mac = base64Decode(outer['mac'] as String);
    final key = await _deriveKey(password, salt);
    final clearBytes = await AesGcm.with256bits().decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
    );
    final payload = jsonDecode(utf8.decode(clearBytes));
    if (payload is! Map || payload['format'] != 'schoolapp-keygen-backup' ||
        payload['version'] != 1 || payload['privateSeed'] is! String ||
        payload['registry'] is! List ||
        (payload['permanentRegistry'] != null && payload['permanentRegistry'] is! List)) {
      throw const FormatException('محتويات النسخة الاحتياطية غير مكتملة.');
    }

    final records = (payload['registry'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    // نتحقق من سجل الأجهزة أولاً، ثم نعيد مفتاح التوقيع.
    final permanentRecords = payload['permanentRegistry'] == null
        ? <Map<String, dynamic>>[]
        : (payload['permanentRegistry'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
    await _registry.replaceAll(records);
    await _registry.replacePermanentAll(permanentRecords);
    await _generator.restorePrivateSeed(payload['privateSeed'] as String);
  }

  Future<SecretKey> _deriveKey(String password, List<int> salt) {
    return Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 210000,
      bits: 256,
    ).deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}
