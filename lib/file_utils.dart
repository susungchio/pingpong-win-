import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FontSettings {
  final String? titleFont;
  final String? headerFont;
  final String? bodyFont;
  FontSettings({this.titleFont, this.headerFont, this.bodyFont});
  Map<String, dynamic> toJson() => {'titleFont': titleFont, 'headerFont': headerFont, 'bodyFont': bodyFont};
  factory FontSettings.fromJson(Map<String, dynamic> json) => FontSettings(
    titleFont: json['titleFont'], headerFont: json['headerFont'], bodyFont: json['bodyFont'],
  );
}

final ValueNotifier<FontSettings> appFontNotifier = ValueNotifier(FontSettings());
final ValueNotifier<Set<String>> eventUncheckedIdsNotifier = ValueNotifier({});
final ValueNotifier<String?> systemAdminPasswordNotifier = ValueNotifier(null);

class FileUtils {
  static String _currentBaseDir = 'C:/pingpong_app_data';

  // path_config.json 파일 위치 결정 (개발 모드와 패키지 모드 모두 지원)
  static Future<File> _getPathConfigFile() async {
    try {
      // 1. 패키지 모드: exe 파일과 같은 디렉토리에 저장
      if (Platform.isWindows) {
        final exePath = File(Platform.resolvedExecutable).parent.path;
        final exeFile = File(Platform.resolvedExecutable);
        
        // exe 파일이 실제 실행 파일인지 확인 (개발 모드가 아닌 경우)
        // 개발 모드에서는 dart.exe나 flutter_tools.snapshot을 가리킬 수 있음
        if (exeFile.path.toLowerCase().endsWith('.exe') && 
            !exeFile.path.toLowerCase().contains('dart.exe') &&
            !exeFile.path.toLowerCase().contains('flutter')) {
          // 실제 exe 파일인 경우, exe 파일과 같은 디렉토리에 저장
          return File(p.join(exePath, 'path_config.json'));
        }
      }
      
      // 2. 개발 모드 또는 일반적인 경우: 사용자 문서 디렉토리에 저장
      // 이렇게 하면 개발 모드와 패키지 모드 모두에서 일관되게 동작
      final documentsDir = await getApplicationDocumentsDirectory();
      return File(p.join(documentsDir.path, 'table_tennis_path_config.json'));
    } catch (e) {
      // 오류 발생 시 기본 위치 사용 (exe 파일 디렉토리)
      final exePath = File(Platform.resolvedExecutable).parent.path;
      return File(p.join(exePath, 'path_config.json'));
    }
  }

  static Future<void> initConfig() async {
    try {
      final file = await _getPathConfigFile();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        _currentBaseDir = data['baseDir'] ?? 'C:/pingpong_app_data';
      }
    } catch (_) {}
  }

  static Future<void> setBaseDir(String newPath) async {
    _currentBaseDir = newPath;
    final file = await _getPathConfigFile();
    await file.writeAsString(jsonEncode({'baseDir': newPath}));
  }

  static String get currentBaseDir => _currentBaseDir;

  static Future<String> getDataDirPath() async {
    final dataDir = Directory(p.join(_currentBaseDir, 'data'));
    if (!await dataDir.exists()) await dataDir.create(recursive: true);
    return dataDir.path;
  }

  static Future<String> getFontsDirPath() async {
    final fontDir = Directory(p.join(_currentBaseDir, 'fonts'));
    if (!await fontDir.exists()) await fontDir.create(recursive: true);
    return fontDir.path;
  }

  static Future<File> getPasswordFile() async {
    final dataPath = await getDataDirPath();
    return File(p.join(dataPath, 'system_admin_password.json'));
  }

  static Future<String> getAdminPassword() async {
    final file = await getPasswordFile();
    if (await file.exists()) {
      try {
        final contents = await file.readAsString();
        final data = jsonDecode(contents);
        final pw = data['password'] ?? '1234';
        systemAdminPasswordNotifier.value = pw;
        return pw;
      } catch (_) { return '1234'; }
    }
    return '1234';
  }

  static Future<void> setAdminPassword(String newPassword) async {
    final file = await getPasswordFile();
    await file.writeAsString(jsonEncode({'password': newPassword}));
    systemAdminPasswordNotifier.value = newPassword;
  }

  static Future<void> saveFontSettings(FontSettings settings) async {
    final dataPath = await getDataDirPath();
    final file = File(p.join(dataPath, 'font_settings.json'));
    await file.writeAsString(jsonEncode(settings.toJson()));
  }

  static Future<void> loadFontSettings() async {
    try {
      final dataPath = await getDataDirPath();
      final file = File(p.join(dataPath, 'font_settings.json'));
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        appFontNotifier.value = FontSettings.fromJson(data);
      }
    } catch (_) {}
  }

  static Future<void> saveEventDisplayChecked(Set<String> uncheckedIds) async {
    final dataPath = await getDataDirPath();
    final file = File(p.join(dataPath, 'event_display_settings.json'));
    await file.writeAsString(jsonEncode({'uncheckedIds': uncheckedIds.toList()}));
  }

  static Future<void> loadEventDisplaySettings() async {
    try {
      final dataPath = await getDataDirPath();
      final file = File(p.join(dataPath, 'event_display_settings.json'));
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        final List<dynamic> ids = data['uncheckedIds'] ?? [];
        eventUncheckedIdsNotifier.value = Set<String>.from(ids.map((e) => e.toString()));
      }
    } catch (_) {}
  }
}

Future<void> saveFontSettings(FontSettings settings) => FileUtils.saveFontSettings(settings);
Future<void> saveEventDisplayChecked(Set<String> uncheckedIds) => FileUtils.saveEventDisplayChecked(uncheckedIds);
Future<void> saveSystemAdminPassword(String pwd) => FileUtils.setAdminPassword(pwd);
