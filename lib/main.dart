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

  // 0. 경로 설정 로드 (가장 먼저 실행되어야 함)
  await FileUtils.initConfig();

  // 1. 외부 폰트 로드 (지정된 경로의 fonts 폴더에서)
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
    // 지정된 경로의 fonts 폴더에서 폰트 로드
    final fontDirPath = await FileUtils.getFontsDirPath();
    final fontDir = Directory(fontDirPath);

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
        debugPrint('외부 폰트 로드 완료: $familyName (경로: $fontDirPath)');
      }
    } else {
      debugPrint('폰트 폴더가 존재하지 않습니다: $fontDirPath');
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
            // 기본 폰트 설정 (bodyFont 사용)
            fontFamily: fontSettings.bodyFont ?? 'SJ세종고딕',
            // textTheme을 사용하여 제목, 헤더, 본문 폰트를 각각 적용
            textTheme: TextTheme(
              // Display 스타일 (가장 큰 제목) - titleFont 사용
              displayLarge: TextStyle(fontFamily: fontSettings.titleFont ?? fontSettings.bodyFont ?? 'SJ세종고딕'),
              displayMedium: TextStyle(fontFamily: fontSettings.titleFont ?? fontSettings.bodyFont ?? 'SJ세종고딕'),
              displaySmall: TextStyle(fontFamily: fontSettings.titleFont ?? fontSettings.bodyFont ?? 'SJ세종고딕'),
              // Headline 스타일 (헤더) - headerFont 사용
              headlineLarge: TextStyle(fontFamily: fontSettings.headerFont ?? fontSettings.bodyFont ?? 'SJ세종고딕'),
              headlineMedium: TextStyle(fontFamily: fontSettings.headerFont ?? fontSettings.bodyFont ?? 'SJ세종고딕'),
              headlineSmall: TextStyle(fontFamily: fontSettings.headerFont ?? fontSettings.bodyFont ?? 'SJ세종고딕'),
              // Title 스타일 (중간 제목) - headerFont 사용
              titleLarge: TextStyle(fontFamily: fontSettings.headerFont ?? fontSettings.bodyFont ?? 'SJ세종고딕'),
              titleMedium: TextStyle(fontFamily: fontSettings.headerFont ?? fontSettings.bodyFont ?? 'SJ세종고딕'),
              titleSmall: TextStyle(fontFamily: fontSettings.headerFont ?? fontSettings.bodyFont ?? 'SJ세종고딕'),
              // Body 스타일 (본문) - bodyFont 사용
              bodyLarge: TextStyle(fontFamily: fontSettings.bodyFont ?? 'SJ세종고딕'),
              bodyMedium: TextStyle(fontFamily: fontSettings.bodyFont ?? 'SJ세종고딕'),
              bodySmall: TextStyle(fontFamily: fontSettings.bodyFont ?? 'SJ세종고딕'),
              // Label 스타일 (라벨) - bodyFont 사용
              labelLarge: TextStyle(fontFamily: fontSettings.bodyFont ?? 'SJ세종고딕'),
              labelMedium: TextStyle(fontFamily: fontSettings.bodyFont ?? 'SJ세종고딕'),
              labelSmall: TextStyle(fontFamily: fontSettings.bodyFont ?? 'SJ세종고딕'),
            ),
          ),
          home: const SetupPage(),
        );
      }
    );
  }
}
