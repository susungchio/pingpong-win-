import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'models.dart';
import 'database_service.dart';
import 'file_utils.dart';

mixin SetupLogicMixin<T extends StatefulWidget> on State<T> {
  final uuid = const Uuid();
  final titleController = TextEditingController(text: '새 탁구 대회');
  final List<TournamentEvent> events = [];
  int selectedEventIdx = 0;
  String? currentFileName;
  
  List<String> presetsLeft = [];
  List<String> presetsRight = [];

  final dbService = DatabaseService();

  TournamentEvent? get currentEvent => events.isNotEmpty && selectedEventIdx < events.length ? events[selectedEventIdx] : null;

  Future<void> initSetupData() async {
    await loadPresets();
  }

  // --- 중복 데이터 파일 관리 ---
  Future<File> _getDuplicationFile() async {
    final dataPath = await FileUtils.getDataDirPath();
    return File(p.join(dataPath, 'duplication.json'));
  }

  Future<void> saveDuplicates(List<MasterPlayer> newDuplicates) async {
    try {
      final file = await _getDuplicationFile();
      List<MasterPlayer> existing = [];
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> json = jsonDecode(content);
        existing = json.map((e) => MasterPlayer.fromJson(e)).toList();
      }
      for (var p in newDuplicates) {
        if (!existing.any((e) => e.uniqueKey == p.uniqueKey)) existing.add(p);
      }
      await file.writeAsString(jsonEncode(existing.map((e) => e.toJson()).toList()));
    } catch (e) { debugPrint('Save duplicates error: $e'); }
  }

  Future<List<MasterPlayer>> loadDuplicates() async {
    try {
      final file = await _getDuplicationFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final List<dynamic> json = jsonDecode(content);
      return json.map((e) => MasterPlayer.fromJson(e)).toList();
    } catch (e) { return []; }
  }

  Future<void> clearDuplicatesFile() async {
    final file = await _getDuplicationFile();
    if (await file.exists()) await file.delete();
  }

  // --- 대량 데이터 등록 ---
  Future<Map<String, int>> importRawPlayerData(String rawText) async {
    List<MasterPlayer> playersToProcess = _parseBulkPlayerRecords(rawText);
    if (playersToProcess.isEmpty) return {'added': 0, 'updated': 0, 'duplicates': 0};

    final res = await dbService.insertMasterPlayers(playersToProcess);
    if (res['duplicates']! > 0) {
      List<MasterPlayer> dups = [];
      for (var p in playersToProcess) {
        final exist = await dbService.searchPlayersExact(p.name, p.affiliation);
        if (exist.isNotEmpty) dups.add(p);
      }
      await saveDuplicates(dups);
    }
    return res;
  }

  List<MasterPlayer> _parseBulkPlayerRecords(String rawText) {
    List<MasterPlayer> result = [];
    if (rawText.trim().isEmpty) return result;
    final recordEndPattern = RegExp(r'\d+(?:\.\d+)?점');
    int start = 0;
    for (final match in recordEndPattern.allMatches(rawText)) {
      final block = rawText.substring(start, match.end).trim();
      start = match.end;
      if (block.isEmpty) continue;
      final player = _parseOneRecord(block);
      if (player != null) result.add(player);
    }
    if (start < rawText.length) {
      final block = rawText.substring(start).trim();
      if (block.isNotEmpty) {
        final player = _parseOneRecord(block);
        if (player != null) result.add(player);
      }
    }
    return result;
  }

  MasterPlayer? _parseOneRecord(String block) {
    final lines = block.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (lines.length < 4) return _parseOneRecordByTokens(block);
    try {
      final firstParts = lines[0].split('\t').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      final number = firstParts.isNotEmpty ? firstParts[0] : '';
      final city = firstParts.length > 1 ? firstParts[1] : '';
      final affiliation = lines[1];
      final name = lines[2];
      final lastParts = lines[3].split('\t').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (lastParts.length < 3) return _parseOneRecordByTokens(block);
      final gender = lastParts[0];
      final tier = lastParts[1];
      final points = lastParts.last;
      if (!RegExp(r'^\d+(\.\d+)?점$').hasMatch(points)) return _parseOneRecordByTokens(block);
      if (name.isEmpty) return null;
      return MasterPlayer(playerNumber: number, city: city, affiliation: affiliation, name: name, gender: gender, tier: tier, points: points);
    } catch (_) { return _parseOneRecordByTokens(block); }
  }

  MasterPlayer? _parseOneRecordByTokens(String block) {
    final tokens = block.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final pointsRegex = RegExp(r'^\d+(\.\d+)?점$');
    if (tokens.length < 5) return null;
    if (!pointsRegex.hasMatch(tokens.last)) return null;
    try {
      final pNum = tokens[0]; final city = tokens[1]; final points = tokens.last;
      int genderIdx = -1;
      for (int j = 2; j < tokens.length; j++) { if (tokens[j] == '남' || tokens[j] == '여') { genderIdx = j; break; } }
      if (genderIdx < 0) return null;
      final name = tokens[genderIdx - 1];
      String aff = tokens.sublist(2, genderIdx - 1).join(' ');
      if (aff.isEmpty) aff = city;
      final tierTail = tokens.sublist(genderIdx + 1, tokens.length - 1).join(' ');
      final tier = '${tokens[genderIdx]} $tierTail'.trim();
      return MasterPlayer(playerNumber: pNum, city: city, affiliation: aff, name: name, gender: tokens[genderIdx], tier: tier, points: points);
    } catch (_) { return null; }
  }

  // --- 프리셋 관리 ---
  Future<void> loadPresets() async {
    try {
      final dataPath = await FileUtils.getDataDirPath();
      final file = File(p.join(dataPath, 'presets_v2.json'));
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        setState(() {
          presetsLeft = List<String>.from(data['left'] ?? []);
          presetsRight = List<String>.from(data['right'] ?? []);
        });
      } else {
        setState(() {
          presetsLeft = ['남자 단식', '남자 복식', '실버부(남)', '희망부(남)'];
          presetsRight = ['여자 단식', '여자 복식', '혼합 복식', '실버부(여)', '희망부(여)'];
        });
        savePresets();
      }
    } catch (e) { debugPrint('Load presets error: $e'); }
  }

  Future<void> savePresets() async {
    try {
      final dataPath = await FileUtils.getDataDirPath();
      final file = File(p.join(dataPath, 'presets_v2.json'));
      await file.writeAsString(jsonEncode({'left': presetsLeft, 'right': presetsRight}));
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
      final dataPath = await FileUtils.getDataDirPath();
      final filePath = p.isAbsolute(currentFileName!) ? currentFileName! : p.join(dataPath, currentFileName);
      final file = File(filePath);
      await file.writeAsString(jsonString, flush: true);
    } catch (e) { debugPrint('Save error: $e'); }
  }

  Map<String, dynamic> _eventToMap(TournamentEvent e) {
    return {
      'id': e.id, 'name': e.name, 'teamSize': e.teamSize, 'groupSize': e.settings.groupSize, 
      'advancingCount': e.settings.advancingCount, 'skipGroupStage': e.settings.skipGroupStage,
      'showTierFilter': e.settings.showTierFilter, 'allowedTiers': e.settings.allowedTiers,
      'players': e.players.map((p) => {'id': p.id, 'name': p.name, 'affiliation': p.affiliation}).toList(),
      'groups': e.groups?.map((g) => {'name': g.name, 'players': g.players.map((p) => p.id).toList(), 'matches': g.matches.map((m) => _matchToMap(m)).toList()}).toList(),
      'knockoutRounds': e.knockoutRounds?.map((r) => {'name': r.name, 'matches': r.matches.map((m) => _matchToMap(m)).toList()}).toList(),
    };
  }

  Map<String, dynamic> _matchToMap(Match m) => {
    'id': m.id, 'p1Id': m.player1?.id, 'p2Id': m.player2?.id, 's1': m.score1, 's2': m.score2,
    'status': m.status.index, 'winnerId': m.winner?.id, 'nextMatchId': m.nextMatchId, 'nextMatchSlot': m.nextMatchSlot,
  };

  void afterLoadFromFile(Map<String, dynamic> data) {}

  Future<void> loadFromFile(File file) async {
    try {
      final contents = await file.readAsString();
      final data = jsonDecode(contents);
      setState(() {
        titleController.text = data['title'] ?? '';
        currentFileName = file.path;
        events.clear();
        if (data['events'] != null) { for (var eJson in data['events']) { events.add(_eventFromMap(eJson)); } }
        selectedEventIdx = 0;
        afterLoadFromFile(data);
      });
    } catch (e) { debugPrint('Load error: $e'); }
  }

  TournamentEvent _eventFromMap(Map<String, dynamic> map) {
    final List<String> allowedTiers = map['allowedTiers'] != null ? List<String>.from(map['allowedTiers'] as List) : <String>[];
    final event = TournamentEvent(id: map['id'], name: map['name'], teamSize: map['teamSize'] ?? 1, settings: TournamentSettings(groupSize: map['groupSize'] ?? 3, advancingCount: map['advancingCount'] ?? 2, skipGroupStage: map['skipGroupStage'] ?? false, showTierFilter: map['showTierFilter'] ?? false, allowedTiers: allowedTiers));
    if (map['players'] != null) { event.players.addAll((map['players'] as List).map((p) => Player(id: p['id'], name: p['name'], affiliation: p['affiliation']))); }
    Player? findP(String? id) => id == null ? null : event.players.firstWhere((p) => p.id == id, orElse: () => Player(id: id, name: '알수없음', affiliation: ''));
    if (map['groups'] != null) { event.groups = (map['groups'] as List).map((gJson) => Group(name: gJson['name'], players: (gJson['players'] as List).map((id) => findP(id)!).toList(), matches: (gJson['matches'] as List).map((mJson) => _matchFromMap(mJson, findP)).toList())).toList(); }
    if (map['knockoutRounds'] != null) { event.knockoutRounds = (map['knockoutRounds'] as List).map((rJson) => Round(name: rJson['name'], matches: (rJson['matches'] as List).map((mJson) => _matchFromMap(mJson, findP)).toList())).toList(); }
    return event;
  }

  Match _matchFromMap(Map<String, dynamic> m, Player? Function(String?) findP) => Match(id: m['id'], player1: findP(m['p1Id']), player2: findP(m['p2Id']), score1: m['s1'], score2: m['s2'], status: MatchStatus.values[m['status']], winner: findP(m['winnerId']), nextMatchId: m['nextMatchId'], nextMatchSlot: m['nextMatchSlot']);

  void showAddEventDialog(BuildContext context) {
    final eventNameController = TextEditingController();
    int selectedTeamSize = 1;
    bool addToLeft = false; bool addToRight = false;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // 리스트 등록만 처리하는 함수
          void handleListRegistration(String name) {
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('종목 이름을 입력해주세요.')));
              return;
            }
            String trimmedName = name.trim();
            if (!addToLeft && !addToRight) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('리스트 등록 그룹을 선택해주세요.')));
              return;
            }
            setDialogState(() {
              if (addToLeft && !presetsLeft.contains(trimmedName)) presetsLeft.add(trimmedName);
              if (addToRight && !presetsRight.contains(trimmedName)) presetsRight.add(trimmedName);
            });
            savePresets();
            eventNameController.clear();
            setDialogState(() { addToLeft = false; addToRight = false; });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('자주 쓰는 종목 리스트에 등록되었습니다.')));
          }

          Widget buildPresetList(List<String> list, bool isLeft) {
            return Container(
              height: 300, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
              child: ListView.separated(
                itemCount: list.length, separatorBuilder: (ctx, i) => const Divider(height: 1),
                itemBuilder: (ctx, idx) => ListTile(
                  dense: true, title: Text(list[idx]),
                  trailing: IconButton(icon: const Icon(Icons.remove_circle_outline, size: 16), onPressed: () { setDialogState(() => list.removeAt(idx)); savePresets(); }),
                  onTap: () {
                    if (events.any((e) => e.name.trim() == list[idx].trim())) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('같은 이름의 종목이 이미 존재합니다.'))); return; }
                    setState(() { events.add(TournamentEvent(id: uuid.v4(), name: list[idx], teamSize: selectedTeamSize)); selectedEventIdx = events.length - 1; });
                    saveData(); Navigator.pop(context);
                  },
                ),
              ),
            );
          }

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: SizedBox(
              width: 600,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 상단바 - #1a535c 색상
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF1a535c),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '종목 추가 및 관리',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  // 내용 영역
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        TextField(
                          controller: eventNameController,
                          decoration: const InputDecoration(
                            labelText: '종목 이름 직접 입력',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Text('리스트 등록:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            const SizedBox(width: 8),
                            Checkbox(
                              value: addToLeft,
                              onChanged: (v) => setDialogState(() => addToLeft = v!),
                            ),
                            const Text('좌'),
                            const SizedBox(width: 16),
                            Checkbox(
                              value: addToRight,
                              onChanged: (v) => setDialogState(() => addToRight = v!),
                            ),
                            const Text('우'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          value: selectedTeamSize,
                          decoration: const InputDecoration(
                            labelText: '인원 구성',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          ),
                          items: [1, 2, 3, 4, 5].map((n) => DropdownMenuItem(
                            value: n,
                            child: Text(n == 1 ? '개인전' : '$n인 단체/복식'),
                          )).toList(),
                          onChanged: (v) => setDialogState(() => selectedTeamSize = v!),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () => handleListRegistration(eventNameController.text),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1a535c),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('리스트 등록', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        const Divider(height: 40),
                        const Text(
                          '자주 쓰는 종목 (클릭 시 추가)',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: Column(children: [
                            const Text('왼쪽 그룹', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            buildPresetList(presetsLeft, true),
                          ])),
                          const SizedBox(width: 10),
                          Expanded(child: Column(children: [
                            const Text('오른쪽 그룹', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            buildPresetList(presetsRight, false),
                          ])),
                        ]),
                      ]),
                    ),
                  ),
                  // 하단바 - #1a535c 색상
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF1a535c),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          child: const Text('닫기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> pickExcelFile() async {
    if (currentEvent == null) return;
    try {
      // [수정] 윈도우에서 안정적으로 동작하도록 withData: false로 설정하고 file.path 사용
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom, 
        allowedExtensions: ['xlsx', 'xls'],
        withData: false, // 윈도우에서는 false가 더 안정적
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      // [수정] 윈도우에서는 file.path를 우선 사용
      Uint8List? bytes;
      if (file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      } else if (file.bytes != null) {
        bytes = file.bytes;
      }
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('파일을 읽을 수 없습니다.'))
          );
        }
        return;
      }
      var excel = excel_lib.Excel.decodeBytes(bytes);
      List<String> sheetNames = excel.tables.keys.toList();
      if (!mounted) return;
      String? selectedSheet = await showDialog<String>(context: context, builder: (context) => AlertDialog(title: const Text('가져올 시트(탭) 선택'), content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: sheetNames.length, itemBuilder: (context, index) { return Card(child: ListTile(leading: const Icon(Icons.table_view, color: Colors.green), title: Text(sheetNames[index]), onTap: () => Navigator.pop(context, sheetNames[index]))); })), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소'))]));
      if (selectedSheet != null) {
        List<Player> newPlayers = [];
        var table = excel.tables[selectedSheet];
        if (table != null) {
          int teamSize = currentEvent!.teamSize;
          for (var row in table.rows.skip(1)) {
            if (row.isEmpty) continue;
            String name = ""; String affiliation = "";
            if (teamSize > 1) {
              // [단체전] A컬럼: 팀명/소속, B컬럼~: 선수 이름(부수)
              affiliation = row[0]?.value?.toString().trim() ?? '개인';
              List<String> memberNames = [];
              for (int i = 1; i <= teamSize; i++) {
                if (row.length > i && row[i] != null) {
                  String mName = row[i]!.value.toString().trim();
                  if (mName.isNotEmpty) memberNames.add(mName);
                }
              }
              name = memberNames.join(', ');
            } else {
              // [개인전] A컬럼: 이름, B컬럼: 소속, C컬럼: 부수 (선택사항)
              String nameOnly = row[0]?.value?.toString().trim() ?? "";
              affiliation = (row.length >= 2 && row[1] != null) ? row[1]!.value.toString().trim() : '개인';
              String tier = (row.length >= 3 && row[2] != null) ? row[2]!.value.toString().trim() : "";
              
              // 부수가 있으면 "이름 (부수)" 형식으로, 없으면 이름만
              if (tier.isNotEmpty) {
                name = "$nameOnly ($tier)";
              } else {
                name = nameOnly;
              }
            }
            if (name.isEmpty) continue;
            if (affiliation.isEmpty) affiliation = '개인';
            newPlayers.add(Player(id: uuid.v4(), name: name, affiliation: affiliation));
          }
        }
        if (newPlayers.isNotEmpty) { setState(() { currentEvent!.players.addAll(newPlayers); currentEvent!.groups = null; }); saveData(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('[$selectedSheet] 시트에서 ${newPlayers.length}개 팀/선수를 추가했습니다.'))); }
      }
    } catch (e) { debugPrint('Excel Import Error: $e'); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('엑셀 파일을 읽는 중 오류가 발생했습니다.'))); }
  }
}
