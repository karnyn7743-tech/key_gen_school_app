import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KeyGenSchoolApp());
}

class KeyGenSchoolApp extends StatelessWidget {
  const KeyGenSchoolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'key_gen_SchoolApp',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'SA'),
      supportedLocales: const [
        Locale('ar', 'SA'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F172A), // ثيم احترافي غامق للإدارة
          primary: const Color(0xFF0F172A),
          secondary: const Color(0xFF2563EB),
        ),
      ),
      home: const KeyGeneratorScreen(),
    );
  }
}

class KeyGeneratorScreen extends StatefulWidget {
  const KeyGeneratorScreen({super.key});

  @override
  State<KeyGeneratorScreen> createState() => _KeyGeneratorScreenState();
}

class _KeyGeneratorScreenState extends State<KeyGeneratorScreen> {
  // المفتاح السري المطابق تماماً للموجود في تطبيق مدير الدوام
  static const String _secretSalt = "SCHOOL_SCHEDULE_SECRET_KEY_2026";

  final TextEditingController _deviceIdController = TextEditingController();
  String _generatedKey = '';

  // توليد مفتاح التفعيل باستخدام SHA-256
  void _generateKey() {
    final String deviceId = _deviceIdController.text.trim();
    if (deviceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى لصق أو كتابة معرّف الجهاز (Device ID) أولاً'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final String raw = "${deviceId}_$_secretSalt";
    final Digest digest = sha256.convert(utf8.encode(raw));
    final String fullHex = digest.toString().toUpperCase();

    // تقسيم أول 16 حرفاً إلى 4 مجموعات
    final part1 = fullHex.substring(0, 4);
    final part2 = fullHex.substring(4, 8);
    final part3 = fullHex.substring(8, 12);
    final part4 = fullHex.substring(12, 16);

    setState(() {
      _generatedKey = "$part1-$part2-$part3-$part4";
    });
  }

  // نسخ المفتاح إلى الحافظة
  void _copyToClipboard() {
    if (_generatedKey.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _generatedKey));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ مفتاح التفعيل بنجاح!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // لصق المعرف من الحافظة مباشرة
  Future<void> _pasteFromClipboard() async {
    final ClipboardData? data = await Clipboard.getData('text/plain');
    if (data != null && data.text != null) {
      setState(() {
        _deviceIdController.text = data.text!.trim();
      });
      _generateKey();
    }
  }

  @override
  void dispose() {
    _deviceIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'مولّد مفاتيح التفعيل | key_gen_SchoolApp',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0F172A),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            const Icon(
              Icons.vpn_key_rounded,
              size: 70,
              color: Color(0xFF2563EB),
            ),
            const SizedBox(height: 10),
            const Text(
              'توليد مفتاح تفعيل لمدير دوام المدرسة',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'الصق رمز الجهاز المستلم من العميل لتوليد المفتاح المخصص له فوراً.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // حقل إدخال رمز الجهاز
            TextField(
              controller: _deviceIdController,
              decoration: InputDecoration(
                labelText: 'رمز الجهاز (Device ID)',
                hintText: 'مثال: e4b27a81093c8d41',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.phone_android),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste),
                  tooltip: 'لصق من الحافظة وتوليد',
                  onPressed: _pasteFromClipboard,
                ),
              ),
            ),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: _generateKey,
              icon: const Icon(Icons.generating_tokens_outlined),
              label: const Text(
                'توليد مفتاح التفعيل',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),

            const SizedBox(height: 30),

            // عرض المفتاح الناتج
            if (_generatedKey.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.blue.shade200, width: 1.5),
                ),
                child: Column(
                  children: [
                    const Text(
                      'مفتاح التفعيل الناتج:',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      _generatedKey,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _copyToClipboard,
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('نسخ المفتاح وإرساله للعميل'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1E3A8A),
                        side: const BorderSide(color: Color(0xFF1E3A8A)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
