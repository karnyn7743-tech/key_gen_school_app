import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/license_generator_service.dart';
import 'services/registry_service.dart';

class LicenseHistorySection extends StatefulWidget {
  const LicenseHistorySection({super.key});

  @override
  State<LicenseHistorySection> createState() => _LicenseHistorySectionState();
}

class _LicenseHistorySectionState extends State<LicenseHistorySection> {
  final _registry = RegistryService();
  final _generator = LicenseGeneratorService();
  final _legacyDeviceController = TextEditingController();
  List<Map<String, dynamic>> _trials = [];
  List<Map<String, dynamic>> _permanent = [];
  bool _loading = true;
  String? _error;

  @override
  void dispose() {
    _legacyDeviceController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trials = await _registry.readAll();
      final permanent = await _registry.readPermanentAll();
      if (!mounted) return;
      setState(() {
        _trials = trials.reversed.toList();
        _permanent = permanent.reversed.toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ المفتاح')),
    );
  }

  Future<void> _copyAll() async {
    try {
      final keys = <String>[];
      for (final record in _trials) {
        keys.add(await _generator.recreateTrialCode(record));
      }
      for (final record in _permanent) {
        final code = record['code'];
        if (code is String && code.isNotEmpty) keys.add(code);
      }
      if (keys.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد مفاتيح محفوظة لنسخها')),
        );
        return;
      }
      await _copy(keys.join('\n'));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تجهيز المفاتيح: $e')),
      );
    }
  }

  Future<void> _restorePermanentFromDeviceId() async {
    final id = _legacyDeviceController.text.trim();
    if (id.isEmpty) return;
    try {
      final code = _generator.generatePermanentCode(id);
      await _registry.addPermanent(
        deviceId: id,
        code: code,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      _legacyDeviceController.clear();
      await _load();
      await _copy(code);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر استعادة المفتاح الدائم: $e')),
      );
    }
  }

  String _date(dynamic seconds) {
    if (seconds is! int) return 'غير محدد';
    final d = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('سجل مفاتيح التفعيل السابقة',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  tooltip: 'تحديث السجل',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const Text(
              'يمكنك استعادة مفاتيح التجربة التي صدرت سابقاً ونسخها، كما تُحفظ المفاتيح الدائمة الجديدة تلقائياً.',
              style: TextStyle(color: Colors.blueGrey, fontSize: 12),
            ),
            const SizedBox(height: 10),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            if (!_loading && _error == null) ...[
              Text('مفاتيح التجربة: ${_trials.length}  |  المفاتيح الدائمة: ${_permanent.length}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('استعادة مفتاح دائم قديم من معرّف الجهاز',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: _legacyDeviceController,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  hintText: 'أدخل Device ID القديم',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _restorePermanentFromDeviceId,
                icon: const Icon(Icons.restore),
                label: const Text('إعادة توليد المفتاح الدائم ونسخه'),
              ),
              const Divider(height: 20),
              if (_trials.isEmpty && _permanent.isEmpty)
                const Text('لا توجد مفاتيح مسجلة حتى الآن.'),
              ..._trials.map((record) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.timer_outlined),
                    title: Text('تجريبي — ${record['deviceId'] ?? ''}',
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Text('تاريخ الإصدار: ${_date(record['issuedAt'])}  |  الانتهاء: ${_date(record['expiresAt'])}'),
                    trailing: IconButton(
                      tooltip: 'إعادة تكوين ونسخ المفتاح',
                      icon: const Icon(Icons.copy),
                      onPressed: () async {
                        try {
                          await _copy(await _generator.recreateTrialCode(record));
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('تعذر استعادة المفتاح: $e')),
                            );
                          }
                        }
                      },
                    ),
                  )),
              ..._permanent.map((record) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.workspace_premium),
                    title: Text('دائم — ${record['deviceId'] ?? ''}',
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontSize: 13)),
                    subtitle: SelectableText(record['code']?.toString() ?? '',
                        textDirection: TextDirection.ltr),
                    trailing: IconButton(
                      tooltip: 'نسخ المفتاح',
                      icon: const Icon(Icons.copy),
                      onPressed: () => _copy(record['code'].toString()),
                    ),
                  )),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _trials.isEmpty && _permanent.isEmpty ? null : _copyAll,
                icon: const Icon(Icons.copy_all),
                label: const Text('نسخ جميع المفاتيح'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
