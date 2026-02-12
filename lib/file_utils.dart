import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// 폰트 설정 모델
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

/// 전역 상태 관리 변수들
final ValueNotifier<FontSettings> appFontNotifier = ValueNotifier(FontSettings());
final ValueNotifier<Set<String>> eventUncheckedIdsNotifier = ValueNotifier({});
final ValueNotifier<String?> systemAdminPasswordNotifier = ValueNotifier(null);

class FileUtils {
  static Future<String> getDataDirPath() async {
    final exePath = File(Platform.resolvedExecutable).parent.path;
    final dataDir = Directory(p.join(exePath, 'data'));
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    return dataDir.path;
  }

  // --- 비밀번호 관리 ---
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
        systemAdminPasswordNotifier.value = pw; // 노티파이어 업데이트
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

  // --- 폰트 설정 저장/로드 ---
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

  // --- 경기 종목 표시 설정 저장/로드 ---
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

/// ProgramSettingsPage 등에서 사용하는 하위 호환용 함수들
Future<void> saveFontSettings(FontSettings settings) => FileUtils.saveFontSettings(settings);
Future<void> saveEventDisplayChecked(Set<String> uncheckedIds) => FileUtils.saveEventDisplayChecked(uncheckedIds);
Future<void> saveSystemAdminPassword(String pwd) => FileUtils.setAdminPassword(pwd);
// FontSettings 클래스는 위에서 정의함
