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
      ..loadRequest(Uri.parse(gameUrl));
  }

  @override
  void dispose() {
    // مهم جداً: إغلاق المتحكم عند الخروج من الشاشة لمنع تسريب الذاكرة (Memory Leak)
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        // استخدمنا Stack لوضع الويب فيو فوق الخلفية
        children: [
          // 1. طبقة الخلفية المتحركة (السماء)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bgController,
              builder: (context, child) {
                return Stack(
                  children: [
                    // الصورة الأولى تتحرك لليسار
                    FractionalTranslation(
                      translation: Offset(-_bgController.value, 0),
                      child: child,
                    ),
                    // الصورة الثانية تكمل الفراغ فوراً لتبدو متصلة
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
                    fit: BoxFit.cover, // لتغطية الشاشة بالكامل
                  ),
                ),
              ),
            ),
          ),

          // 2. طبقة اللعبة (WebView)
          Positioned.fill(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
