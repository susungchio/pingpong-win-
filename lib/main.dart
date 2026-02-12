import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'setup_page.dart';
import 'file_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 외부 폰트 로드
  await _loadExternalFonts();

  // 2. 저장된 설정 로드 (폰트 설정, 경기종목 표시 설정 등)
  await FileUtils.loadFontSettings();
  await FileUtils.loadEventDisplaySettings();
  await FileUtils.getAdminPassword(); // 비밀번호 로드 및 노티파이어 초기화

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 800),
    center: true,
    title: "탁구 대회 관리 시스템",
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const PingPongApp());
}

Future<void> _loadExternalFonts() async {
  try {
    final exePath = File(Platform.resolvedExecutable).parent.path;
    final fontDir = Directory('$exePath/fonts');

    if (await fontDir.exists()) {
      final fontFiles = fontDir.listSync().whereType<File>().where(
        (file) => file.path.toLowerCase().endsWith('.ttf')
      );

      for (var fontFile in fontFiles) {
        final familyName = fontFile.path.split(Platform.pathSeparator).last.split('.').first;
        final data = await fontFile.readAsBytes();

        final fontLoader = FontLoader(familyName);
        fontLoader.addFont(Future.value(ByteData.view(data.buffer)));
        await fontLoader.load();
        debugPrint('외부 폰트 로드 완료: $familyName');
      }
    }
  } catch (e) {
    debugPrint('폰트 로딩 오류: $e');
  }
}

class PingPongApp extends StatelessWidget {
  const PingPongApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FontSettings>(
      valueListenable: appFontNotifier,
      builder: (context, fontSettings, _) {
        return MaterialApp(
          title: '탁구 대회 관리',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1A535C),
              primary: const Color(0xFF1A535C),
              secondary: const Color(0xFFFF6B6B),
            ),
            // 설정된 바디 폰트가 있으면 적용, 없으면 기본 세종고딕
            fontFamily: fontSettings.bodyFont ?? 'SJ세종고딕',
          ),
          home: const SetupPage(),
        );
      }
    );
  }
}
