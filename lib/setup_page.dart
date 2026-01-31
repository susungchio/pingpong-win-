import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:excel/excel.dart' as excel_lib;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'tournament_logic.dart';
import 'group_stage_page.dart';
import 'match_sheet_page.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _uuid = const Uuid();
  final _titleController = TextEditingController(text: '새 탁구 대회');
  
  final List<TournamentEvent> _events = [];
  int _selectedEventIdx = 0;
  String? _currentFileName; 
  List<String> _presets = []; 

  final _nameController = TextEditingController();
  final _affController = TextEditingController();

  TournamentEvent? get _currentEvent => _events.isNotEmpty ? _events[_selectedEventIdx] : null;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _loadPresets(); 
  }

  Future<void> _loadPresets() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/presets.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        setState(() {
          _presets = List<String>.from(jsonDecode(content));
        });
      } else {
        setState(() {
          _presets = ['남자 단식', '여자 단식', '남자 복식', '여자 복식', '혼합 복식', '실버부', '희망부'];
        });
        _savePresets();
      }
    } catch (e) {
      debugPrint('Load presets error: $e');
    }
  }

  Future<void> _savePresets() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/presets.json');
      await file.writeAsString(jsonEncode(_presets));
    } catch (e) {
      debugPrint('Save presets error: $e');
    }
  }

  Future<void> _saveData() async {
    if (_currentFileName == null) return;
    try {
      final title = _titleController.text;
      final eventsData = _events.map((e) => _eventToMap(e)).toList();
      final data = {
        'title': title,
        'events': eventsData,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      final jsonString = await compute(jsonEncode, data);
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_currentFileName');
      await file.writeAsString(jsonString, flush: true);
    } catch (e) {
      debugPrint('Save error: $e');
    }
  }

  Future<void> _handleInitialSave() async {
    if (_currentFileName == null) {
      final directory = await getApplicationDocumentsDirectory();
      final entities = await directory.list().toList();
      final files = entities.where((f) => f.path.contains('tournament_') && f.path.endsWith('.json')).toList();
      
      final currentTitle = _titleController.text.trim();
      bool isDuplicate = false;

      for (var f in files) {
        try {
          final content = await File(f.path).readAsString();
          final data = jsonDecode(content);
          if (data['title']?.toString().trim() == currentTitle) {
            isDuplicate = true;
            break;
          }
        } catch (_) {}
      }

      if (isDuplicate) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('같은 이름의 대회가 이미 있습니다.'),
              backgroundColor: Colors.redAccent,
            )
          );
        }
        return;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentFileName = 'tournament_$timestamp.json';
    }
    await _saveData();
    setState(() {}); 
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('대회 파일이 고정되었습니다. 이제부터 모든 진행 상황이 자동 저장됩니다.')));
    }
  }

  Map<String, dynamic> _eventToMap(TournamentEvent e) {
    return {
      'id': e.id, 'name': e.name, 'groupSize': e.settings.groupSize, 'advancingCount': e.settings.advancingCount,
      'players': e.players.map((p) => {'id': p.id, 'name': p.name, 'affiliation': p.affiliation}).toList(),
      'groups': e.groups?.map((g) => {
        'name': g.name, 'players': g.players.map((p) => p.id).toList(), 'matches': g.matches.map((m) => _matchToMap(m)).toList(),
      }).toList(),
      'knockoutRounds': e.knockoutRounds?.map((r) => {
        'name': r.name, 'matches': r.matches.map((m) => _matchToMap(m)).toList(),
      }).toList(),
      'lastQualified': e.lastQualified?.map((p) => p.id).toList(),
    };
  }

  Map<String, dynamic> _matchToMap(Match m) {
    return {
      'id': m.id, 'p1Id': m.player1?.id, 'p2Id': m.player2?.id, 's1': m.score1, 's2': m.score2,
      'status': m.status.index, 'winnerId': m.winner?.id, 'nextMatchId': m.nextMatchId, 'nextMatchSlot': m.nextMatchSlot,
    };
  }

  Future<void> _loadInitialData() async {
    setState(() { _events.clear(); _currentFileName = null; });
  }

  Future<void> _loadFromFile(File file) async {
    try {
      final String contents = await file.readAsString();
      final Map<String, dynamic> data = jsonDecode(contents);
      setState(() {
        _titleController.text = data['title'] ?? '';
        _currentFileName = file.path.split(Platform.pathSeparator).last;
        _events.clear();
        if (data['events'] != null) {
          for (var eJson in data['events']) { _events.add(_eventFromMap(eJson)); }
        }
        _selectedEventIdx = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('[${_titleController.text}] 대회를 불러왔습니다.')));
    } catch (e) { debugPrint('Load error: $e'); }
  }

  TournamentEvent _eventFromMap(Map<String, dynamic> map) {
    final event = TournamentEvent(id: map['id'], name: map['name'], settings: TournamentSettings(groupSize: map['groupSize'] ?? 3, advancingCount: map['advancingCount'] ?? 2));
    if (map['players'] != null) { event.players.addAll((map['players'] as List).map((p) => Player(id: p['id'], name: p['name'], affiliation: p['affiliation']))); }
    Player? findP(String? id) => id == null ? null : event.players.firstWhere((p) => p.id == id, orElse: () => Player(id: id, name: '알수없음', affiliation: ''));
    if (map['groups'] != null) {
      event.groups = (map['groups'] as List).map((gJson) => Group(name: gJson['name'], players: (gJson['players'] as List).map((id) => findP(id)!).toList(), matches: (gJson['matches'] as List).map((mJson) => _matchFromMap(mJson, findP)).toList())).toList();
    }
    if (map['knockoutRounds'] != null) {
      event.knockoutRounds = (map['knockoutRounds'] as List).map((rJson) => Round(name: rJson['name'], matches: (rJson['matches'] as List).map((mJson) => _matchFromMap(mJson, findP)).toList())).toList();
    }
    if (map['lastQualified'] != null) { event.lastQualified = (map['lastQualified'] as List).map((id) => findP(id)!).toList(); }
    return event;
  }

  Match _matchFromMap(Map<String, dynamic> m, Player? Function(String?) findP) {
    return Match(id: m['id'], player1: findP(m['p1Id']), player2: findP(m['p2Id']), score1: m['s1'], score2: m['s2'], status: MatchStatus.values[m['status']], winner: findP(m['winnerId']), nextMatchId: m['nextMatchId'], nextMatchSlot: m['nextMatchSlot']);
  }

  Future<void> _showTournamentList() async {
    final directory = await getApplicationDocumentsDirectory();
    final entities = await directory.list().toList();
    final files = entities.where((f) => f.path.contains('tournament_') && f.path.endsWith('.json')).toList();

    List<Map<String, dynamic>> tournamentInfos = [];
    for (var f in files) {
      try {
        final content = await File(f.path).readAsString();
        final data = jsonDecode(content);
        tournamentInfos.add({
          'file': File(f.path),
          'title': data['title'] ?? '제목 없음',
          'fileName': f.path.split(Platform.pathSeparator).last,
        });
      } catch (_) {}
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('저장된 대회 목록', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: tournamentInfos.isEmpty 
            ? const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('저장된 대회가 없습니다.', textAlign: TextAlign.center))
            : ListView.separated(
                shrinkWrap: true,
                itemCount: tournamentInfos.length,
                separatorBuilder: (ctx, idx) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final info = tournamentInfos[index];
                  String displayTitle = info['title'];
                  if (displayTitle.length > 15) {
                    displayTitle = '${displayTitle.substring(0, 15)}...';
                  }

                  return ListTile(
                    contentPadding: const EdgeInsets.only(left: 4, right: 0),
                    minLeadingWidth: 20, 
                    leading: const Icon(Icons.emoji_events_outlined, color: Colors.green, size: 20),
                    title: Text(
                      displayTitle, 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), 
                      maxLines: 1,
                    ),
                    onTap: () { Navigator.pop(context); _loadFromFile(info['file']); },
                    trailing: IconButton(
                      padding: EdgeInsets.zero, 
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                      onPressed: () {
                        if (_currentFileName == info['fileName']) setState(() { _currentFileName = null; });
                        info['file'].deleteSync();
                        Navigator.pop(context);
                        _showTournamentList();
                      },
                    ),
                  );
                },
              ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기', style: TextStyle(color: Colors.grey)))],
      ),
    );
  }

  static List<int>? _generateExcelData(Map<String, dynamic> params) {
    final String title = params['title'];
    final String eventName = params['eventName'];
    final List<Map<String, dynamic>> groups = params['groups'];
    var excel = excel_lib.Excel.createExcel();
    var sheet = excel[excel.getDefaultSheet() ?? 'Sheet1'];
    sheet.appendRow([excel_lib.TextCellValue('대회명: $title ($eventName)')]);
    sheet.appendRow([excel_lib.TextCellValue('출력일시: ${DateTime.now().toString()}')]);
    if (groups.isNotEmpty) {
      sheet.appendRow([excel_lib.TextCellValue('=== [예선 조별 기록] ===')]);
      for (var group in groups) {
        sheet.appendRow([excel_lib.TextCellValue('--- ${group['name']} ---')]);
        for (var m in group['matches']) { sheet.appendRow([excel_lib.TextCellValue('${m['p1']} ${m['s1']} : ${m['s2']} ${m['p2']}')]); }
      }
    }
    return excel.encode();
  }

  Future<void> _exportToExcel() async {
    if (_currentEvent == null) return;
    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
    try {
      final title = _titleController.text;
      final event = _currentEvent!;
      final groupsData = event.groups?.map((g) => {
        'name': g.name, 'matches': g.matches.where((m) => m.status == MatchStatus.completed).map((m) => {'p1': m.player1?.name ?? '?', 'p2': m.player2?.name ?? '?', 's1': m.score1, 's2': m.score2}).toList(),
      }).toList() ?? [];
      final encodedBytes = await compute(_generateExcelData, {'title': title, 'eventName': event.name, 'groups': groupsData});
      if (!mounted) return;
      Navigator.pop(context);
      if (encodedBytes != null) {
        String? selectedPath = await FilePicker.platform.saveFile(dialogTitle: '데이터 저장', fileName: '${title}_${event.name}.xlsx', bytes: Uint8List.fromList(encodedBytes));
        if (selectedPath != null) { await File(selectedPath).writeAsBytes(encodedBytes, flush: true); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장되었습니다.'))); }
      }
    } catch (e) { if (mounted) { if (Navigator.canPop(context)) Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 실패: $e'))); } }
  }

  Future<void> _pickExcelFile() async {
    if (_currentEvent == null) return;
    try {
      // 1. 엑셀 파일 선택
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom, 
        allowedExtensions: ['xlsx', 'xls'], 
        withData: true
      );
      
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      Uint8List? bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null) return;

      // 2. 엑셀 데이터 분석 및 시트 목록 추출
      var excel = excel_lib.Excel.decodeBytes(bytes);
      List<String> sheetNames = excel.tables.keys.toList();

      if (!mounted) return;

      // 3. 시트(탭) 선택 다이얼로그 표시 (참조 코드 스타일 적용)
      String? selectedSheet = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('가져올 시트(탭) 선택', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: sheetNames.length,
              itemBuilder: (context, index) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.table_view, color: Colors.green),
                    title: Text(sheetNames[index]),
                    onTap: () => Navigator.pop(context, sheetNames[index]),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: const Text('취소', style: TextStyle(color: Colors.grey))
            ),
          ],
        ),
      );

      // 4. 선택된 시트의 데이터를 선수 명단에 추가
      if (selectedSheet != null) {
        List<Player> newPlayers = [];
        var table = excel.tables[selectedSheet];
        if (table != null) {
          // 첫 번째 행(헤더)은 건너뛰고 데이터 추출
          for (var row in table.rows.skip(1)) {
            if (row.isEmpty || row[0] == null) continue;
            
            String name = row[0]!.value.toString().trim();
            if (name.isEmpty) continue;
            
            String affiliation = (row.length >= 2 && row[1] != null) 
                ? row[1]!.value.toString().trim() 
                : '개인';
            if (affiliation.isEmpty) affiliation = '개인';

            newPlayers.add(Player(
              id: _uuid.v4(), 
              name: name, 
              affiliation: affiliation
            ));
          }
        }

        if (newPlayers.isNotEmpty) {
          setState(() {
            // 선택한 시트의 선수를 명단에 포함(추가)
            _currentEvent!.players.addAll(newPlayers);
            // 명단이 변경되었으므로 기존 대진표(그룹) 초기화
            _currentEvent!.groups = null; 
          });
          _saveData();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('[$selectedSheet] 시트에서 ${newPlayers.length}명을 추가했습니다.'))
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('선택한 시트에 가져올 선수 데이터가 없습니다.'))
            );
          }
        }
      }
    } catch (e) { 
      debugPrint('Excel Import Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('엑셀 파일을 읽는 중 오류가 발생했습니다.'))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('대회 설정 및 관리'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _topMenuButton(Icons.folder_open_rounded, '대회 목록', Colors.amber, _showTournamentList),
                if (_currentEvent != null) ...[
                  _topMenuButton(Icons.file_upload_rounded, '엑셀 로드', Colors.blue, _pickExcelFile),
                  _topMenuButton(Icons.assignment_outlined, '기록지 보기', Colors.purple, () {
                    if (_currentEvent!.groups == null) { _currentEvent!.groups = TournamentLogic.generateGroups(_currentEvent!.players, _currentEvent!.settings); _saveData(); }
                    Navigator.push(context, MaterialPageRoute(builder: (context) => MatchSheetPage(tournamentTitle: '${_titleController.text} (${_currentEvent!.name})', groups: _currentEvent!.groups!, knockoutRounds: _currentEvent!.knockoutRounds)));
                  }),
                  _topMenuButton(Icons.file_download_rounded, '결과 저장', Colors.green, _exportToExcel),
                ],
                _topMenuButton(Icons.refresh, '초기화', Colors.red, () { setState(() { _events.clear(); _currentFileName = null; _titleController.text = '새 탁구 대회'; }); }),
              ],
            ),
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildTitleInput(),
                const SizedBox(height: 12),
                const Text(' 경기 종목 선택/추가', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                _buildEventSelector(),
                const SizedBox(height: 16),
                if (_currentEvent != null) ...[
                  _buildSettingsCard(),
                  const SizedBox(height: 16),
                  _buildPlayerInput(),
                ] else
                  const Center(child: Padding(padding: EdgeInsets.all(40.0), child: Text('상단의 폴더 버튼으로 대회를 불러오거나\n[종목 추가]로 새 경기를 시작하세요.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))),
              ]),
            ),
          ),
          if (_currentEvent != null)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(delegate: SliverChildBuilderDelegate((context, index) => _buildPlayerTile(_currentEvent!.players[index], index), childCount: _currentEvent!.players.length)),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: (_currentEvent == null || _currentEvent!.players.length < 2) ? null : Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: FloatingActionButton.extended(
          onPressed: () async {
            _currentEvent!.groups ??= TournamentLogic.generateGroups(_currentEvent!.players, _currentEvent!.settings);
            _saveData();
            
            // [수정] GroupStagePage 호출 시 인덱스 동기화를 위해 결과값을 반환받습니다.
            final result = await Navigator.push(
              context, 
              MaterialPageRoute(builder: (context) => GroupStagePage(
                tournamentBaseTitle: _titleController.text, 
                allEvents: _events, 
                initialEventIdx: _selectedEventIdx, 
                onDataChanged: _saveData
              ))
            );

            // 예선 화면에서 종목이 변경되어 돌아온 경우, 메인 화면의 선택 인덱스도 동기화합니다.
            if (result is int) {
              setState(() {
                _selectedEventIdx = result;
              });
            }
          },
          label: Text('${_currentEvent!.name} 예선 관리 (${_currentEvent!.players.length}명)', style: const TextStyle(fontWeight: FontWeight.bold)),
          icon: const Icon(Icons.play_arrow_rounded),
          backgroundColor: const Color(0xFF1A535C),
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _topMenuButton(IconData icon, String label, Color color, VoidCallback onTap) => InkWell(onTap: onTap, child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: color, size: 24), const SizedBox(height: 2), Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold))]));

  Widget _buildTitleInput() => Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0), child: Row(children: [Expanded(child: TextField(controller: _titleController, onEditingComplete: _saveData, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A535C)), decoration: const InputDecoration(labelText: '대회 제목', border: InputBorder.none))), IconButton(icon: Icon(_currentFileName == null ? Icons.save_outlined : Icons.check_circle_rounded, color: _currentFileName == null ? Colors.grey : Colors.blue, size: 28), onPressed: _handleInitialSave, tooltip: _currentFileName == null ? '대회 파일 생성/고정' : '파일 고정됨 (자동 저장 중)')])));

  Widget _buildEventSelector() => SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [..._events.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(right: 8.0), child: GestureDetector(onLongPress: () { showDialog(context: context, builder: (context) => AlertDialog(title: const Text('종목 삭제'), content: Text('[${e.value.name}]을 삭제할까요?'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')), TextButton(onPressed: () { setState(() { _events.removeAt(e.key); _selectedEventIdx = 0; }); _saveData(); Navigator.pop(context); }, child: const Text('삭제', style: TextStyle(color: Colors.red)))],)); }, child: ChoiceChip(label: Text(e.value.name), selected: _selectedEventIdx == e.key, selectedColor: const Color(0xFF1A535C), labelStyle: TextStyle(color: _selectedEventIdx == e.key ? Colors.white : Colors.black, fontWeight: FontWeight.bold), onSelected: (selected) { if (selected) setState(() => _selectedEventIdx = e.key); },),),)), ActionChip(avatar: const Icon(Icons.add, size: 20), label: const Text('종목 추가'), onPressed: _addNewEvent, backgroundColor: Colors.orange.shade50)]));

  Widget _buildSettingsCard() => Card(child: Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('[${_currentEvent!.name}] 경기 설정', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A535C))), const SizedBox(height: 8), Row(children: [Expanded(child: DropdownButtonFormField<int>(value: _currentEvent!.settings.groupSize, decoration: const InputDecoration(labelText: '조별 인원'), items: [3, 4, 5].map((e) => DropdownMenuItem(value: e, child: Text('$e명'))).toList(), onChanged: (v) => setState(() { _currentEvent!.settings.groupSize = v!; _currentEvent!.groups = null; _saveData(); }))), const SizedBox(width: 16), Expanded(child: DropdownButtonFormField<int>(value: _currentEvent!.settings.advancingCount, decoration: const InputDecoration(labelText: '진출 인원'), items: [1, 2, 3].map((e) => DropdownMenuItem(value: e, child: Text('$e명'))).toList(), onChanged: (v) => setState(() { _currentEvent!.settings.advancingCount = v!; _currentEvent!.groups = null; _saveData(); }))),])],),));

  Widget _buildPlayerInput() => Card(child: Padding(padding: const EdgeInsets.all(8.0), child: Row(children: [Expanded(child: TextField(controller: _nameController, decoration: const InputDecoration(hintText: '이름', border: InputBorder.none))), Expanded(child: TextField(controller: _affController, decoration: const InputDecoration(hintText: '소속', border: InputBorder.none))), IconButton.filled(onPressed: () { if (_nameController.text.isNotEmpty) { setState(() { _currentEvent!.players.insert(0, Player(id: _uuid.v4(), name: _nameController.text, affiliation: _affController.text.isEmpty ? '개인' : _affController.text)); _nameController.clear(); _affController.clear(); _currentEvent!.groups = null; }); _saveData(); } }, icon: const Icon(Icons.add), style: IconButton.styleFrom(backgroundColor: const Color(0xFFFF6B6B))),])));

  Widget _buildPlayerTile(Player p, int index) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(leading: CircleAvatar(backgroundColor: const Color(0xFF4ECDC4).withOpacity(0.2), child: Text('${_currentEvent!.players.length - index}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A535C))),), title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(p.affiliation), trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () { setState(() { _currentEvent!.players.removeAt(index); _currentEvent!.groups = null; }); _saveData(); }),),);

  void _addNewEvent() {
    final controller = TextEditingController();
    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(title: const Text('새 경기 종목 추가'), content: SizedBox(width: double.maxFinite, child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: controller, decoration: InputDecoration(hintText: '종목 이름을 입력하세요', suffixIcon: IconButton(icon: const Icon(Icons.playlist_add, color: Colors.blue), onPressed: () { if (controller.text.isNotEmpty && !_presets.contains(controller.text)) { setDialogState(() => _presets.add(controller.text)); _savePresets(); } },),), autofocus: true,), const SizedBox(height: 15), const Row(children: [Icon(Icons.star, size: 14, color: Colors.amber), SizedBox(width: 4), Text('자주 쓰는 종목', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),],), const Divider(), Flexible(child: Container(constraints: const BoxConstraints(maxHeight: 200), child: ListView.builder(shrinkWrap: true, itemCount: _presets.length, itemBuilder: (context, idx) { return ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(_presets[idx]), onTap: () => controller.text = _presets[idx], trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.edit_note, size: 20, color: Colors.grey), onPressed: () { final editController = TextEditingController(text: _presets[idx]); showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('종목 이름 수정'), content: TextField(controller: editController, autofocus: true), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')), TextButton(onPressed: () { if (editController.text.isNotEmpty) { setDialogState(() => _presets[idx] = editController.text); _savePresets(); Navigator.pop(ctx); } }, child: const Text('수정')),],),); },), IconButton(icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.redAccent), onPressed: () { setDialogState(() => _presets.removeAt(idx)); _savePresets(); },),],),); },),),),],),), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')), TextButton(onPressed: () { if (controller.text.isNotEmpty) { final bool isDuplicate = _events.any((e) => e.name.trim() == controller.text.trim()); if (isDuplicate) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이미 생성된 종목입니다.'), backgroundColor: Colors.orange)); return; } setState(() { _events.add(TournamentEvent(id: _uuid.v4(), name: controller.text.trim())); _selectedEventIdx = _events.length - 1; }); _saveData(); Navigator.pop(context); } }, child: const Text('추가')),],),),);
  }
}
