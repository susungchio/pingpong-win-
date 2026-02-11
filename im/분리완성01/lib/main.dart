import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'setup_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const PingPongApp());
}

class PingPongApp extends StatelessWidget {
  const PingPongApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '탁구 토너먼트 매니저',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A535C),
          primary: const Color(0xFF1A535C),
          secondary: const Color(0xFF4ECDC4),
          surface: const Color(0xFFF7FFF7),
        ),
        cardTheme: const CardThemeData(elevation: 0, color: Colors.white),
      ),
      home: const SetupPage(),
    );
  }
}
