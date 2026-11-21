import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class RegistryService {
  static const String _storageKey = 'schoolapp_trial_registry_v1';

  Future<List<Map<String, dynamic>>> readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('سجل التجارب المحلي غير صالح.');
    }
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<int> count() async => (await readAll()).length;

  Future<bool> hasDevice(String deviceId) async {
    final normalized = deviceId.trim();
    final records = await readAll();
    return records.any((record) => record['deviceId'] == normalized);
  }

  Future<void> add({
    required String deviceId,
    required int issuedAt,
    required int expiresAt,
    required String licenseId,
  }) async {
    final records = await readAll();
    if (records.any((record) => record['deviceId'] == deviceId)) {
      throw Exception('سبق إصدار تجربة لهذا الجهاز. لن يصدر له مفتاح تجريبي آخر.');
    }
    records.add({
      'deviceId': deviceId,
      'issuedAt': issuedAt,
      'expiresAt': expiresAt,
      'licenseId': licenseId,
    });
    await _write(records);
  }

  Future<void> replaceAll(List<Map<String, dynamic>> records) async {
    final seen = <String>{};
    for (final record in records) {
      final id = record['deviceId'];
      if (id is! String || id.trim().isEmpty || !seen.add(id)) {
        throw const FormatException('النسخة الاحتياطية تحتوي سجلاً غير صالح أو معرّفاً مكرراً.');
      }
      if (record['issuedAt'] is! int || record['expiresAt'] is! int) {
        throw const FormatException('بيانات تاريخ أحد سجلات النسخة الاحتياطية غير صالحة.');
      }
    }
    await _write(records);
  }

  Future<void> _write(List<Map<String, dynamic>> records) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(_storageKey, jsonEncode(records));
    if (!ok) throw Exception('تعذر حفظ سجل الأجهزة على الهاتف.');
  }
}
