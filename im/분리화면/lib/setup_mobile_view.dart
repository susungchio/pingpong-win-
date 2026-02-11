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

class SetupMobileView extends StatefulWidget {
  const SetupMobileView({super.key});
  @override
  State<SetupMobileView> createState() => _SetupMobileViewState();
}

class _SetupMobileViewState extends State<SetupMobileView> {
  final _uuid = const Uuid();
  final _titleController = TextEditingController(text: '새 탁구 대회');
  
  final List<TournamentEvent> _events = [];
  int _selectedEventIdx = 0;
  String? _currentFileName; 
  List<String> _presets = []; 

  // 개인전용 컨트롤러
  final _nameController = TextEditingController();
  final _affController = TextEditingController();

  // 단체전용 컨트롤러 리스트
  final List<TextEditingController> _teamMemberControllers = List.generate(5, (_) => TextEditingController());
  final _teamNameController = TextEditingController();

  TournamentEvent? get _currentEvent => _events.isNotEmpty ? _events[_selectedEventIdx] : null;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _loadPresets(); 
  }

  @override
  void dispose() {
    _nameController.dispose();
    _affController.dispose();
    _teamNameController.dispose();
    for (var c in _teamMemberControllers) {
      c.dispose();
    }
    super.dispose();
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
      'id': e.id, 'name': e.name, 'teamSize': e.teamSize, 'groupSize': e.settings.groupSize, 'advancingCount': e.settings.advancingCount,
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
    final event = TournamentEvent(
      id: map['id'], 
      name: map['name'], 
      teamSize: map['teamSize'] ?? 1,
      settings: TournamentSettings(groupSize: map['groupSize'] ?? 3, advancingCount: map['advancingCount'] ?? 2)
    );
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
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom, 
        allowedExtensions: ['xlsx', 'xls'], 
        withData: true
      );
      
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      Uint8List? bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null) return;

      var excel = excel_lib.Excel.decodeBytes(bytes);
      List<String> sheetNames = excel.tables.keys.toList();

      if (!mounted) return;

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

      if (selectedSheet != null) {
        List<Player> newPlayers = [];
        var table = excel.tables[selectedSheet];
        if (table != null) {
          int teamSize = _currentEvent!.teamSize;

          for (var row in table.rows.skip(1)) {
            if (row.isEmpty) continue;
            
            String name = "";
            String affiliation = "";

            if (teamSize > 1) {
              // [단체전] A컬럼: 소속, B컬럼~: 선수 이름들
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
              // [개인전] A컬럼: 이름, B컬럼: 소속
              name = row[0]?.value?.toString().trim() ?? "";
              affiliation = (row.length >= 2 && row[1] != null) 
                  ? row[1]!.value.toString().trim() 
                  : '개인';
            }

            if (name.isEmpty) continue;
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
            _currentEvent!.players.addAll(newPlayers);
            _currentEvent!.groups = null; 
          });
          _saveData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('[$selectedSheet] 시트에서 ${newPlayers.length}개 팀/선수를 추가했습니다.'))
            );
          }
        }
      }
    } catch (e) { 
      debugPrint('Excel Import Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('엑셀 파일을 읽는 중 오류가 발생했습니다.')));
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
            
            final result = await Navigator.push(
              context, 
              MaterialPageRoute(builder: (context) => GroupStagePage(
                tournamentBaseTitle: _titleController.text, 
                allEvents: _events, 
                initialEventIdx: _selectedEventIdx, 
                onDataChanged: _saveData
              ))
            );

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

  Widget _buildPlayerInput() {
    if (_currentEvent == null) return const SizedBox.shrink();

    // 단체전용 입력 UI (팀명 + 팀원들)
    if (_currentEvent!.teamSize > 1) {
      return Card(
        color: const Color(0xFFF8F9FA),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.group, color: Color(0xFF1A535C), size: 20),
                  const SizedBox(width: 8),
                  Text('${_currentEvent!.teamSize}인 단체전 팀 등록', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A535C))),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _teamNameController,
                decoration: const InputDecoration(
                  labelText: '팀명 (클럽명)',
                  hintText: '예: 진주탁구클럽',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              const Text(' 팀원 명단 입력', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              // 인원수만큼 입력칸 생성
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_currentEvent!.teamSize, (i) => SizedBox(
                  width: (MediaQuery.of(context).size.width - 64) / 2,
                  child: TextField(
                    controller: _teamMemberControllers[i],
                    decoration: InputDecoration(
                      labelText: '${i + 1}번 선수',
                      hintText: '이름(부수)',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                )),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _addTeamEntry,
                icon: const Icon(Icons.add_task),
                label: const Text('단체전 팀 등록하기'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B6B),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 45),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 개인전용 입력 UI (기존)
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Expanded(child: TextField(controller: _nameController, decoration: const InputDecoration(hintText: '이름(부수)', border: InputBorder.none))),
            Expanded(child: TextField(controller: _affController, decoration: const InputDecoration(hintText: '소속 (클럽명)', border: InputBorder.none))),
            IconButton.filled(
              onPressed: _addSinglePlayer,
              icon: const Icon(Icons.add),
              style: IconButton.styleFrom(backgroundColor: const Color(0xFFFF6B6B)),
            ),
          ],
        ),
      ),
    );
  }

  void _addSinglePlayer() {
    if (_nameController.text.isNotEmpty) {
      setState(() {
        _currentEvent!.players.insert(0, Player(
          id: _uuid.v4(), 
          name: _nameController.text, 
          affiliation: _affController.text.isEmpty ? '개인' : _affController.text
        ));
        _nameController.clear();
        _affController.clear();
        _currentEvent!.groups = null;
      });
      _saveData();
    }
  }

  void _addTeamEntry() {
    if (_teamNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('팀명을 입력해주세요.')));
      return;
    }

    // 입력된 팀원 이름들을 리스트로 추출 (비어있지 않은 것만)
    List<String> names = [];
    for (int i = 0; i < _currentEvent!.teamSize; i++) {
      if (_teamMemberControllers[i].text.isNotEmpty) {
        names.add(_teamMemberControllers[i].text.trim());
      }
    }

    if (names.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('최소 한 명 이상의 팀원을 입력해주세요.')));
      return;
    }

    setState(() {
      _currentEvent!.players.insert(0, Player(
        id: _uuid.v4(),
        name: names.join(', '), // 팀원들을 "이름1, 이름2" 형태로 저장
        affiliation: _teamNameController.text.trim(),
      ));
      
      // 입력창 초기화
      _teamNameController.clear();
      for (var c in _teamMemberControllers) {
        c.clear();
      }
      _currentEvent!.groups = null;
    });
    _saveData();
  }

  // 명단 2명씩 줄바꿈 포맷터
  String _formatNames(String names) {
    if (names.isEmpty) return "";
    List<String> list = names.split(',').map((s) => s.trim()).toList();
    List<String> lines = [];
    for (int i = 0; i < list.length; i += 2) {
      if (i + 1 < list.length) lines.add("${list[i]}, ${list[i+1]}");
      else lines.add(list[i]);
    }
    return lines.join('\n');
  }

  Widget _buildPlayerTile(Player p, int index) {
    bool isTeamMatch = _currentEvent!.teamSize > 1;
    return Card(
      margin: const EdgeInsets.only(bottom: 8), 
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF4ECDC4).withOpacity(0.2), 
          child: Text('${_currentEvent!.players.length - index}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A535C))),
        ), 
        title: Text(isTeamMatch ? p.affiliation : p.name, style: const TextStyle(fontWeight: FontWeight.bold)), 
        subtitle: Text(isTeamMatch ? _formatNames(p.name) : p.affiliation), 
        isThreeLine: isTeamMatch && p.name.contains(','),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red), 
          onPressed: () { 
            setState(() { 
              _currentEvent!.players.removeAt(index); 
              _currentEvent!.groups = null; 
            }); 
            _saveData(); 
          }
        ),
      ),
    );
  }

  void _addNewEvent() {
    final controller = TextEditingController();
    int selectedTeamSize = 1; 

    showDialog(
      context: context, 
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('새 경기 종목 추가'), 
          content: SizedBox(
            width: double.maxFinite, 
            child: Column(
              mainAxisSize: MainAxisSize.min, 
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller, 
                        decoration: const InputDecoration(
                          hintText: '종목 이름을 입력하세요',
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ), 
                        autofocus: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    DropdownButton<int>(
                      value: selectedTeamSize,
                      underline: Container(height: 1, color: Colors.grey),
                      items: [1, 2, 3, 4, 5].map((n) => DropdownMenuItem(
                        value: n,
                        child: Text(n == 1 ? '개인전' : '$n인 단체', style: const TextStyle(fontSize: 13)),
                      )).toList(),
                      onChanged: (v) {
                        if (v != null) setDialogState(() => selectedTeamSize = v);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.playlist_add, color: Colors.blue), 
                      onPressed: () { 
                        if (controller.text.isNotEmpty && !_presets.contains(controller.text)) { 
                          setDialogState(() => _presets.add(controller.text)); 
                          _savePresets(); 
                        } 
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 15), 
                const Row(children: [Icon(Icons.star, size: 14, color: Colors.amber), SizedBox(width: 4), Text('자주 쓰는 종목', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),],), 
                const Divider(), 
                Flexible(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 200), 
                    child: ListView.builder(
                      shrinkWrap: true, 
                      itemCount: _presets.length, 
                      itemBuilder: (context, idx) { 
                        return ListTile(
                          dense: true, 
                          contentPadding: EdgeInsets.zero, 
                          title: Text(_presets[idx]), 
                          onTap: () => controller.text = _presets[idx], 
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min, 
                            children: [
                              IconButton(icon: const Icon(Icons.edit_note, size: 20, color: Colors.grey), onPressed: () { final editController = TextEditingController(text: _presets[idx]); showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('종목 이름 수정'), content: TextField(controller: editController, autofocus: true), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')), TextButton(onPressed: () { if (editController.text.isNotEmpty) { setDialogState(() => _presets[idx] = editController.text); _savePresets(); Navigator.pop(ctx); } }, child: const Text('수정')),],),); },), 
                              IconButton(icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.redAccent), onPressed: () { setDialogState(() => _presets.removeAt(idx)); _savePresets(); },),
                            ],
                          ),
                        ); 
                      },
                    ),
                  ),
                ),
              ],
            ),
          ), 
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')), 
            TextButton(
              onPressed: () { 
                if (controller.text.isNotEmpty) { 
                  String eventName = controller.text.trim();
                  if (selectedTeamSize > 1) {
                    eventName = '$eventName ($selectedTeamSize인 단체)';
                  }

                  final bool isDuplicate = _events.any((e) => e.name.trim() == eventName); 
                  if (isDuplicate) { 
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이미 생성된 종목입니다.'), backgroundColor: Colors.orange)); 
                    return; 
                  } 
                  setState(() { 
                    _events.add(TournamentEvent(id: _uuid.v4(), name: eventName, teamSize: selectedTeamSize));
                    _selectedEventIdx = _events.length - 1; 
                  }); 
                  _saveData(); 
                  Navigator.pop(context); 
                } 
              }, 
              child: const Text('추가'),
            ),
          ],
        ),
      ),
    );
  }
}
