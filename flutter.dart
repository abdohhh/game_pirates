// ملف Flutter جاهز للربط مع لعبة الويب عبر WebView.
// الفكرة الأساسية:
// 1) نفتح اللعبة داخل WebView.
// 2) نستقبل رسائل من الجسر JavaScript.
// 3) نبعث أوامر للجسر لتعديل العملة (الرصيد).

import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

// نقطة تشغيل التطبيق.
void main() {
  // تأكد أن Flutter engine جهز كل الـ bindings قبل أي عمل async.
  WidgetsFlutterBinding.ensureInitialized();

  // تشغيل التطبيق الرئيسي.
  runApp(const FishermanApp());
}

// الـ App root: هنا إعداد الثيم والشاشة الرئيسية.
class FishermanApp extends StatelessWidget {
  const FishermanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Fisherman Wallet Bridge',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const FishermanWebViewScreen(),
    );
  }
}

// شاشة الربط: فيها WebView + حالة الرصيد + أزرار اختبار.
class FishermanWebViewScreen extends StatefulWidget {
  const FishermanWebViewScreen({super.key});

  @override
  State<FishermanWebViewScreen> createState() => _FishermanWebViewScreenState();
}

class _FishermanWebViewScreenState extends State<FishermanWebViewScreen> {
  // كنترولر WebView: عن طريقه نفتح الرابط وننفذ JavaScript.
  late final WebViewController _controller;

  // حالة محلية في Flutter لعرض معلومات الجسر والرصيد.
  int _balance = 0;
  bool _bridgeReady = false;
  String _lastEvent = 'idle';
  Timer? _bootstrapSyncTimer;

  // مهم جدا: عدّل الرابط ده إلى رابط لعبتك الحقيقي.
  static const String gameUrl = 'https://your-domain.com/';

  @override
  void initState() {
    super.initState();

    // إعداد الـ WebView بالكامل عند فتح الشاشة.
    _controller = WebViewController()
      // نسمح بتشغيل JavaScript لأن الجسر معتمد عليه.
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // قناة الرسائل الأساسية المتوقعة من bridge في اللعبة.
      ..addJavaScriptChannel(
        'FishermanBridge',
        onMessageReceived: (msg) => _onBridgeMessage(msg.message),
      )
      // قناة بديلة (احتياط) لأن bridge عندك بيدور على أكثر من اسم.
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (msg) => _onBridgeMessage(msg.message),
      )
      // قناة بديلة ثالثة (احتياط إضافي).
      ..addJavaScriptChannel(
        'fishermanBridge',
        onMessageReceived: (msg) => _onBridgeMessage(msg.message),
      )
      // متابعة أحداث الملاحة.
      ..setNavigationDelegate(
        NavigationDelegate(
          // لما الصفحة تخلص تحميل: نسحب الحالة الحالية من JavaScript.
          onPageFinished: (_) async {
            await _syncInitialStateFromJs();
            _startBootstrapSyncLoop();
          },
        ),
      )
      // فتح اللعبة داخل WebView.
      ..loadRequest(Uri.parse(gameUrl));
  }

  // Retry loop بسيط في البداية لو الجسر اتأخر في التجهيز.
  void _startBootstrapSyncLoop() {
    _bootstrapSyncTimer?.cancel();

    var attempts = 0;
    const maxAttempts = 20;

    _bootstrapSyncTimer = Timer.periodic(const Duration(milliseconds: 700), (
      timer,
    ) async {
      if (_bridgeReady || attempts >= maxAttempts) {
        timer.cancel();
        return;
      }

      attempts++;
      await _syncInitialStateFromJs();
    });
  }

  // استقبال الرسالة القادمة من JavaScript channel.
  void _onBridgeMessage(String rawMessage) {
    try {
      // الرسالة جاية JSON string، نحولها إلى Map.
      final decoded = jsonDecode(rawMessage);
      if (decoded is! Map<String, dynamic>) return;

      // استخراج أهم حقول البروتوكول.
      final type = decoded['type']?.toString() ?? '';
      final balanceValue = _toInt(decoded['balance']);
      final readyValue = decoded['ready'] == true;

      // تحديث الواجهة المحلية.
      setState(() {
        _balance = balanceValue;
        _bridgeReady = readyValue;
        _lastEvent = type.isEmpty ? 'unknown' : type;
      });
    } catch (_) {
      // لو الرسالة malformed ما نكسرش التطبيق.
    }
  }

  // نسحب الحالة المبدئية من الجسر JavaScript بعد تحميل الصفحة.
  Future<void> _syncInitialStateFromJs() async {
    // بننادي window.FishermanFlutterBridge.getState() ونرجع JSON string.
    final raw = await _controller.runJavaScriptReturningResult('''
(() => {
	const bridge = window.FishermanFlutterBridge;
	if (!bridge || !bridge.getState) return "null";
	return JSON.stringify(bridge.getState());
})();
''');

    // بعض المنصات ترجع النص محاط باقتباس إضافي، فننظفه.
    final normalized = _normalizeJsResult(raw);
    if (normalized == 'null') return;

    // تحويل النص إلى JSON واستخراج القيم.
    final decoded = jsonDecode(normalized);
    if (decoded is! Map<String, dynamic>) return;

    setState(() {
      _bridgeReady = decoded['ready'] == true;
      _balance = _toInt(decoded['balance']);
      _lastEvent = 'initial-sync';
    });
  }

  // إرسال أمر مباشر لضبط الرصيد من Flutter إلى اللعبة.
  Future<void> _setBalance(int value) async {
    await _controller.runJavaScript(
      'window.FishermanFlutterBridge?.setBalance($value, "flutter-set");',
    );
  }

  // إرسال أمر زيادة/نقصان الرصيد.
  Future<void> _adjustBalance(int delta) async {
    await _controller.runJavaScript(
      'window.FishermanFlutterBridge?.adjustBalance($delta, "flutter-adjust");',
    );
  }

  // طلب مزامنة من جهة اللعبة (لو اللعبة عدلت الرصيد داخليًا).
  Future<void> _requestGameToPushState() async {
    await _controller.runJavaScript(
      'window.FishermanFlutterBridge?.syncFromGame("flutter-sync-request");',
    );
  }

  // تحويل آمن لأي قيمة رقمية جاية من JSON إلى int.
  int _toInt(Object? v) {
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  // تنظيف ناتج JavaScript Returning Result بين Android/iOS.
  String _normalizeJsResult(Object raw) {
    final text = raw.toString().trim();

    // لو النتيجة String مغلف داخل String JSON، نفك التغليف.
    if ((text.startsWith('"') && text.endsWith('"')) ||
        (text.startsWith("'") && text.endsWith("'"))) {
      try {
        final unwrapped = jsonDecode(text);
        if (unwrapped is String) return unwrapped;
      } catch (_) {
        // لو فشل الفك نرجع النص الأصلي.
      }
    }

    return text;
  }

  @override
  void dispose() {
    _bootstrapSyncTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fisherman + Flutter Wallet')),
      body: Column(
        children: [
          // شريط حالة بسيط يعرض حالة الجسر والرصيد وآخر event.
          Container(
            width: double.infinity,
            color: Colors.blueGrey.shade50,
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Bridge: ${_bridgeReady ? "READY" : "NOT READY"}'),
                Text('Balance: $_balance'),
                Text('Last event: $_lastEvent'),
              ],
            ),
          ),

          // مساحة اللعبة نفسها داخل WebView.
          Expanded(child: WebViewWidget(controller: _controller)),

          // أزرار اختبار يدوية للتأكد أن الربط شغال.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () => _setBalance(5000),
                  child: const Text('Set 5000'),
                ),
                ElevatedButton(
                  onPressed: () => _adjustBalance(100),
                  child: const Text('+100'),
                ),
                ElevatedButton(
                  onPressed: () => _adjustBalance(-50),
                  child: const Text('-50'),
                ),
                OutlinedButton(
                  onPressed: _requestGameToPushState,
                  child: const Text('Sync From Game'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
