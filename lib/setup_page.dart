import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart' as excel_lib;
import 'package:file_picker/file_picker.dart';
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
  final List<Player> _players = [];
  final _titleController = TextEditingController(text: '탁구 토너먼트');
  final _nameController = TextEditingController();
  final _affController = TextEditingController();
  final _uuid = const Uuid();
  TournamentSettings _settings = TournamentSettings(groupSize: 3, advancingCount: 2);

  List<Group>? _generatedGroups;
  List<Round>? _generatedKnockoutRounds;
  List<Player>? _lastQualifiedPlayers;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/tournament_config.json');
      if (await file.exists()) {
        final String contents = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(contents);
        setState(() {
          _titleController.text = data['title'] ?? '탁구 토너먼트';
          _settings.groupSize = data['groupSize'] ?? 3;
          _settings.advancingCount = data['advancingCount'] ?? 2;
        });
      } else {
        _addDummyData();
      }
    } catch (e) {
      _addDummyData();
    }
  }

  Future<void> _saveData() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/tournament_config.json');
      final data = {
        'title': _titleController.text,
        'groupSize': _settings.groupSize,
        'advancingCount': _settings.advancingCount,
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Save error: $e');
    }
  }

  void _addDummyData() {
    final List<Map<String, String>> dummyData = [
      {'name': '홍길동', 'aff': '진주하나'}, {'name': '김철수', 'aff': '서울탁구'},
      {'name': '이영희', 'aff': '부산핑퐁'}, {'name': '박민수', 'aff': '대구클럽'},
      {'name': '최지우', 'aff': '광주동호'}, {'name': '강호동', 'aff': '대전탁구'},
      {'name': '유재석', 'aff': '인천핑퐁'}, {'name': '정형돈', 'aff': '울산클럽'},
      {'name': '노홍철', 'aff': '수원탁구'}, {'name': '하동훈', 'aff': '제주동호'},
      {'name': '박명수', 'aff': '성남클럽'}, {'name': '정준하', 'aff': '고양탁구'},
    ];
    for (var data in dummyData) {
      _players.add(Player(id: _uuid.v4(), name: data['name']!, affiliation: data['aff']!));
    }
  }

  Future<void> _pickExcelFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      Uint8List? bytes = file.bytes;

      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }

      if (bytes != null) {
        _processExcel(bytes);
      }
    } catch (e) {
      debugPrint('Excel Import Error: $e');
    }
  }

  void _processExcel(Uint8List bytes) {
    try {
      var excel = excel_lib.Excel.decodeBytes(bytes);
      List<Player> allPlayers = [];
      for (var table in excel.tables.keys) {
        var sheet = excel.tables[table]!;
        for (var row in sheet.rows.skip(1)) {
          if (row.isEmpty || row[0] == null) continue;
          String name = row[0]!.value.toString();
          String aff = (row.length >= 2 && row[1] != null) ? row[1]!.value.toString() : '개인';
          allPlayers.add(Player(id: _uuid.v4(), name: name, affiliation: aff));
        }
      }
      setState(() {
        _players.clear();
        _players.addAll(allPlayers);
        _generatedGroups = null;
        _saveData();
      });
    } catch (e) {
      debugPrint('Excel Processing Error: $e');
    }
  }

  Future<void> _exportToExcel() async {
    try {
      var excel = excel_lib.Excel.createExcel();
      var sheet = excel[excel.getDefaultSheet() ?? 'Sheet1'];
      
      sheet.appendRow([excel_lib.TextCellValue('대회명: ${_titleController.text}')]);
      sheet.appendRow([excel_lib.TextCellValue('출력일시: ${DateTime.now().toString()}')]);
      sheet.appendRow([excel_lib.TextCellValue('')]);

      // 1. 본선 기록 내보내기 (결승부터 역순으로)
      if (_generatedKnockoutRounds != null && _generatedKnockoutRounds!.isNotEmpty) {
        sheet.appendRow([excel_lib.TextCellValue('=== [본선 토너먼트 전체 기록] ===')]);
        var reversedRounds = _generatedKnockoutRounds!.reversed.toList();
        for (var round in reversedRounds) {
          sheet.appendRow([excel_lib.TextCellValue('[${round.name}]')]);
          for (int i = 0; i < round.matches.length; i++) {
            var m = round.matches[i];
            String p1Info = m.player1 != null ? '${m.player1!.name}(${m.player1!.affiliation})' : 'TBD';
            String p2Info = m.player2 != null ? '${m.player2!.name}(${m.player2!.affiliation})' : 'TBD';
            String score = m.status == MatchStatus.completed ? '${m.score1} : ${m.score2}' : '-';
            sheet.appendRow([
              excel_lib.TextCellValue('경기 ${i + 1}'), 
              excel_lib.TextCellValue(p1Info), 
              excel_lib.TextCellValue(score), 
              excel_lib.TextCellValue(p2Info)
            ]);
          }
          sheet.appendRow([excel_lib.TextCellValue('')]);
        }
      }

      // 2. 예선 기록 내보내기 (표 + 세트 기록)
      if (_generatedGroups != null) {
        sheet.appendRow([excel_lib.TextCellValue('=== [예선 조별 리그 기록] ===')]);
        for (var group in _generatedGroups!) {
          sheet.appendRow([excel_lib.TextCellValue('--- ${group.name} ---')]);
          
          // 2.1 예선 순위 표 (승, 득, 실, 득실)
          sheet.appendRow([
            excel_lib.TextCellValue('순위'),
            excel_lib.TextCellValue('이름'),
            excel_lib.TextCellValue('소속'),
            excel_lib.TextCellValue('승'),
            excel_lib.TextCellValue('득'),
            excel_lib.TextCellValue('실'),
            excel_lib.TextCellValue('득실')
          ]);
          
          var rankings = TournamentLogic.getGroupRankings(group);
          var stats = TournamentLogic.getRankingStats(group);
          for (int i = 0; i < rankings.length; i++) {
            var p = rankings[i];
            var s = stats[p]!;
            sheet.appendRow([
              excel_lib.IntCellValue(i + 1), 
              excel_lib.TextCellValue(p.name), 
              excel_lib.TextCellValue(p.affiliation), 
              excel_lib.IntCellValue(s['wins']!), 
              excel_lib.IntCellValue(s['won']!), 
              excel_lib.IntCellValue(s['lost']!), 
              excel_lib.IntCellValue(s['diff']!)
            ]);
          }
          sheet.appendRow([excel_lib.TextCellValue('')]);
          
          // 2.2 세부 경기 세트 기록 (권태영 2 : 3 최수빈 형식)
          sheet.appendRow([excel_lib.TextCellValue('<세부 경기 기록>')]);
          for (var m in group.matches) {
            if (m.status == MatchStatus.completed) {
              String matchResult = '${m.player1?.name ?? "알수없음"} ${m.score1} : ${m.score2} ${m.player2?.name ?? "알수없음"}';
              sheet.appendRow([excel_lib.TextCellValue(matchResult)]);
            }
          }
          sheet.appendRow([excel_lib.TextCellValue('')]);
        }
      }

      final encodedBytes = excel.encode();
      if (encodedBytes != null) {
        Uint8List bytes = Uint8List.fromList(encodedBytes);
        String? selectedPath = await FilePicker.platform.saveFile(
          dialogTitle: '대회 결과 저장',
          fileName: '${_titleController.text}_전체결과.xlsx',
          bytes: bytes, 
        );
        if (selectedPath != null) {
          final file = File(selectedPath);
          await file.writeAsBytes(bytes);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장되었습니다.')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('대회 설정 및 등록'), actions: [
        IconButton(
          icon: const Icon(Icons.assignment_outlined, color: Colors.purple),
          onPressed: () {
             if (_generatedGroups == null) {
               _generatedGroups = TournamentLogic.generateGroups(_players, _settings);
             }
             Navigator.push(context, MaterialPageRoute(builder: (context) => MatchSheetPage(
               tournamentTitle: _titleController.text,
               groups: _generatedGroups!,
               knockoutRounds: _generatedKnockoutRounds,
             )));
          },
          tooltip: '경기 기록지(오다지) 보기',
        ),
        IconButton(icon: const Icon(Icons.file_upload_rounded, color: Colors.blue), onPressed: _pickExcelFile, tooltip: '엑셀 불러오기'),
        IconButton(icon: const Icon(Icons.file_download_rounded, color: Colors.green), onPressed: _exportToExcel, tooltip: '대회 결과 내보내기'),
        IconButton(onPressed: () => setState(() { _players.clear(); _generatedGroups = null; _generatedKnockoutRounds = null; _saveData(); }), icon: const Icon(Icons.refresh, color: Colors.red)),
      ]),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildTitleInput(),
                const SizedBox(height: 12),
                _buildSettingsCard(),
                const SizedBox(height: 20),
                _buildPlayerInput(),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(delegate: SliverChildBuilderDelegate((context, index) => _buildPlayerTile(_players[index], index), childCount: _players.length)),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: FloatingActionButton.extended(
          onPressed: _players.length < 2 ? null : () {
            _generatedGroups ??= TournamentLogic.generateGroups(_players, _settings);
            Navigator.push(context, MaterialPageRoute(builder: (context) => GroupStagePage(
              tournamentTitle: _titleController.text,
              groups: _generatedGroups!,
              settings: _settings,
              existingRounds: _generatedKnockoutRounds,
              lastQualified: _lastQualifiedPlayers,
              onKnockoutUpdate: (rounds, qualified) => setState(() {
                _generatedKnockoutRounds = rounds;
                _lastQualifiedPlayers = qualified;
                _saveData();
              }),
            )));
          },
          label: Text('예선 대진 관리 (${_players.length}명)', style: const TextStyle(fontWeight: FontWeight.bold)),
          icon: const Icon(Icons.play_arrow_rounded),
          backgroundColor: const Color(0xFF1A535C),
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildTitleInput() => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: TextField(
        controller: _titleController,
        onChanged: (_) => _saveData(),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A535C)),
        decoration: const InputDecoration(labelText: '대회 제목', border: InputBorder.none, hintText: '대회 이름을 입력하세요'),
      ),
    ),
  );

  Widget _buildSettingsCard() => Card(child: Padding(padding: const EdgeInsets.all(16.0), child: Row(children: [
    Expanded(child: DropdownButtonFormField<int>(value: _settings.groupSize, decoration: const InputDecoration(labelText: '조별 인원'), items: [3, 4, 5].map((e) => DropdownMenuItem(value: e, child: Text('$e명'))).toList(), onChanged: (v) => setState(() { _settings.groupSize = v!; _generatedGroups = null; _saveData(); }))),
    const SizedBox(width: 16),
    Expanded(child: DropdownButtonFormField<int>(value: _settings.advancingCount, decoration: const InputDecoration(labelText: '진출 인원'), items: [1, 2, 3].map((e) => DropdownMenuItem(value: e, child: Text('$e명'))).toList(), onChanged: (v) => setState(() { _settings.advancingCount = v!; _generatedGroups = null; _saveData(); }))),
  ])));

  Widget _buildPlayerInput() => Card(child: Padding(padding: const EdgeInsets.all(8.0), child: Row(children: [
    Expanded(child: TextField(controller: _nameController, decoration: const InputDecoration(hintText: '이름', border: InputBorder.none))),
    Expanded(child: TextField(controller: _affController, decoration: const InputDecoration(hintText: '소속', border: InputBorder.none))),
    IconButton.filled(onPressed: () {
      if (_nameController.text.isNotEmpty) {
        setState(() { _players.insert(0, Player(id: _uuid.v4(), name: _nameController.text, affiliation: _affController.text.isEmpty ? '개인' : _affController.text)); _nameController.clear(); _affController.clear(); _generatedGroups = null; _saveData(); });
      }
    }, icon: const Icon(Icons.add), style: IconButton.styleFrom(backgroundColor: const Color(0xFFFF6B6B))),
  ])));

  Widget _buildPlayerTile(Player p, int index) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
    leading: CircleAvatar(
      backgroundColor: const Color(0xFF4ECDC4).withOpacity(0.2),
      radius: 26,
      child: Text('${_players.length - index}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A535C))),
    ),
    title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(p.affiliation, style: const TextStyle(fontSize: 13, color: Colors.grey)),
    ]),
    trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => setState(() { _players.removeAt(index); _generatedGroups = null; _saveData(); })),
  ));
}
