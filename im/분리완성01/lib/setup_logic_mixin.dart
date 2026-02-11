import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:file_picker/file_picker.dart';
import 'models.dart';
import 'tournament_logic.dart';

mixin SetupLogicMixin<T extends StatefulWidget> on State<T> {
  final uuid = const Uuid();
  final titleController = TextEditingController(text: '새 탁구 대회');
  final List<TournamentEvent> events = [];
  int selectedEventIdx = 0;
  String? currentFileName;
  List<String> presets = [];

  TournamentEvent? get currentEvent => events.isNotEmpty ? events[selectedEventIdx] : null;

  // 공통 초기화 로직
  Future<void> initSetupData() async {
    await loadPresets();
  }

  Future<void> loadPresets() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/presets.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        setState(() { presets = List<String>.from(jsonDecode(content)); });
      } else {
        setState(() {
          presets = ['남자 단식', '여자 단식', '남자 복식', '여자 복식', '혼합 복식', '실버부', '희망부'];
        });
        savePresets();
      }
    } catch (e) { debugPrint('Load presets error: $e'); }
  }

  Future<void> savePresets() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/presets.json');
      await file.writeAsString(jsonEncode(presets));
    } catch (e) { debugPrint('Save presets error: $e'); }
  }

  Future<void> saveData() async {
    if (currentFileName == null) return;
    try {
      final data = {
        'title': titleController.text,
        'events': events.map((e) => _eventToMap(e)).toList(),
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      final jsonString = jsonEncode(data);
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$currentFileName');
      await file.writeAsString(jsonString, flush: true);
    } catch (e) { debugPrint('Save error: $e'); }
  }

  Map<String, dynamic> _eventToMap(TournamentEvent e) {
    return {
      'id': e.id, 'name': e.name, 'teamSize': e.teamSize, 
      'groupSize': e.settings.groupSize, 'advancingCount': e.settings.advancingCount,
      'players': e.players.map((p) => {'id': p.id, 'name': p.name, 'affiliation': p.affiliation}).toList(),
      'groups': e.groups?.map((g) => {
        'name': g.name, 'players': g.players.map((p) => p.id).toList(), 
        'matches': g.matches.map((m) => _matchToMap(m)).toList(),
      }).toList(),
    };
  }

  Map<String, dynamic> _matchToMap(Match m) {
    return {
      'id': m.id, 'p1Id': m.player1?.id, 'p2Id': m.player2?.id, 's1': m.score1, 's2': m.score2,
      'status': m.status.index, 'winnerId': m.winner?.id, 'nextMatchId': m.nextMatchId, 'nextMatchSlot': m.nextMatchSlot,
    };
  }

  Future<void> loadFromFile(File file) async {
    try {
      final contents = await file.readAsString();
      final data = jsonDecode(contents);
      setState(() {
        titleController.text = data['title'] ?? '';
        currentFileName = file.path.split(Platform.pathSeparator).last;
        events.clear();
        if (data['events'] != null) {
          for (var eJson in data['events']) { events.add(_eventFromMap(eJson)); }
        }
        selectedEventIdx = 0;
      });
    } catch (e) { debugPrint('Load error: $e'); }
  }

  TournamentEvent _eventFromMap(Map<String, dynamic> map) {
    final event = TournamentEvent(
      id: map['id'], name: map['name'], teamSize: map['teamSize'] ?? 1,
      settings: TournamentSettings(groupSize: map['groupSize'] ?? 3, advancingCount: map['advancingCount'] ?? 2)
    );
    if (map['players'] != null) {
      event.players.addAll((map['players'] as List).map((p) => Player(id: p['id'], name: p['name'], affiliation: p['affiliation'])));
    }
    return event;
  }

  Future<void> pickExcelFile() async {
    if (currentEvent == null) return;
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls']);
      if (result == null) return;
      // ... 엑셀 로드 상세 로직 (생략 - 모바일 버전과 동일하게 이식 가능)
    } catch (e) { debugPrint('Excel error: $e'); }
  }
}
