import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ضبط التطبيق على الوضع العرضي وإخفاء شريط النظام
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: GameWebView()),
  );
}

class GameWebView extends StatefulWidget {
  const GameWebView({super.key});

  @override
  // أضفنا SingleTickerProviderStateMixin لدعم الـ Animation
  State<GameWebView> createState() => _GameWebViewState();
}

class _GameWebViewState extends State<GameWebView>
    with SingleTickerProviderStateMixin {
  late final WebViewController _controller;
  late final AnimationController _bgController; // متحكم حركة السماء

  final String gameUrl = 'https://rococo-torrone-48b523.netlify.app/';

  @override
  void initState() {
    super.initState();

    // إعداد حركة الخلفية
    // يمكنك تعديل الثواني (20) للتحكم في سرعة حركة السحاب
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat(); // repeat تجعل الحركة تستمر للأبد (Infinite Loop)

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // الأهم: جعل الويب فيو "شفاف" لتظهر صورتنا من تحته
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'FishermanBridge',
        onMessageReceived: (msg) {
          try {
            final data = jsonDecode(msg.message);
            print('Current Balance from Game: ${data['balance']}');
          } catch (e) {
            debugPrint('Error: $e');
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            await _forceTransparentWebPage();
            await _syncInitialStateFromJs();
            _startBootstrapSyncLoop();
          },
        ),
      )
      ..loadRequest(Uri.parse(gameUrl));

    Future.microtask(() async {
      await _forceTransparentWebPage();
      await _syncInitialStateFromJs();
      _startBootstrapSyncLoop();
    });
  }

  void _startBootstrapSyncLoop() {
    // نحاول عدة مرات في البداية لأن Construct قد يتأخر لحظة في تجهيز الجسر.
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

  Future<void> _syncInitialStateFromJs() async {
    try {
      final raw = await _controller.runJavaScriptReturningResult('''
(() => {
  const bridge = window.FishermanFlutterBridge;
  if (!bridge || !bridge.getState) return "null";
  return JSON.stringify(bridge.getState());
})();
''');

      final normalized = _normalizeJsResult(raw);
      if (normalized == 'null') return;

      final decoded = jsonDecode(normalized);
      if (decoded is! Map<String, dynamic>) return;

      setState(() {
        _bridgeReady = decoded['ready'] == true;
        _balance = _toInt(decoded['balance']);
        _lastEvent = 'initial-sync';
      });
    } catch (_) {
      // لو الجسر مش جاهز بعد، نسيب retry loop يكمل.
    }
  }

  Future<void> _forceTransparentWebPage() async {
    try {
      await _controller.runJavaScript('''
(function () {
  const apply = (el) => {
    if (!el) return;
    el.style.background = 'transparent';
    el.style.backgroundColor = 'transparent';
    el.style.backgroundImage = 'none';
  };

  apply(document.documentElement);
  apply(document.body);

  const canvases = document.querySelectorAll('canvas');
  canvases.forEach((canvas) => {
    canvas.style.background = 'transparent';
    canvas.style.backgroundColor = 'transparent';
    canvas.style.display = 'block';
  });

  const style = document.createElement('style');
  style.textContent = `
    html, body, canvas {
      background: transparent !important;
      background-color: transparent !important;
      background-image: none !important;
    }
    body {
      margin: 0 !important;
      overflow: hidden !important;
    }
    canvas {
      position: fixed !important;
      inset: 0 !important;
      width: 100vw !important;
      height: 100vh !important;
      display: block !important;
    }
  `;
  document.head.appendChild(style);
})();
''');
    } catch (_) {
      // لو الحقن فشل نحافظ على تشغيل اللعبة عادي.
    }
  }

  @override
  void dispose() {
    // مهم جداً: إغلاق المتحكم عند الخروج من الشاشة لمنع تسريب الذاكرة (Memory Leak)
    _bgController.dispose();
    _bootstrapSyncTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bgController,
              builder: (context, child) {
                return Stack(
                  children: [
                    FractionalTranslation(
                      translation: Offset(-_bgController.value, 0),
                      child: child,
                    ),
                    FractionalTranslation(
                      translation: Offset(1 - _bgController.value, 0),
                      child: child,
                    ),
                  ],
                );
              },
              child: Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage(
                      'https://images.unsplash.com/photo-1570483358100-6d222cdea6ff?w=600&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8MTJ8fHNreXxlbnwwfHwwfHx8MA%3D%3D',
                    ),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
