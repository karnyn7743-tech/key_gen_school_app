import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'license_history_section.dart';
import 'services/backup_service.dart';
import 'services/license_generator_service.dart';
import 'services/registry_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KeyGeneratorApp());
}

class KeyGeneratorApp extends StatelessWidget {
  const KeyGeneratorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مولّد مفاتيح التفعيل',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF173B70)),
        scaffoldBackgroundColor: const Color(0xFFF3F6FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF173B70),
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      home: const GeneratorHomePage(),
    );
  }
}

class GeneratorHomePage extends StatefulWidget {
  const GeneratorHomePage({super.key});

  @override
  State<GeneratorHomePage> createState() => _GeneratorHomePageState();
}

class _GeneratorHomePageState extends State<GeneratorHomePage> {
  final _deviceController = TextEditingController();
  final _backupPasswordController = TextEditingController();
  final _registry = RegistryService();
  final _generator = LicenseGeneratorService();
  final _backup = BackupService();

  String? _generatedKey;
  String? _error;
  String? _publicKey;
  int _registeredDevices = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void dispose() {
    _deviceController.dispose();
    _backupPasswordController.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    try {
      final count = await _registry.count();
      final publicKey = await _generator.getPublicKey();
      if (!mounted) return;
      setState(() {
        _registeredDevices = count;
        _publicKey = publicKey;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'تعذر تهيئة مفاتيح التوقيع: $e');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _refreshStatus();
      }
    }
  }

  Future<void> _makePermanent() => _run(() async {
        final id = _deviceController.text.trim();
        if (id.isEmpty) throw Exception('أدخل معرّف الجهاز أولاً.');
        final code = _generator.generatePermanentCode(id);
        await _registry.addPermanent(
          deviceId: id,
          code: code,
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
        setState(() => _generatedKey = code);
      });

  Future<void> _makeTrial() => _run(() async {
        final id = _deviceController.text.trim();
        if (id.isEmpty) throw Exception('أدخل معرّف الجهاز أولاً.');
        final code = await _generator.generateTrialCode(id, days: 10);
        setState(() => _generatedKey = code);
      });

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم نسخ $label')),
    );
  }

  Future<void> _exportBackup() => _run(() async {
        final password = _backupPasswordController.text;
        if (password.length < 8) {
          throw Exception('اجعل كلمة مرور النسخة الاحتياطية 8 أحرف على الأقل.');
        }
        final jsonText = await _backup.createEncryptedBackup(password);
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/schoolapp_keys_backup.json');
        await file.writeAsString(jsonText, flush: true);
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'نسخة احتياطية مشفّرة لمولّد مفاتيح التفعيل. احتفظ بكلمة المرور.',
        );
      });

  Future<void> _importBackup() => _run(() async {
        final password = _backupPasswordController.text;
        if (password.length < 8) {
          throw Exception('أدخل كلمة مرور النسخة الاحتياطية أولاً.');
        }
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['json'],
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;
        final picked = result.files.single;
        final content = picked.bytes != null
            ? utf8.decode(picked.bytes!)
            : await File(picked.path!).readAsString();
        await _backup.restoreEncryptedBackup(content, password);
        setState(() {
          _generatedKey = null;
          _deviceController.clear();
        });
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مولّد مفاتيح التفعيل'),
        actions: [
          IconButton(
            tooltip: 'تحديث البيانات',
            onPressed: _busy ? null : _refreshStatus,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified_user, color: Color(0xFF173B70), size: 28),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'إصدار مفاتيح الأجهزة',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'الأجهزة المسجّلة للتجربة: $_registeredDevices',
                      style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _deviceController,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: 'معرّف الجهاز Device ID',
                        hintText: 'ألصق معرّف الجهاز الظاهر في تطبيق العميل',
                        prefixIcon: Icon(Icons.phone_android),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _busy ? null : _makePermanent,
                      icon: const Icon(Icons.workspace_premium),
                      label: const Text('توليد مفتاح دائم STUG'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _makeTrial,
                      icon: const Icon(Icons.timer_outlined),
                      label: const Text('إصدار تجربة جديدة لمدة 10 أيام'),
                    ),
                    if (_generatedKey != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF2FF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF9BBBE8)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'مفتاح التفعيل الناتج',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              _generatedKey!,
                              textAlign: TextAlign.center,
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () => _copy(_generatedKey!, 'مفتاح التفعيل'),
                              icon: const Icon(Icons.copy),
                              label: const Text('نسخ المفتاح'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'مفتاح التحقق العام',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'هذا المفتاح يُنقل إلى تطبيق atmath_exams للتحقق من التراخيص التجريبية. لا تشارك المفتاح الخاص مطلقاً.',
                      style: TextStyle(color: Colors.blueGrey, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _publicKey ?? 'جارٍ إنشاء زوج مفاتيح التوقيع...',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _publicKey == null ? null : () => _copy(_publicKey!, 'مفتاح التحقق العام'),
                      icon: const Icon(Icons.copy),
                      label: const Text('نسخ المفتاح العام'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const LicenseHistorySection(),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'النسخ الاحتياطي لسجل التراخيص',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'النسخة مشفّرة وتتضمن سجل الأجهزة ومفتاح التوقيع الخاص. احتفظ بها في مكان آمن، ولا تفقد كلمة المرور.',
                      style: TextStyle(color: Colors.blueGrey, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _backupPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'كلمة مرور النسخة الاحتياطية',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _exportBackup,
                      icon: const Icon(Icons.backup),
                      label: const Text('إنشاء نسخة احتياطية مشفّرة'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _importBackup,
                      icon: const Icon(Icons.settings_backup_restore),
                      label: const Text('استعادة نسخة احتياطية'),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: TextStyle(color: Colors.red.shade900)),
              ),
            ],
            if (_busy) const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator()),
            ),
            const SizedBox(height: 10),
            const Text(
              'تنبيه: منع التجربة الثانية يعتمد على بقاء سجل المولّد واستعادته عند تغيير الهاتف أو إعادة تثبيت المولّد. لا يوجد خادم مركزي في هذا النظام.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.blueGrey),
            ),
          ],
        ),
      ),
    );
  }
}
