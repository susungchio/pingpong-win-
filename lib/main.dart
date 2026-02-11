import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'setup_page.dart';

// 영역별 폰트 설정을 위한 클래스
class FontSettings {
  final String? titleFont;
  final String? headerFont;
  final String? bodyFont;

  FontSettings({this.titleFont, this.headerFont, this.bodyFont});

  Map<String, dynamic> toJson() => {
    'titleFont': titleFont,
    'headerFont': headerFont,
    'bodyFont': bodyFont,
  };

  factory FontSettings.fromJson(Map<String, dynamic> json) => FontSettings(
    titleFont: json['titleFont'],
    headerFont: json['headerFont'],
    bodyFont: json['bodyFont'],
  );
}

final ValueNotifier<FontSettings> appFontNotifier = ValueNotifier<FontSettings>(
  FontSettings(titleFont: null, headerFont: null, bodyFont: null),
);

Future<File> _getFontConfigFile() async {
  final directory = await getApplicationDocumentsDirectory();
  return File('${directory.path}/font_config.json');
}

Future<void> saveFontSettings(FontSettings settings) async {
  try {
    final file = await _getFontConfigFile();
    await file.writeAsString(jsonEncode(settings.toJson()));
  } catch (e) {
    debugPrint('폰트 저장 오류: $e');
  }
}

Future<void> loadFontSettings() async {
  try {
    final file = await _getFontConfigFile();
    if (await file.exists()) {
      final content = await file.readAsString();
      final Map<String, dynamic> json = jsonDecode(content);
      appFontNotifier.value = FontSettings.fromJson(json);
    }
  } catch (e) {
    debugPrint('폰트 로드 오류: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // [수정] 윈도우/데스크톱용 SQLite FFI 초기화
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await loadFontSettings();

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1920, 1060),
      minimumSize: Size(1280, 720),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: '탁구 토너먼트 매니저',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

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
    return ValueListenableBuilder<FontSettings>(
      valueListenable: appFontNotifier,
      builder: (context, fonts, child) {
        return MaterialApp(
          title: '탁구 토너먼트 매니저',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            textTheme: TextTheme(
              displayLarge: TextStyle(fontFamily: fonts.titleFont),
              displayMedium: TextStyle(fontFamily: fonts.titleFont),
              displaySmall: TextStyle(fontFamily: fonts.titleFont),
              headlineLarge: TextStyle(fontFamily: fonts.titleFont),
              headlineMedium: TextStyle(fontFamily: fonts.headerFont),
              headlineSmall: TextStyle(fontFamily: fonts.headerFont),
              titleLarge: TextStyle(fontFamily: fonts.headerFont),
              titleMedium: TextStyle(fontFamily: fonts.headerFont),
              titleSmall: TextStyle(fontFamily: fonts.headerFont),
              bodyLarge: TextStyle(fontFamily: fonts.bodyFont),
              bodyMedium: TextStyle(fontFamily: fonts.bodyFont),
              bodySmall: TextStyle(fontFamily: fonts.bodyFont),
              labelLarge: TextStyle(fontFamily: fonts.bodyFont),
              labelMedium: TextStyle(fontFamily: fonts.bodyFont),
              labelSmall: TextStyle(fontFamily: fonts.bodyFont),
            ),
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
      },
    );
  }
}
