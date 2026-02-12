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
import 'main.dart';
import 'models.dart';
import 'tournament_logic.dart';
import 'group_stage_page.dart';
import 'knockout_page.dart';
import 'match_sheet_page.dart';
import 'setup_logic_mixin.dart';

class SetupMobileView extends StatefulWidget {
  const SetupMobileView({super.key});
  @override
  State<SetupMobileView> createState() => _SetupMobileViewState();
}

class _SetupMobileViewState extends State<SetupMobileView> with SetupLogicMixin {
  final _nameController = TextEditingController();
  final _affController = TextEditingController();
  final List<TextEditingController> _teamMemberControllers = List.generate(5, (_) => TextEditingController());
  final _teamNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    initSetupData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _affController.dispose();
    _teamNameController.dispose();
    for (var c in _teamMemberControllers) c.dispose();
    super.dispose();
  }

  // 선수의 추가/삭제 제한을 포함한 보안 업데이트 함수
  void _secureSettingUpdate(VoidCallback updateAction, {bool isPlayerAction = false}) {
    // 1. 본선이 시작되었는지 확인 (Hard Block)
    if (isPlayerAction && currentEvent != null && currentEvent!.knockoutRounds != null && currentEvent!.knockoutRounds!.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('본선 토너먼트가 시작되어 선수를 추가/삭제할 수 없습니다.'), backgroundColor: Colors.redAccent)
      );
      return;
    }

    // 2. 예선 대진표가 생성되었는지 확인 (Password 확인)
    if (currentEvent != null && currentEvent!.groups != null) {
      final pwController = TextEditingController();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('관리자 확인'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('관리자의 허락없이 수정할 수 없습니다.', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: pwController,
                obscureText: true,
                onSubmitted: (_) => _handlePasswordSubmit(pwController.text, updateAction, ctx),
                decoration: const InputDecoration(labelText: '비밀번호 입력', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            TextButton(
              onPressed: () => _handlePasswordSubmit(pwController.text, updateAction, ctx),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } else {
      setState(updateAction);
    }
  }

  void _handlePasswordSubmit(String input, VoidCallback updateAction, BuildContext dialogCtx) {
    if (input == '1234') {
      setState(updateAction);
      Navigator.pop(dialogCtx);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('비밀번호가 틀렸습니다.')));
    }
  }

  Future<void> _handleInitialSave() async {
    if (currentFileName == null) {
      final directory = await getApplicationDocumentsDirectory();
      final entities = await directory.list().toList();
      final files = entities.where((f) => f.path.contains('tournament_') && f.path.endsWith('.json')).toList();
      final currentTitle = titleController.text.trim();
      bool isDuplicate = false;
      for (var f in files) {
        try {
          final content = await File(f.path).readAsString();
          final data = jsonDecode(content);
          if (data['title']?.toString().trim() == currentTitle) { isDuplicate = true; break; }
        } catch (_) {}
      }
      if (isDuplicate) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('같은 이름의 대회가 이미 있습니다.'), backgroundColor: Colors.redAccent));
        return;
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      currentFileName = 'tournament_$timestamp.json';
    }
    await saveData();
    setState(() {}); 
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('대회 파일이 고정되었습니다.')));
  }

  @override
  Widget build(BuildContext context) {
    bool isKnockoutStarted = currentEvent != null && currentEvent!.knockoutRounds != null && currentEvent!.knockoutRounds!.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('대회 설정 및 관리'),
        actions: [
          TextButton(onPressed: _goToGroupStage, child: const Text('예선전', style: TextStyle(color: Colors.white, fontSize: 13))),
          TextButton(onPressed: _goToKnockout, child: const Text('본선', style: TextStyle(color: Colors.white, fontSize: 13))),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _topMenuButton(Icons.folder_open_rounded, '대회 목록', Colors.amber, _showTournamentList),
                if (currentEvent != null) ...[
                  _topMenuButton(Icons.file_upload_rounded, '엑셀 로드', Colors.blue, pickExcelFile),
                  _topMenuButton(Icons.file_download_rounded, '결과 저장', Colors.green, _exportToExcel),
                ],
                _topMenuButton(Icons.refresh, '초기화', Colors.red, _handleReset),
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
                if (currentEvent != null) ...[
                  _buildSettingsCard(),
                  const SizedBox(height: 16),
                  _buildPlayerInput(isKnockoutStarted),
                ] else
                  const Center(child: Padding(padding: EdgeInsets.all(40.0), child: Text('대회를 불러오거나 종목을 추가하세요.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))),
              ]),
            ),
          ),
          if (currentEvent != null)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(delegate: SliverChildBuilderDelegate((context, index) => _buildPlayerTile(currentEvent!.players[index], index, isKnockoutStarted), childCount: currentEvent!.players.length)),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: (currentEvent == null || currentEvent!.players.length < 2) ? null : Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: FloatingActionButton.extended(
          onPressed: _startTournament,
          label: Text('${currentEvent!.name} 예선 관리 (${currentEvent!.players.length}명)', style: const TextStyle(fontWeight: FontWeight.bold)),
          icon: const Icon(Icons.play_arrow_rounded),
          backgroundColor: const Color(0xFF1A535C),
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    bool isLocked = currentEvent!.groups != null;
    return Card(
      color: isLocked ? Colors.amber.shade50 : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(isLocked ? Icons.lock_outline : Icons.settings, size: 18, color: const Color(0xFF1A535C)),
                    const SizedBox(width: 8),
                    Text('[${currentEvent!.name}] 경기 설정', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A535C))),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('예선전 없음', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Checkbox(
                      visualDensity: VisualDensity.compact,
                      value: currentEvent!.settings.skipGroupStage,
                      onChanged: (v) {
                        _secureSettingUpdate(() {
                          currentEvent!.settings.skipGroupStage = v!;
                          currentEvent!.groups = null;
                          saveData();
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
            if (isLocked)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('관리자의 허락없이 수정할 수 없습니다.', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: currentEvent!.settings.groupSize,
                    decoration: const InputDecoration(labelText: '조별 인원'),
                    items: [3, 4, 5].map((e) => DropdownMenuItem(value: e, child: Text('$e명'))).toList(),
                    onChanged: currentEvent!.settings.skipGroupStage ? null : (v) {
                      _secureSettingUpdate(() {
                        currentEvent!.settings.groupSize = v!;
                        currentEvent!.groups = null;
                        saveData();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: currentEvent!.settings.advancingCount,
                    decoration: const InputDecoration(labelText: '진출 인원'),
                    items: [1, 2, 3].map((e) => DropdownMenuItem(value: e, child: Text('$e명'))).toList(),
                    onChanged: currentEvent!.settings.skipGroupStage ? null : (v) {
                      _secureSettingUpdate(() {
                        currentEvent!.settings.advancingCount = v!;
                        currentEvent!.groups = null;
                        saveData();
                      });
                    },
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _topMenuButton(IconData icon, String label, Color color, VoidCallback onTap) => InkWell(onTap: onTap, child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: color, size: 24), const SizedBox(height: 2), Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold))]));
  Widget _buildTitleInput() => Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0), child: Row(children: [Expanded(child: TextField(controller: titleController, onEditingComplete: saveData, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A535C)), decoration: const InputDecoration(labelText: '대회 제목', border: InputBorder.none))), IconButton(icon: Icon(currentFileName == null ? Icons.save_outlined : Icons.check_circle_rounded, color: currentFileName == null ? Colors.grey : Colors.blue, size: 28), onPressed: _handleInitialSave)])));
  Widget _buildEventSelector() => SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [...events.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(right: 8.0), child: GestureDetector(onLongPress: () { _secureSettingUpdate(() { showDialog(context: context, builder: (context) => AlertDialog(title: const Text('종목 삭제'), content: Text('[${e.value.name}]을 삭제할까요?'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')), TextButton(onPressed: () { setState(() { events.removeAt(e.key); selectedEventIdx = 0; }); saveData(); Navigator.pop(context); }, child: const Text('삭제', style: TextStyle(color: Colors.red)))],)); }); }, child: ChoiceChip(label: Text(e.value.name), selected: selectedEventIdx == e.key, selectedColor: const Color(0xFF1A535C), labelStyle: TextStyle(color: selectedEventIdx == e.key ? Colors.white : Colors.black, fontWeight: FontWeight.bold), onSelected: (selected) { if (selected) setState(() => selectedEventIdx = e.key); },),),)), ActionChip(avatar: const Icon(Icons.add, size: 20), label: const Text('종목 추가'), onPressed: () => showAddEventDialog(context), backgroundColor: Colors.orange.shade50)]));

  Widget _buildPlayerInput(bool isKnockoutStarted) {
    if (currentEvent == null) return const SizedBox.shrink();
    if (currentEvent!.teamSize > 1) {
      return Card(
        color: isKnockoutStarted ? Colors.grey.shade50 : const Color(0xFFF8F9FA),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [const Icon(Icons.group, color: Color(0xFF1A535C), size: 20), const SizedBox(width: 8), Text('${currentEvent!.teamSize}인 단체전 팀 등록', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A535C))), if (isKnockoutStarted) const Padding(padding: EdgeInsets.only(left: 8), child: Text('(본선 시작-추가불가)', style: TextStyle(color: Colors.red, fontSize: 11)))]),
              const SizedBox(height: 12),
              TextField(controller: _teamNameController, enabled: !isKnockoutStarted, decoration: const InputDecoration(labelText: '팀명 (클럽명)', border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: List.generate(currentEvent!.teamSize, (i) => SizedBox(width: (MediaQuery.of(context).size.width - 64) / 2, child: TextField(controller: _teamMemberControllers[i], enabled: !isKnockoutStarted, decoration: InputDecoration(labelText: '${i + 1}번 선수', border: const OutlineInputBorder(), isDense: true))))),
              const SizedBox(height: 12),
              ElevatedButton.icon(onPressed: isKnockoutStarted ? null : _addTeamEntry, icon: const Icon(Icons.add_task), label: const Text('단체전 팀 등록하기'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B6B), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 45))),
            ],
          ),
        ),
      );
    }
    return Card(child: Padding(padding: const EdgeInsets.all(8.0), child: Row(children: [Expanded(child: TextField(controller: _nameController, enabled: !isKnockoutStarted, decoration: const InputDecoration(hintText: '이름(부수)', border: InputBorder.none))), Expanded(child: TextField(controller: _affController, enabled: !isKnockoutStarted, decoration: const InputDecoration(hintText: '소속 (클럽명)', border: InputBorder.none))), IconButton.filled(onPressed: isKnockoutStarted ? null : _addSinglePlayer, icon: const Icon(Icons.add), style: IconButton.styleFrom(backgroundColor: const Color(0xFFFF6B6B)))])));
  }

  void _addSinglePlayer() => _secureSettingUpdate(() { if (_nameController.text.isNotEmpty) { currentEvent!.players.insert(0, Player(id: const Uuid().v4(), name: _nameController.text, affiliation: _affController.text.isEmpty ? '개인' : _affController.text)); _nameController.clear(); _affController.clear(); saveData(); } }, isPlayerAction: true);
  void _addTeamEntry() => _secureSettingUpdate(() { if (_teamNameController.text.isEmpty) return; List<String> names = []; for (int i = 0; i < currentEvent!.teamSize; i++) { if (_teamMemberControllers[i].text.isNotEmpty) names.add(_teamMemberControllers[i].text.trim()); } if (names.isEmpty) return; currentEvent!.players.insert(0, Player(id: const Uuid().v4(), name: names.join(', '), affiliation: _teamNameController.text.trim())); _teamNameController.clear(); for (var c in _teamMemberControllers) c.clear(); saveData(); }, isPlayerAction: true);

  String _formatNames(String names) {
    if (names.isEmpty) return "";
    List<String> list = names.split(',').map((s) => s.trim()).toList();
    List<String> lines = [];
    for (int i = 0; i < list.length; i += 2) { if (i + 1 < list.length) lines.add("${list[i]}, ${list[i+1]}"); else lines.add(list[i]); }
    return lines.join('\n');
  }

  Widget _buildPlayerTile(Player p, int index, bool isKnockoutStarted) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(leading: CircleAvatar(backgroundColor: const Color(0xFF4ECDC4).withOpacity(0.2), child: Text('${currentEvent!.players.length - index}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A535C)))), title: Text(currentEvent!.teamSize > 1 ? p.affiliation : p.name, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(currentEvent!.teamSize > 1 ? _formatNames(p.name) : p.affiliation), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: Icon(Icons.edit_outlined, color: isKnockoutStarted ? Colors.grey : Colors.blue), onPressed: isKnockoutStarted ? null : () => _handleEditPlayer(index, p)), IconButton(icon: Icon(Icons.delete_outline, color: isKnockoutStarted ? Colors.grey : Colors.red), onPressed: isKnockoutStarted ? null : () => _secureSettingUpdate(() { currentEvent!.players.removeAt(index); saveData(); }, isPlayerAction: true))])));

  void _handleEditPlayer(int index, Player player) {
    final editNameController = TextEditingController(text: player.name);
    final editAffController = TextEditingController(text: player.affiliation);
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('수정'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: editAffController, decoration: const InputDecoration(labelText: '소속')), TextField(controller: editNameController, decoration: const InputDecoration(labelText: '이름'))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')), TextButton(onPressed: () { _secureSettingUpdate(() { currentEvent!.players[index] = Player(id: player.id, name: editNameController.text.trim(), affiliation: editAffController.text.trim()); saveData(); Navigator.pop(ctx); }, isPlayerAction: true); }, child: const Text('수정'))]));
  }

  void _handleReset() => showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('초기화'), content: const Text('데이터를 초기화하시겠습니까?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')), TextButton(onPressed: () { setState(() { events.clear(); currentFileName = null; titleController.text = '새 탁구 대회'; }); Navigator.pop(ctx); }, child: const Text('초기화', style: TextStyle(color: Colors.red)))]));
  void _goToGroupStage() { if (currentEvent == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('진행 종목을 선택해주세요.'))); return; } currentEvent!.groups ??= TournamentLogic.generateGroups(currentEvent!.players, currentEvent!.settings); saveData(); final unchecked = eventUncheckedIdsNotifier.value; final eventsToShow = events.where((e) => !unchecked.contains(e.id)).toList(); final list = eventsToShow.isEmpty ? List<TournamentEvent>.from(events) : eventsToShow; final idx = list.indexWhere((e) => e.id == currentEvent!.id); final initialIdx = idx >= 0 ? idx : 0; Navigator.push(context, MaterialPageRoute(builder: (context) => GroupStagePage(tournamentBaseTitle: titleController.text, allEvents: list, initialEventIdx: initialIdx, onDataChanged: saveData))).then((result) { if (result is int) setState(() => selectedEventIdx = result); }); }
  void _goToKnockout() { if (currentEvent == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('진행 종목을 선택해주세요.'))); return; } if (currentEvent!.knockoutRounds == null || currentEvent!.knockoutRounds!.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('본선 대진이 없습니다. 예선전에서 본선 진출 생성 후 이동해주세요.'))); return; } final unchecked = eventUncheckedIdsNotifier.value; final eventsToShow = events.where((e) => !unchecked.contains(e.id)).toList(); final list = eventsToShow.isEmpty ? List<TournamentEvent>.from(events) : eventsToShow; Navigator.push(context, MaterialPageRoute(builder: (context) => KnockoutPage(tournamentTitle: '${titleController.text} - ${currentEvent!.name}', rounds: currentEvent!.knockoutRounds!, onDataChanged: saveData, events: list))); }
  void _startTournament() async { if (currentEvent!.groups == null) currentEvent!.groups = TournamentLogic.generateGroups(currentEvent!.players, currentEvent!.settings); saveData(); final unchecked = eventUncheckedIdsNotifier.value; final eventsToShow = events.where((e) => !unchecked.contains(e.id)).toList(); final list = eventsToShow.isEmpty ? List<TournamentEvent>.from(events) : eventsToShow; final idx = list.indexWhere((e) => e.id == currentEvent!.id); final initialIdx = idx >= 0 ? idx : 0; final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => GroupStagePage(tournamentBaseTitle: titleController.text, allEvents: list, initialEventIdx: initialIdx, onDataChanged: saveData))); if (result is int) setState(() => selectedEventIdx = result); }
  Future<void> _showTournamentList() async { final directory = await getApplicationDocumentsDirectory(); final entities = await directory.list().toList(); final files = entities.where((f) => f.path.contains('tournament_') && f.path.endsWith('.json')).toList(); List<Map<String, dynamic>> infos = []; for (var f in files) { try { final content = await File(f.path).readAsString(); final data = jsonDecode(content); infos.add({'file': File(f.path), 'title': data['title'] ?? '제목 없음', 'fileName': f.path.split(Platform.pathSeparator).last}); } catch (_) {} } if (!mounted) return; showDialog(context: context, builder: (context) => AlertDialog(title: const Text('대회 목록'), content: SizedBox(width: double.maxFinite, child: infos.isEmpty ? const Text('없음') : ListView.builder(shrinkWrap: true, itemCount: infos.length, itemBuilder: (context, index) { final info = infos[index]; return ListTile(title: Text(info['title']), onTap: () { Navigator.pop(context); loadFromFile(info['file']); }); })), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))])); }
  Future<void> _exportToExcel() async { /* 엑셀 로직 유지 */ }
}
