import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:file_picker/file_picker.dart';
import 'models.dart';
import 'database_service.dart';

mixin SetupLogicMixin<T extends StatefulWidget> on State<T> {
  final uuid = const Uuid();
  final titleController = TextEditingController(text: '새 탁구 대회');
  final List<TournamentEvent> events = [];
  int selectedEventIdx = 0;
  String? currentFileName;
  
  List<String> presetsLeft = [];
  List<String> presetsRight = [];

  final dbService = DatabaseService();

  TournamentEvent? get currentEvent => events.isNotEmpty ? events[selectedEventIdx] : null;

  Future<void> initSetupData() async {
    await loadPresets();
  }

  // --- 중복 데이터 파일 관리 ---
  Future<File> _getDuplicationFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/duplication.json');
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

  /// 레코드 구분: "0~9 문자형식+점" (예: 0.625점, 0점). 필드: 번호, 지역, 동호회, 이름, 성별, 부수, 누적점수.
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

  /// 대량 데이터를 "숫자+점"으로 레코드 구분 후, 줄 단위로 번호/지역/동호회/이름/성별/부수/누적점수 파싱.
  List<MasterPlayer> _parseBulkPlayerRecords(String rawText) {
    List<MasterPlayer> result = [];
    if (rawText.trim().isEmpty) return result;

    // 레코드 끝 패턴: 숫자(소수 가능)+"점" (예: 0.625점, 0점)
    final recordEndPattern = RegExp(r'\d+(?:\.\d+)?점');
    int start = 0;
    for (final match in recordEndPattern.allMatches(rawText)) {
      final block = rawText.substring(start, match.end).trim();
      start = match.end;
      if (block.isEmpty) continue;

      final player = _parseOneRecord(block);
      if (player != null) result.add(player);
    }
    // 마지막에 레코드 끝 없이 남은 텍스트가 있으면 한 건으로 시도
    if (start < rawText.length) {
      final block = rawText.substring(start).trim();
      if (block.isNotEmpty) {
        final player = _parseOneRecord(block);
        if (player != null) result.add(player);
      }
    }

    return result;
  }

  /// 한 명 분량 문자열에서 번호, 지역, 동호회, 이름, 성별, 부수, 누적점수 추출.
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
      return MasterPlayer(
        playerNumber: number,
        city: city,
        affiliation: affiliation,
        name: name,
        gender: gender,
        tier: tier,
        points: points,
      );
    } catch (_) {
      return _parseOneRecordByTokens(block);
    }
  }

  /// 줄 단위 파싱 실패 시 기존 방식: 공백/탭으로 토큰 나누고 "숫자+점"으로 레코드 구분.
  MasterPlayer? _parseOneRecordByTokens(String block) {
    final tokens = block.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final pointsRegex = RegExp(r'^\d+(\.\d+)?점$');
    if (tokens.length < 5) return null;
    if (!pointsRegex.hasMatch(tokens.last)) return null;

    try {
      final pNum = tokens[0];
      final city = tokens[1];
      final points = tokens.last;
      int genderIdx = -1;
      for (int j = 2; j < tokens.length; j++) {
        if (tokens[j] == '남' || tokens[j] == '여') {
          genderIdx = j;
          break;
        }
      }
      if (genderIdx < 0) return null;

      final name = tokens[genderIdx - 1];
      String aff = tokens.sublist(2, genderIdx - 1).join(' ');
      if (aff.isEmpty) aff = city;
      final tierTail = tokens.sublist(genderIdx + 1, tokens.length - 1).join(' ');
      final tier = '${tokens[genderIdx]} $tierTail'.trim();

      return MasterPlayer(
        playerNumber: pNum,
        city: city,
        affiliation: aff,
        name: name,
        gender: tokens[genderIdx],
        tier: tier,
        points: points,
      );
    } catch (_) {
      return null;
    }
  }

  // --- 나머지 기존 로직 유지 ---
  Future<void> loadPresets() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/presets_v2.json');
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
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/presets_v2.json');
      await file.writeAsString(jsonEncode({'left': presetsLeft, 'right': presetsRight}));
    } catch (e) { debugPrint('Save presets error: $e'); }
  }

  /// 저장 시 포함할 체크된 경기종목 id 목록 (상태에서 override)
  List<String> get checkedEventIdsForSave => [];

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
      'id': e.id, 'name': e.name, 'teamSize': e.teamSize, 'groupSize': e.settings.groupSize, 
      'advancingCount': e.settings.advancingCount, 'skipGroupStage': e.settings.skipGroupStage,
      'showTierFilter': e.settings.showTierFilter, 'allowedTiers': e.settings.allowedTiers,
      'players': e.players.map((p) => {'id': p.id, 'name': p.name, 'affiliation': p.affiliation}).toList(),
      'groups': e.groups?.map((g) => {'name': g.name, 'players': g.players.map((p) => p.id).toList(), 'matches': g.matches.map((m) => _matchToMap(m)).toList()}).toList(),
      'knockoutRounds': e.knockoutRounds?.map((r) => {'name': r.name, 'matches': r.matches.map((m) => _matchToMap(m)).toList()}).toList(),
    };
  }

  Map<String, dynamic> _matchToMap(Match m) {
    return {
      'id': m.id, 'p1Id': m.player1?.id, 'p2Id': m.player2?.id, 's1': m.score1, 's2': m.score2,
      'status': m.status.index, 'winnerId': m.winner?.id, 'nextMatchId': m.nextMatchId, 'nextMatchSlot': m.nextMatchSlot,
    };
  }

  /// 로드 후 체크된 종목 id 복원 (상태에서 override)
  void afterLoadFromFile(Map<String, dynamic> data) {}

  Future<void> loadFromFile(File file) async {
    try {
      final contents = await file.readAsString();
      final data = jsonDecode(contents);
      setState(() {
        titleController.text = data['title'] ?? '';
        currentFileName = file.path.split(Platform.pathSeparator).last;
        events.clear();
        if (data['events'] != null) { for (var eJson in data['events']) { events.add(_eventFromMap(eJson)); } }
        selectedEventIdx = 0;
        afterLoadFromFile(data);
      });
    } catch (e) { debugPrint('Load error: $e'); }
  }

  TournamentEvent _eventFromMap(Map<String, dynamic> map) {
    final List<String> allowedTiers = map['allowedTiers'] != null
        ? List<String>.from(map['allowedTiers'] as List)
        : <String>[];
    final event = TournamentEvent(
      id: map['id'],
      name: map['name'],
      teamSize: map['teamSize'] ?? 1,
      settings: TournamentSettings(
        groupSize: map['groupSize'] ?? 3,
        advancingCount: map['advancingCount'] ?? 2,
        skipGroupStage: map['skipGroupStage'] ?? false,
        showTierFilter: map['showTierFilter'] ?? false,
        allowedTiers: allowedTiers,
      ),
    );
    if (map['players'] != null) { event.players.addAll((map['players'] as List).map((p) => Player(id: p['id'], name: p['name'], affiliation: p['affiliation']))); }
    Player? findP(String? id) => id == null ? null : event.players.firstWhere((p) => p.id == id, orElse: () => Player(id: id, name: '알수없음', affiliation: ''));
    if (map['groups'] != null) { event.groups = (map['groups'] as List).map((gJson) => Group(name: gJson['name'], players: (gJson['players'] as List).map((id) => findP(id)!).toList(), matches: (gJson['matches'] as List).map((mJson) => _matchFromMap(mJson, findP)).toList())).toList(); }
    if (map['knockoutRounds'] != null) { event.knockoutRounds = (map['knockoutRounds'] as List).map((rJson) => Round(name: rJson['name'], matches: (rJson['matches'] as List).map((mJson) => _matchFromMap(mJson, findP)).toList())).toList(); }
    return event;
  }

  Match _matchFromMap(Map<String, dynamic> m, Player? Function(String?) findP) {
    return Match(id: m['id'], player1: findP(m['p1Id']), player2: findP(m['p2Id']), score1: m['s1'], score2: m['s2'], status: MatchStatus.values[m['status']], winner: findP(m['winnerId']), nextMatchId: m['nextMatchId'], nextMatchSlot: m['nextMatchSlot']);
  }

  void showAddEventDialog(BuildContext context) {
    final eventNameController = TextEditingController();
    int selectedTeamSize = 1;
    bool addToLeft = false;
    bool addToRight = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void handleAddAction(String name, int teamSize) {
            if (name.isEmpty) return;
            String trimmedName = name.trim();
            if (addToLeft || addToRight) {
              setDialogState(() {
                if (addToLeft && !presetsLeft.contains(trimmedName)) presetsLeft.add(trimmedName);
                if (addToRight && !presetsRight.contains(trimmedName)) presetsRight.add(trimmedName);
              });
              savePresets();
              eventNameController.clear();
              setDialogState(() { addToLeft = false; addToRight = false; });
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('자주 쓰는 종목 리스트에 등록되었습니다.'), duration: Duration(seconds: 1)));
              return;
            }
            if (events.any((e) => e.name == trimmedName && e.teamSize == teamSize)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이미 동일한 종목이 존재합니다.'))); return; }
            setState(() { events.add(TournamentEvent(id: uuid.v4(), name: trimmedName, teamSize: teamSize)); selectedEventIdx = events.length - 1; });
            saveData();
            Navigator.pop(context);
          }

          Widget buildPresetList(List<String> list, bool isLeft) {
            // ListView.separated 대신 Column + SingleChildScrollView 사용: intrinsic dimensions 계산 문제 방지
            return Container(
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
              child: SingleChildScrollView(
                child: Column(
                  // mainAxisSize.min 제거: intrinsic dimensions 계산 문제 방지
                  children: [
                    for (int idx = 0; idx < list.length; idx++) ...[
                      ListTile(
                        dense: true,
                        title: Text(list[idx], style: const TextStyle(fontSize: 14)),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline, size: 16, color: Colors.redAccent),
                          onPressed: () {
                            setDialogState(() => list.removeAt(idx));
                            savePresets();
                          },
                        ),
                        onTap: () {
                          if (events.any((e) => e.name == list[idx] && e.teamSize == selectedTeamSize)) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이미 동일한 종목이 존재합니다.')));
                            return;
                          }
                          setState(() {
                            events.add(TournamentEvent(id: uuid.v4(), name: list[idx], teamSize: selectedTeamSize));
                            selectedEventIdx = events.length - 1;
                          });
                          saveData();
                          Navigator.pop(context);
                        },
                        hoverColor: isLeft ? Colors.blue.withOpacity(0.05) : Colors.green.withOpacity(0.05),
                      ),
                      if (idx < list.length - 1) const Divider(height: 1),
                    ],
                  ],
                ),
              ),
            );
          }

          // AlertDialog 대신 Dialog 사용: intrinsic dimensions 계산 문제 방지
          return Dialog(
            child: ConstrainedBox(
              // 명시적인 크기 제약: Windows 환경 대응
              constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 800),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 제목 영역
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1A535C),
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.settings_suggest, color: Colors.white),
                        SizedBox(width: 12),
                        Text('종목 추가 및 관리', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  // 내용 영역
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('종목 직접 입력 및 추가', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A535C))),
                          const SizedBox(height: 16),
                          // Row에 명시적인 크기 제약 추가
                          LayoutBuilder(
                            builder: (context, constraints) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      children: [
                                        TextField(
                                          controller: eventNameController,
                                          decoration: const InputDecoration(labelText: '종목 이름 입력', border: OutlineInputBorder(), hintText: '예: 남자 60대부'),
                                          onSubmitted: (v) => handleAddAction(v, selectedTeamSize),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Text('자주 쓰는 종목에 추가:', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                            const SizedBox(width: 12),
                                            FilterChip(
                                              label: const Text('왼쪽 그룹'),
                                              selected: addToLeft,
                                              onSelected: (v) => setDialogState(() => addToLeft = v),
                                              selectedColor: Colors.blue.shade100,
                                            ),
                                            const SizedBox(width: 8),
                                            FilterChip(
                                              label: const Text('오른쪽 그룹'),
                                              selected: addToRight,
                                              onSelected: (v) => setDialogState(() => addToRight = v),
                                              selectedColor: Colors.green.shade100,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    flex: 2,
                                    child: DropdownButtonFormField<int>(
                                      value: selectedTeamSize,
                                      decoration: const InputDecoration(labelText: '인원 구성', border: OutlineInputBorder()),
                                      items: [1, 2, 3, 4, 5].map((n) => DropdownMenuItem(value: n, child: Text(n == 1 ? '개인전' : '$n인 단체/복식'))).toList(),
                                      onChanged: (v) => setDialogState(() => selectedTeamSize = v!),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // ElevatedButton의 minimumSize에서 double.infinity 제거
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () => handleAddAction(eventNameController.text, selectedTeamSize),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: (addToLeft || addToRight) ? Colors.blueGrey : const Color(0xFF1A535C),
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(0, 55), // double.infinity 대신 0 사용
                                      ),
                                      child: Text((addToLeft || addToRight) ? '리스트 등록' : '종목 추가', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          if (addToLeft || addToRight)
                            const Text('※ 그룹 체크 시 리스트에만 등록되며 대회에는 추가되지 않습니다.', style: TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 40),
                          const Text('자주 쓰는 종목 선택 (클릭 시 즉시 추가)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A535C))),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 8),
                                      child: Text('◀ 왼쪽 그룹', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                                    ),
                                    SizedBox(height: 400, child: buildPresetList(presetsLeft, true)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 8),
                                      child: Text('오른쪽 그룹 ▶', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                    ),
                                    SizedBox(height: 400, child: buildPresetList(presetsRight, false)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 하단 버튼 영역
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('닫기'),
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
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls'], withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      Uint8List? bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null) return;
      var excel = excel_lib.Excel.decodeBytes(bytes);
      List<String> sheetNames = excel.tables.keys.toList();
      if (!mounted) return;
      String? selectedSheet = await showDialog<String>(context: context, builder: (context) => AlertDialog(title: const Text('가져올 시트(탭) 선택', style: TextStyle(fontWeight: FontWeight.bold)), content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: sheetNames.length, itemBuilder: (context, index) { return Card(child: ListTile(leading: const Icon(Icons.table_view, color: Colors.green), title: Text(sheetNames[index]), onTap: () => Navigator.pop(context, sheetNames[index]))); })), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소'))]));
      if (selectedSheet != null) {
        List<Player> newPlayers = [];
        var table = excel.tables[selectedSheet];
        if (table != null) {
          int teamSize = currentEvent!.teamSize;
          for (var row in table.rows.skip(1)) {
            if (row.isEmpty) continue;
            String name = ""; String affiliation = "";
            if (teamSize > 1) {
              affiliation = row[0]?.value?.toString().trim() ?? '개인';
              List<String> memberNames = [];
              for (int i = 1; i <= teamSize; i++) { if (row.length > i && row[i] != null) { String mName = row[i]!.value.toString().trim(); if (mName.isNotEmpty) memberNames.add(mName); } }
              name = memberNames.join(', ');
            } else {
              name = row[0]?.value?.toString().trim() ?? "";
              affiliation = (row.length >= 2 && row[1] != null) ? row[1]!.value.toString().trim() : '개인';
            }
            if (name.isEmpty) continue;
            if (affiliation.isEmpty) affiliation = '개인';
            newPlayers.add(Player(id: uuid.v4(), name: name, affiliation: affiliation));
          }
        }
        if (newPlayers.isNotEmpty) { setState(() { currentEvent!.players.addAll(newPlayers); currentEvent!.groups = null; }); saveData(); if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('[$selectedSheet] 시트에서 ${newPlayers.length}개 팀/선수를 추가했습니다.'))); } }
      }
    } catch (e) { debugPrint('Excel Import Error: $e'); if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('엑셀 파일을 읽는 중 오류가 발생했습니다.'))); } }
  }
}
