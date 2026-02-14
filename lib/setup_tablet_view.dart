import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'main.dart';
import 'models.dart';
import 'tournament_logic.dart';
import 'group_stage_page.dart';
import 'knockout_page.dart';
import 'program_settings_page.dart';
import 'setup_logic_mixin.dart';
import 'file_utils.dart'; // [추가]
import 'package:path/path.dart' as p; // [추가] 경로 처리를 위해

/// 경기설정 부수설정에서 선택 가능한 17가지 부수 명칭
const List<String> _tierOptions = [
  '남 1부', '남 2부', '남 3부', '남 4부', '남 5부', '남 6부', '남 7부', '남 8부',
  '여 1부', '여 2부', '여 3부', '여 4부', '여 5부', '여 6부', '여 7부', '여 8부',
  '남 선수부',
];

class SetupTabletView extends StatefulWidget {
  const SetupTabletView({super.key});
  @override
  State<SetupTabletView> createState() => _SetupTabletViewState();
}

class _SetupTabletViewState extends State<SetupTabletView> with SetupLogicMixin<SetupTabletView>, SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _affController = TextEditingController();
  List<TextEditingController> _teamMemberControllers = [];
  final _teamNameController = TextEditingController();
  final _bulkInputController = TextEditingController();
  int _lastTeamSize = 0;
  String? _editingTeamId;

  bool _isDbManagementMode = false;
  List<MasterPlayer> _searchedMasterPlayers = [];
  bool _showAutoComplete = false;
  List<MasterPlayer> _allMasterPlayers = [];
  int _duplicatesCount = 0;
  late final TabController _playerTabController;
  String _playerSelectQuery = '';
  bool _leftPanelTapped = false;
  final GlobalKey _leftPanelKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    initSetupData();
    _refreshMasterList();
    _checkDuplicatesCount();
    
    _nameController.addListener(_onNameChanged);
    _playerTabController = TabController(length: 2, vsync: this);
    _playerTabController.addListener(() {
      if (!mounted) return;
      if (_playerTabController.index == 1) {
        setState(() { _leftPanelTapped = false; });
      }
      if (_playerTabController.index == 0) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (!mounted) return;
          if (_playerTabController.index == 0) { setState(() {}); }
        });
      }
    });
    FocusManager.instance.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    final leftCtx = _leftPanelKey.currentContext;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (leftCtx == null || focused == null || !mounted) return;
    bool inLeft = false;
    (focused as Element).visitAncestorElements((Element e) {
      if (e == leftCtx) { inLeft = true; return false; }
      return true;
    });
    if (inLeft && mounted) setState(() => _leftPanelTapped = true);
  }

  @override
  void afterLoadFromFile(Map<String, dynamic> data) {
    if (currentEvent != null && currentEvent!.teamSize > 1) {
      _updateTeamMemberControllers(currentEvent!.teamSize);
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _affController.dispose();
    _teamNameController.dispose();
    _bulkInputController.dispose();
    for (var c in _teamMemberControllers) c.dispose();
    _playerTabController.dispose();
    FocusManager.instance.removeListener(_onFocusChange);
    super.dispose();
  }

  void _updateTeamMemberControllers(int teamSize) {
    final int totalMembers = teamSize > 1 ? teamSize + 1 : 0;
    if (_lastTeamSize != totalMembers) {
      for (var c in _teamMemberControllers) { c.dispose(); }
      _teamMemberControllers = List.generate(totalMembers, (_) => TextEditingController());
      _lastTeamSize = totalMembers;
    }
  }

  bool _isPlayerInInputFields(String playerName) {
    for (var controller in _teamMemberControllers) {
      if (controller.text.trim() == playerName.trim()) return true;
    }
    return false;
  }

  bool _isPlayerInRegisteredTeams(String playerName) {
    if (currentEvent == null || currentEvent!.teamSize <= 1) return false;
    for (var player in currentEvent!.players) {
      final teamMembers = player.name.split(', ').map((s) => s.trim()).toList();
      if (teamMembers.contains(playerName.trim())) return true;
    }
    return false;
  }

  bool _isPlayerAlreadyRegistered(String playerName) {
    return _isPlayerInInputFields(playerName) || _isPlayerInRegisteredTeams(playerName);
  }

  void _removePlayerFromInputFields(String playerName) {
    for (var controller in _teamMemberControllers) {
      if (controller.text.trim() == playerName.trim()) { controller.clear(); break; }
    }
  }

  void _loadTeamToInputFields(Player teamPlayer) {
    if (currentEvent == null || currentEvent!.teamSize <= 1) return;
    _updateTeamMemberControllers(currentEvent!.teamSize);
    _teamNameController.text = teamPlayer.affiliation;
    final teamMembers = teamPlayer.name.split(', ').map((s) => s.trim()).toList();
    for (int i = 0; i < _teamMemberControllers.length && i < teamMembers.length; i++) {
      _teamMemberControllers[i].text = teamMembers[i];
    }
    for (int i = teamMembers.length; i < _teamMemberControllers.length; i++) {
      _teamMemberControllers[i].clear();
    }
    _editingTeamId = teamPlayer.id;
    setState(() {});
  }

  void _addPlayerToTeamInput(MasterPlayer p) {
    if (currentEvent == null || currentEvent!.teamSize <= 1) return;
    _updateTeamMemberControllers(currentEvent!.teamSize);
    final String playerName = '${p.name} (${p.tier})';
    final int totalMembers = currentEvent!.teamSize + 1;
    bool isInCurrentEditingTeam = false;
    if (_editingTeamId != null) {
      final existingTeam = currentEvent!.players.firstWhere((e) => e.id == _editingTeamId, orElse: () => Player(id: '', name: '', affiliation: ''));
      final existingMembers = existingTeam.name.split(', ').map((s) => s.trim()).toList();
      isInCurrentEditingTeam = existingMembers.contains(playerName);
    }
    if (!isInCurrentEditingTeam && _isPlayerAlreadyRegistered(playerName)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이미 등록된 선수입니다.'), duration: Duration(seconds: 1)));
      return;
    }
    int emptyIndex = -1;
    for (int i = 0; i < totalMembers && i < _teamMemberControllers.length; i++) {
      if (_teamMemberControllers[i].text.trim().isEmpty) { emptyIndex = i; break; }
    }
    if (emptyIndex == -1 && _teamMemberControllers.isNotEmpty) { emptyIndex = _teamMemberControllers.length - 1; }
    if (emptyIndex >= 0 && emptyIndex < _teamMemberControllers.length) {
      _teamMemberControllers[emptyIndex].text = playerName;
      if (_teamNameController.text.trim().isEmpty) {
        _teamNameController.text = p.affiliation.isNotEmpty ? p.affiliation : (p.city.isNotEmpty ? p.city : '개인');
      }
      setState(() {});
    }
  }

  Future<void> _refreshMasterList() async {
    final players = await dbService.getAllPlayers();
    setState(() { _allMasterPlayers = players; });
  }

  Future<void> _checkDuplicatesCount() async {
    final dups = await loadDuplicates();
    setState(() { _duplicatesCount = dups.length; });
  }

  void _onNameChanged() async {
    final query = _nameController.text.trim();
    if (query.length < 2) {
      if (mounted) setState(() { _searchedMasterPlayers = []; _showAutoComplete = false; });
      return;
    }
    final results = await dbService.searchPlayers(query);
    if (mounted) { setState(() { _searchedMasterPlayers = results; _showAutoComplete = results.isNotEmpty; }); }
  }

  void _selectMasterPlayer(MasterPlayer p) {
    setState(() { _nameController.text = "${p.name}(${p.tier})"; _affController.text = p.affiliation; _showAutoComplete = false; });
  }

  Future<void> _handleDeleteMaster(MasterPlayer p) async {
    if (p.id == null) return;
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('선수 정보 삭제'), content: Text('[${p.name}] 선수를 DB에서 영구 삭제하시겠습니까?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제', style: TextStyle(color: Colors.red)))]));
    if (confirmed == true) { await dbService.deletePlayer(p.id!); _refreshMasterList(); }
  }

  Future<void> _handleEditMaster(MasterPlayer p) async {
    final numEdit = TextEditingController(text: p.playerNumber);
    final cityEdit = TextEditingController(text: p.city);
    final affEdit = TextEditingController(text: p.affiliation);
    final nameEdit = TextEditingController(text: p.name);
    final genderEdit = TextEditingController(text: p.gender);
    final tierEdit = TextEditingController(text: p.tier);
    final pointsEdit = TextEditingController(text: p.points);
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('선수 정보 수정'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: numEdit, decoration: const InputDecoration(labelText: '번호')), TextField(controller: cityEdit, decoration: const InputDecoration(labelText: '지역')), TextField(controller: affEdit, decoration: const InputDecoration(labelText: '동호회')), TextField(controller: nameEdit, decoration: const InputDecoration(labelText: '이름')), TextField(controller: genderEdit, decoration: const InputDecoration(labelText: '성별')), TextField(controller: tierEdit, decoration: const InputDecoration(labelText: '부수')), TextField(controller: pointsEdit, decoration: const InputDecoration(labelText: '누적점수'))])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')), TextButton(onPressed: () async { final updated = MasterPlayer(id: p.id, playerNumber: numEdit.text.trim(), city: cityEdit.text.trim(), affiliation: affEdit.text.trim(), name: nameEdit.text.trim(), gender: genderEdit.text.trim(), tier: tierEdit.text.trim(), points: pointsEdit.text.trim()); await dbService.updatePlayer(p.id!, updated); _refreshMasterList(); Navigator.pop(ctx); }, child: const Text('수정'))]));
  }

  void _goToGroupStage() {
    if (currentEvent == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('진행 종목을 선택해주세요.'))); return; }
    currentEvent!.groups ??= TournamentLogic.generateGroups(currentEvent!.players, currentEvent!.settings);
    saveData();
    final unchecked = eventUncheckedIdsNotifier.value;
    final visibleEvents = events.where((e) => !unchecked.contains(e.id)).toList();
    final eventsToShow = visibleEvents.isEmpty ? List<TournamentEvent>.from(events) : visibleEvents;
    int initialIdx = 0;
    if (selectedEventIdx < events.length) {
      final currentId = events[selectedEventIdx].id;
      final idx = eventsToShow.indexWhere((e) => e.id == currentId);
      if (idx >= 0) initialIdx = idx;
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => GroupStagePage(tournamentBaseTitle: titleController.text, allEvents: eventsToShow, initialEventIdx: initialIdx, onDataChanged: saveData)));
  }

  void _goToKnockout() {
    if (currentEvent == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('진행 종목을 선택해주세요.'))); return; }
    if (currentEvent!.knockoutRounds == null || currentEvent!.knockoutRounds!.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('본선 대진이 없습니다. 예선전에서 본선 진출 생성 후 이동해주세요.'))); return; }
    final unchecked = eventUncheckedIdsNotifier.value;
    final visibleEvents = events.where((e) => !unchecked.contains(e.id)).toList();
    final eventsToShow = visibleEvents.isEmpty ? List<TournamentEvent>.from(events) : visibleEvents;
    int initialIdx = eventsToShow.indexWhere((e) => e.id == currentEvent!.id);
    if (initialIdx < 0) initialIdx = 0;
    Navigator.push(context, MaterialPageRoute(builder: (context) => KnockoutPage(tournamentTitle: '${titleController.text} - ${currentEvent!.name}', rounds: currentEvent!.knockoutRounds!, onDataChanged: saveData, events: eventsToShow)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: _isDbManagementMode ? null : AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF1A535C),
        foregroundColor: Colors.white,
        title: Text(titleController.text.isEmpty ? '대회 설정' : titleController.text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(onPressed: _goToGroupStage, child: const Text('예선전', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          TextButton(onPressed: _goToKnockout, child: const Text('본선토너먼트', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(children: [
        _buildSidebar(),
        Expanded(child: _isDbManagementMode ? _buildDbManagementArea() : LayoutBuilder(builder: (context, constraints) {
          final w = constraints.maxWidth;
          const dividerW = 1.0;
          final isPanelExpanded = _playerTabController.index == 1 && !_leftPanelTapped;
          final leftWidth = isPanelExpanded ? (w * 3 / 5 - 200).clamp(400.0, w - 400) : w * 3 / 5;
          final rightPanelWidth = w - leftWidth - dividerW;
          return Row(children: [
            GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => setState(() => _leftPanelTapped = true), child: SizedBox(key: _leftPanelKey, width: leftWidth, child: _buildMainInputArea())),
            const SizedBox(width: 1, child: VerticalDivider(width: 1)),
            Expanded(child: _buildPlayerListArea(rightPanelWidth, isPanelExpanded: isPanelExpanded)),
          ]);
        })),
      ]),
    );
  }

  Widget _buildSidebar() {
    // [추가] 외부 이미지 로드 경로 생성 (현재 베이스 디렉토리/img/logo.png)
    final logoPath = p.join(FileUtils.currentBaseDir, 'img', 'logo.png');
    final logoFile = File(logoPath);
    // [추가] 상단 마크 이미지 경로 생성 (현재 베이스 디렉토리/img/mark.png)
    final markPath = p.join(FileUtils.currentBaseDir, 'img', 'mark.png');
    final markFile = File(markPath);

    return Container(
      width: 280, color: const Color(0xFF1A535C),
      child: Column(children: [
        const SizedBox(height: 50),
        // [수정] mark.png 파일이 있으면 이미지로 표시, 없으면 기본 아이콘 표시
        markFile.existsSync()
            ? Image.file(
                markFile,
                width: 40,
                height: 40,
                fit: BoxFit.contain,
                errorBuilder: (ctx, err, st) => const Icon(Icons.emoji_events_outlined, color: Colors.white, size: 40),
              )
            : const Icon(Icons.emoji_events_outlined, color: Colors.white, size: 40),
        const SizedBox(height: 12),
        const Text('탁구 대회 매니저', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const Text('PC/Tablet Edition', style: TextStyle(color: Colors.white54, fontSize: 11)),
        const Divider(color: Colors.white24, height: 40, indent: 30, endIndent: 30),
        _sidebarItem(Icons.edit_document, '대회 설정 및 참가 등록', !_isDbManagementMode, () => setState(() { _isDbManagementMode = false; })),
        _sidebarItem(Icons.storage_rounded, '기초 선수 DB 관리', _isDbManagementMode, () { setState(() { _isDbManagementMode = true; _refreshMasterList(); _checkDuplicatesCount(); }); }),
        _sidebarItem(Icons.settings_applications_rounded, '프로그램 설정', false, () {
          Navigator.push(context, MaterialPageRoute(builder: (ctx) => ProgramSettingsPage(
            events: events,
            currentFileName: currentFileName,
            onLoadFromFile: (file) async { await loadFromFile(file); setState(() {}); },
            onDeleteFile: (file, name) async { _handleDeleteFile(file, name); },
            onEditTitle: (file, title) async { _handleEditTitle(file, title); },
            onDeleteEvent: (eventId) {
              final idx = events.indexWhere((e) => e.id == eventId);
              if (idx >= 0) { setState(() { events.removeAt(idx); if (selectedEventIdx >= events.length) selectedEventIdx = events.length > 0 ? 0 : 0; }); saveData(); }
            },
          ))).then((_) { setState(() {}); });
        }),
        const Divider(color: Colors.white24, height: 30),
        if (!_isDbManagementMode) ...[
          _sidebarItem(Icons.save_rounded, '현재 상태 저장', false, () async { await saveData(); }),
          _sidebarItem(Icons.table_view_rounded, '엑셀 명단 로드', false, pickExcelFile),
          _sidebarItem(Icons.refresh_rounded, '새 대회 시작', false, _handleReset),
          const Divider(color: Colors.white24, height: 30),
        ] else const Expanded(child: SizedBox()),
        
        // [수정] 하단 이미지 삽입 구간 (가로 2 : 세로 3 비율, 양쪽 여백 제거 및 너비 꽉 채우기)
        if (logoFile.existsSync()) 
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10), // 좌우 패딩을 0으로 설정
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: Image.file(
                  logoFile,
                  fit: BoxFit.fitWidth, // 가로를 꽉 채우도록 설정
                  alignment: Alignment.center,
                  errorBuilder: (ctx, err, st) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),

        const Divider(color: Colors.white24, height: 1),
        const Spacer(),
        const SizedBox(height: 10),
        Padding(padding: const EdgeInsets.all(16.0), child: Text(currentFileName ?? '신규 대회 작성 중', style: const TextStyle(color: Colors.white24, fontSize: 10))),
      ]),
    );
  }

  Widget _sidebarItem(IconData icon, String label, bool isSelected, VoidCallback onTap) => ListTile(leading: Icon(icon, color: isSelected ? Colors.amber : Colors.white, size: 20), title: Text(label, style: TextStyle(color: isSelected ? Colors.amber : Colors.white, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)), onTap: onTap, contentPadding: const EdgeInsets.symmetric(horizontal: 24));

  Widget _buildDbManagementArea() {
    return Row(children: [
      Expanded(flex: 4, child: Container(color: Colors.white, child: Column(children: [
        Padding(padding: const EdgeInsets.all(32), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('선수 DB 브라우저', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton.icon(onPressed: () async {
              final stats = await dbService.getTierStats();
              if (!mounted) return;
              final totalTiers = stats.length;
              final tierNames = stats.keys.toList();
              showDialog(context: context, builder: (ctx) => AlertDialog(
                title: const Text('부수 분석'),
                content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('부수 종류: ${totalTiers}가지', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  Text('명칭 및 인원:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 8),
                  ...tierNames.map((name) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $name: ${stats[name]}명'))),
                ])),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인'))],
              ));
            }, icon: const Icon(Icons.analytics_outlined, size: 20), label: const Text('부수 분석')),
            const SizedBox(width: 8),
            Chip(label: Text('총 ${_allMasterPlayers.length}명'), backgroundColor: Colors.amber.shade50),
          ]),
        ])),
        const Divider(height: 1),
        Expanded(child: _allMasterPlayers.isEmpty ? const Center(child: Text('등록된 선수가 없습니다.')) : ListView.separated(padding: const EdgeInsets.all(24), itemCount: _allMasterPlayers.length, separatorBuilder: (ctx, i) => const Divider(), itemBuilder: (ctx, idx) {
          final p = _allMasterPlayers[idx];
          return Card(color: Colors.grey.shade50, child: ListTile(
            leading: CircleAvatar(backgroundColor: const Color(0xFF1A535C), child: Text(p.playerNumber.isNotEmpty ? p.playerNumber : '${_allMasterPlayers.length - idx}', style: const TextStyle(color: Colors.white, fontSize: 10))),
            title: Text('${p.name} (${p.tier})', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${p.city} | ${p.gender} | ${p.affiliation} | ${p.points}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 20), onPressed: () => _handleEditMaster(p)),
              IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20), onPressed: () => _handleDeleteMaster(p))
            ]),
          ));
        })),
        Padding(padding: const EdgeInsets.all(24.0), child: OutlinedButton.icon(onPressed: () async {
          final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('DB 전체 초기화'), content: const Text('모든 기초 선수 자료가 영구 삭제됩니다. 계속하시겠습니까?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('전체 삭제', style: TextStyle(color: Colors.red)))]));
          if (confirmed == true) { await dbService.clearDatabase(); _refreshMasterList(); }
        }, icon: const Icon(Icons.delete_sweep, color: Colors.red), label: const Text('전체 DB 초기화 (주의)', style: TextStyle(color: Colors.red)), style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)))),
      ]))),
      const VerticalDivider(width: 1),
      Expanded(flex: 3, child: Padding(padding: const EdgeInsets.all(32.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('대량 데이터 입력', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A535C))),
        const SizedBox(height: 12),
        const Text('한 줄에 번호·지역, 다음 줄 동호회, 이름, 마지막 줄 성별·부수·누적점수. 레코드는 "숫자+점"(예: 0.625점)으로 구분.', style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 24),
        Expanded(child: Card(elevation: 2, child: Padding(padding: const EdgeInsets.all(16.0), child: TextField(controller: _bulkInputController, maxLines: null, expands: true, decoration: const InputDecoration(hintText: '1\t거창군\n거창 거창클럽\n감규범\n남\t남 6부\t0.625점\n2\t김해시\n...', border: InputBorder.none), style: const TextStyle(fontSize: 12))))),
        const SizedBox(height: 24),
        ElevatedButton.icon(onPressed: () async {
          if (_bulkInputController.text.trim().isEmpty) return;
          final result = await importRawPlayerData(_bulkInputController.text);
          _bulkInputController.clear(); _refreshMasterList(); _checkDuplicatesCount();
          if (mounted) showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('입력 완료'), content: Text('신규 등록: ${result['added']}명\n정보 보완: ${result['updated']}명\n중복 제외: ${result['duplicates']}명'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인'))]));
        }, icon: const Icon(Icons.add_task), label: const Text('데이터 분석 및 등록', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A535C), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
        if (_duplicatesCount > 0) ...[
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade100)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [const Icon(Icons.warning_amber_rounded, color: Colors.red), const SizedBox(width: 8), Text('중복 발견: $_duplicatesCount건', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: ElevatedButton(onPressed: _showDuplicatesList, style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red), child: const Text('목록 보기'))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(onPressed: () async { await clearDuplicatesFile(); _checkDuplicatesCount(); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('파일 비우기'))),
              ]),
            ]),
          ),
        ],
      ]))),
    ]);
  }

  void _showDuplicatesList() async {
    final dups = await loadDuplicates();
    if (!mounted) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('중복 데이터 목록 (저장되지 않음)'), content: SizedBox(width: 500, height: 400, child: ListView.separated(itemCount: dups.length, separatorBuilder: (ctx, i) => const Divider(), itemBuilder: (ctx, i) => ListTile(title: Text('${dups[i].name} (${dups[i].tier})'), subtitle: Text('${dups[i].city} - ${dups[i].affiliation}'), dense: true))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기'))]));
  }

  Widget _buildMainInputArea() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: TextField(controller: titleController, onEditingComplete: () { saveData(); }, style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 40, fontWeight: FontWeight.bold, color: const Color(0xFF1A535C)), decoration: const InputDecoration(border: InputBorder.none, hintText: '대회 명칭을 입력하세요'))), if (currentFileName == null) ElevatedButton.icon(onPressed: _handleInitialSave, icon: const Icon(Icons.save_alt), label: const Text('대회 파일 생성/고정'), style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black87))]),
        const SizedBox(height: 32),
        Text('진행 종목', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 12),
        _buildEventSelector(),
        const SizedBox(height: 40),
        if (currentEvent != null) ...[_buildSettingsRow(), const SizedBox(height: 32), _buildPlayerInputCard()] else const Center(child: Padding(padding: EdgeInsets.all(60.0), child: Text('대회를 불러오거나 종목을 추가하세요.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))),
      ]),
    );
  }

  Widget _buildEventSelector() {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: eventUncheckedIdsNotifier,
      builder: (context, uncheckedIds, _) {
        // [수정] 체크 해제되지 않은 종목만 필터링
        final visibleEventEntries = events.asMap().entries.where((e) => !uncheckedIds.contains(e.value.id)).toList();

        return Wrap(spacing: 12, runSpacing: 12, children: [
          ...visibleEventEntries.map((e) {
            final isSelected = selectedEventIdx == e.key;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onLongPress: () => _deleteEventDialog(e.key),
                child: ChoiceChip(
                  label: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), child: Text(e.value.name, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black))),
                  selected: isSelected,
                  selectedColor: const Color(0xFF1A535C),
                  onSelected: (v) { if (v) { setState(() { selectedEventIdx = e.key; if (currentEvent != null && currentEvent!.teamSize > 1) { _updateTeamMemberControllers(currentEvent!.teamSize); } }); } },
                ),
              ),
            );
          }),
          ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('종목 추가'), onPressed: () => Future.delayed(Duration.zero, () => showAddEventDialog(context)), backgroundColor: Colors.orange.shade50),
        ]);
      },
    );
  }

  void _secureSettingUpdate(VoidCallback updateAction, {bool isPlayerAction = false}) async {
    if (isPlayerAction && currentEvent!.knockoutRounds != null && currentEvent!.knockoutRounds!.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('본선 토너먼트가 시작되어 선수를 추가/삭제할 수 없습니다.'), backgroundColor: Colors.redAccent));
      return;
    }
    if (currentEvent!.groups != null) {
      final pwController = TextEditingController();
      final adminPw = await FileUtils.getAdminPassword(); // [변경]
      if (!mounted) return;
      showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text('관리자 확인'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('관리자의 허락없이 수정할 수 없습니다.', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(controller: pwController, obscureText: true, decoration: const InputDecoration(labelText: '비밀번호 입력', border: OutlineInputBorder()))
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(onPressed: () {
            if (pwController.text == adminPw) { // [변경]
              setState(updateAction);
              Navigator.pop(ctx);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('비밀번호가 틀렸습니다.')));
            }
          }, child: const Text('확인'))
        ],
      ));
    } else { setState(updateAction); }
  }

  Widget _buildSettingsRow() {
    bool isLocked = currentEvent!.groups != null;
    final settings = currentEvent!.settings;
    final showTierFilter = settings.showTierFilter;
    final hasTierSelection = settings.allowedTiers.isNotEmpty;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isLocked ? Colors.amber.shade200 : Colors.grey.shade200)),
      color: isLocked ? Colors.amber.shade50.withOpacity(0.3) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(isLocked ? Icons.lock_outline : Icons.settings, color: const Color(0xFF1A535C), size: 24),
              const SizedBox(width: 20),
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [const Text('경기 설정:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), if (isLocked) const Padding(padding: EdgeInsets.only(left: 8), child: Text('(대진표 관리 중 - 수정 제한)', style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold)))]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('예선전 없음', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(width: 4),
                  Checkbox(visualDensity: VisualDensity.compact, value: settings.skipGroupStage, onChanged: (v) { _secureSettingUpdate(() { currentEvent!.settings.skipGroupStage = v!; currentEvent!.groups = null; saveData(); }); }),
                  const SizedBox(width: 20),
                  Icon(hasTierSelection ? Icons.filter_list : Icons.filter_list_outlined, size: 18, color: hasTierSelection ? Colors.red : Colors.grey),
                  const SizedBox(width: 4),
                  Text('부수설정', style: TextStyle(fontSize: 13, color: hasTierSelection ? Colors.red : Colors.grey, fontWeight: hasTierSelection ? FontWeight.bold : FontWeight.normal)),
                  const SizedBox(width: 4),
                  Checkbox(visualDensity: VisualDensity.compact, value: showTierFilter, onChanged: (v) { _secureSettingUpdate(() { currentEvent!.settings.showTierFilter = v!; currentEvent!.groups = null; saveData(); }); }),
                ]),
              ]),
              const SizedBox(width: 40),
              Expanded(child: DropdownButtonFormField<int>(value: settings.groupSize, decoration: const InputDecoration(labelText: '조별 인원', labelStyle: TextStyle(fontSize: 14, color: Colors.grey), isDense: true, border: UnderlineInputBorder()), items: [3, 4, 5].map((e) => DropdownMenuItem(value: e, child: Text('$e명'))).toList(), onChanged: settings.skipGroupStage ? null : (v) { _secureSettingUpdate(() { currentEvent!.settings.groupSize = v!; currentEvent!.groups = null; saveData(); }); })),
              const SizedBox(width: 32),
              Expanded(child: DropdownButtonFormField<int>(value: settings.advancingCount, decoration: const InputDecoration(labelText: '진출 인원', labelStyle: TextStyle(fontSize: 14, color: Colors.grey), isDense: true, border: UnderlineInputBorder()), items: [1, 2, 3].map((e) => DropdownMenuItem(value: e, child: Text('$e명'))).toList(), onChanged: settings.skipGroupStage ? null : (v) { _secureSettingUpdate(() { currentEvent!.settings.advancingCount = v!; currentEvent!.groups = null; saveData(); }); })),
            ]),
            if (showTierFilter) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: _tierOptions.map((tier) {
                final isChecked = settings.allowedTiers.contains(tier);
                return FilterChip(label: Text(tier, style: const TextStyle(fontSize: 12)), selected: isChecked, onSelected: (v) { _secureSettingUpdate(() { if (v) currentEvent!.settings.allowedTiers.add(tier); else currentEvent!.settings.allowedTiers.remove(tier); currentEvent!.settings.allowedTiers = List.from(currentEvent!.settings.allowedTiers); currentEvent!.groups = null; saveData(); }); });
              }).toList()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerInputCard() {
    bool isTeam = currentEvent!.teamSize > 1;
    // 본선이 시작되었는지 확인
    bool isKnockoutStarted = currentEvent!.knockoutRounds != null && currentEvent!.knockoutRounds!.isNotEmpty;
    // 예선전 게임이 모두 종료되었는지 확인
    final groups = currentEvent!.groups ?? [];
    final bool isSkipMode = currentEvent!.settings.skipGroupStage;
    bool canProceed = false;
    if (isSkipMode) { canProceed = true; }
    else {
      canProceed = groups.isNotEmpty &&
                   groups.every((g) => g.matches.isNotEmpty &&
                   g.matches.every((m) => m.status == MatchStatus.completed || m.status == MatchStatus.withdrawal));
    }
    // 선수 추가 가능 여부: 본선이 시작되지 않았고, 예선전 게임이 모두 종료되지 않은 상태
    final bool canAddPlayer = !isKnockoutStarted && (isSkipMode || !canProceed || groups.isEmpty);
    
    if (isTeam) _updateTeamMemberControllers(currentEvent!.teamSize);
    return Stack(clipBehavior: Clip.none, children: [
      Card(
        elevation: 4, shadowColor: Colors.black12, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), color: canAddPlayer ? Colors.white : Colors.grey.shade50,
        child: Padding(padding: const EdgeInsets.all(32), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Text(isTeam ? '${currentEvent!.teamSize}인 단체전 선수 등록' : '개인전 선수 등록', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: canAddPlayer ? const Color(0xFF1A535C) : Colors.grey)), if (!canAddPlayer) const Padding(padding: EdgeInsets.only(left: 12), child: Text('(본선 시작으로 추가 불가)', style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold)))]),
          const SizedBox(height: 24),
          if (isTeam) ...[
            TextField(controller: _teamNameController, enabled: canAddPlayer, decoration: const InputDecoration(labelText: '팀명 (클럽명)', border: OutlineInputBorder())),
            const SizedBox(height: 20),
            Wrap(spacing: 16, runSpacing: 16, children: List.generate(currentEvent!.teamSize + 1, (i) => SizedBox(width: 250, child: Row(children: [Expanded(child: TextField(controller: i < _teamMemberControllers.length ? _teamMemberControllers[i] : null, enabled: canAddPlayer && i < _teamMemberControllers.length, decoration: InputDecoration(labelText: i < currentEvent!.teamSize ? '${i + 1}번 선수 이름(부수)' : '예비 선수 이름(부수)', border: const OutlineInputBorder()), onChanged: (value) { if (value.trim().isEmpty) setState(() {}); })), if (i < _teamMemberControllers.length && _teamMemberControllers[i].text.trim().isNotEmpty && canAddPlayer) IconButton(icon: const Icon(Icons.clear, size: 20, color: Colors.red), onPressed: () => setState(() => _teamMemberControllers[i].clear()), tooltip: '삭제')]))))
          ] else ...[
            Row(children: [Expanded(child: TextField(controller: _nameController, enabled: canAddPlayer, decoration: const InputDecoration(labelText: '이름(부수)', border: OutlineInputBorder(), hintText: '이름 입력 (DB에서 검색됨)'))), const SizedBox(width: 20), Expanded(child: TextField(controller: _affController, enabled: canAddPlayer, decoration: const InputDecoration(labelText: '소속 클럽명', border: OutlineInputBorder())))])
          ],
          const SizedBox(height: 32),
          ElevatedButton.icon(onPressed: canAddPlayer ? _addPlayer : null, icon: const Icon(Icons.person_add_alt_1), label: const Text('참가 명단에 추가하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B6B), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))
        ]))
      ),
      if (_showAutoComplete && !isTeam) Positioned(top: 145, left: 32, right: 32, child: Material(elevation: 8, borderRadius: BorderRadius.circular(8), child: Container(constraints: const BoxConstraints(maxHeight: 250), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8), color: Colors.white), child: ListView.separated(shrinkWrap: true, padding: EdgeInsets.zero, itemCount: _searchedMasterPlayers.length, separatorBuilder: (ctx, i) => const Divider(height: 1), itemBuilder: (ctx, idx) { final p = _searchedMasterPlayers[idx]; return ListTile(leading: const Icon(Icons.person_search, color: Color(0xFF1A535C)), title: Text("${p.name} (${p.tier})", style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text("${p.city} - ${p.affiliation}"), trailing: const Text('선택하기', style: TextStyle(color: Colors.blue, fontSize: 12)), onTap: () => _selectMasterPlayer(p)); }))))
    ]);
  }

  Widget _buildPlayerListArea(double rightPanelWidth, {required bool isPanelExpanded}) {
    if (currentEvent == null) return Container(color: Colors.white);
    return Container(color: Colors.white, child: Column(children: [
      Padding(padding: const EdgeInsets.all(24), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('참가 관리', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFF0F4F8), borderRadius: BorderRadius.circular(20)), child: Text('총 ${currentEvent!.players.length}명', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A535C), fontSize: 13)))])),
      const Divider(height: 1),
      TabBar(controller: _playerTabController, labelColor: const Color(0xFF1A535C), unselectedLabelColor: Colors.grey, indicatorColor: const Color(0xFF1A535C), tabs: const [Tab(text: '참가 현황'), Tab(text: '선수 선택')]),
      const Divider(height: 1),
      Expanded(child: TabBarView(controller: _playerTabController, children: [_buildParticipantTab(isPanelExpanded: isPanelExpanded), _buildPlayerSelectTab(isPanelExpanded: isPanelExpanded)]))
    ]));
  }

  Widget _buildParticipantTab({required bool isPanelExpanded}) {
    final playerCount = currentEvent!.players.length; final isTeam = currentEvent!.teamSize > 1; final int columnCount = isPanelExpanded ? 4 : 3;
    return Column(key: ValueKey('participant_list_$playerCount'), children: [
      Expanded(child: playerCount == 0 ? const Center(child: Text('참가 명단이 비어 있습니다.', style: TextStyle(color: Colors.grey))) : GridView.builder(key: ValueKey('participant_grid_$playerCount'), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2), gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columnCount, childAspectRatio: isTeam ? 2.0 : 3.4, crossAxisSpacing: 8, mainAxisSpacing: 4), itemCount: playerCount, itemBuilder: (ctx, index) {
        if (index >= currentEvent!.players.length) return const SizedBox.shrink();
        final p = currentEvent!.players[index]; final displayIndex = currentEvent!.players.length - index; final capturedPlayer = p;
        void showActionMenu() {
          if (!ctx.mounted) return;
          showModalBottomSheet(context: ctx, builder: (sheetCtx) => SafeArea(child: Wrap(children: [ListTile(leading: const Icon(Icons.edit), title: const Text('수정'), onTap: () { Navigator.pop(sheetCtx); if (!mounted) return; _loadTeamToInputFields(capturedPlayer); }), ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('삭제', style: TextStyle(color: Colors.red)), onTap: () { Navigator.pop(sheetCtx); if (!mounted) return; _secureSettingUpdate(() { currentEvent!.players.removeWhere((e) => e.id == capturedPlayer.id); saveData(); }, isPlayerAction: true); })])));
        }
        if (isTeam) {
          final teamMembers = p.name.split(', ').map((s) => s.trim()).toList();
          return Card(elevation: 1, margin: EdgeInsets.zero, child: InkWell(onTap: () => _loadTeamToInputFields(p), child: Padding(padding: const EdgeInsets.all(5.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Row(children: [GestureDetector(onTap: showActionMenu, child: CircleAvatar(backgroundColor: const Color(0xFF1A535C), radius: 12, child: Text('$displayIndex', style: const TextStyle(color: Colors.white, fontSize: 8)))), const SizedBox(width: 6), Expanded(child: Text(p.affiliation, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1A535C)), maxLines: 1, overflow: TextOverflow.ellipsis))]), const SizedBox(height: 3), ...List.generate((teamMembers.length / 2).ceil(), (rowIndex) { if (rowIndex >= 3) return const SizedBox.shrink(); final startIdx = rowIndex * 2; final endIdx = (startIdx + 2 < teamMembers.length) ? startIdx + 2 : teamMembers.length; return Padding(padding: const EdgeInsets.only(left: 30, bottom: 0.5), child: Row(children: [Expanded(child: Text(teamMembers[startIdx], style: const TextStyle(fontSize: 10, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis)), if (endIdx > startIdx + 1) ...[const SizedBox(width: 4), Expanded(child: Text(teamMembers[startIdx + 1], style: const TextStyle(fontSize: 10, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis))]])); })]))));
        }
        return Card(elevation: 1, margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), child: Row(children: [GestureDetector(onTap: showActionMenu, child: CircleAvatar(backgroundColor: const Color(0xFF1A535C), radius: 16, child: Text('$displayIndex', style: const TextStyle(color: Colors.white, fontSize: 10)))), const SizedBox(width: 10), Expanded(child: FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown, child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(p.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis), Text(p.affiliation, style: const TextStyle(fontSize: 12, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis)])))])));
      })),
      Padding(padding: const EdgeInsets.all(24), child: ElevatedButton(onPressed: currentEvent!.players.length < 2 ? null : _startTournament, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A535C), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 70), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text('예선 대진표 관리 시작', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), SizedBox(width: 12), Icon(Icons.arrow_forward_rounded)])))
    ]);
  }

  Widget _buildPlayerSelectTab({required bool isPanelExpanded}) {
    final q = _playerSelectQuery.toLowerCase(); final allowedTiers = currentEvent!.settings.allowedTiers;
    List<MasterPlayer> candidates = _allMasterPlayers.where((p) { if (q.isNotEmpty && !p.city.toLowerCase().contains(q) && !p.affiliation.toLowerCase().contains(q) && !p.name.toLowerCase().contains(q)) return false; if (allowedTiers.isNotEmpty && !allowedTiers.contains(p.tier)) return false; return true; }).toList();
    final bool isTeam = currentEvent!.teamSize > 1;
    // 본선이 시작되었는지 확인
    final bool isKnockoutStarted = currentEvent!.knockoutRounds != null && currentEvent!.knockoutRounds!.isNotEmpty;
    // 예선전 게임이 모두 종료되었는지 확인
    final groups = currentEvent!.groups ?? [];
    final bool isSkipMode = currentEvent!.settings.skipGroupStage;
    bool canProceed = false;
    if (isSkipMode) { canProceed = true; }
    else {
      canProceed = groups.isNotEmpty &&
                   groups.every((g) => g.matches.isNotEmpty &&
                   g.matches.every((m) => m.status == MatchStatus.completed || m.status == MatchStatus.withdrawal));
    }
    // 선수 추가 가능 여부: 본선이 시작되지 않았고, 예선전 게임이 모두 종료되지 않은 상태
    final bool canAddPlayer = !isKnockoutStarted && (isSkipMode || !canProceed || groups.isEmpty);
    
    final int columnCount = isPanelExpanded ? 4 : 3;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(24, 16, 24, 8), child: TextField(decoration: const InputDecoration(labelText: '지역 / 동호회 / 이름 검색', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true), onChanged: (v) => setState(() => _playerSelectQuery = v))),
      if (isTeam) const Padding(padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4), child: Text('※ 단체전: 선수를 선택하면 입력칸에 자동으로 등록됩니다.', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold))),
      if (!canAddPlayer) const Padding(padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4), child: Text('※ 본선이 시작되어 선수를 추가할 수 없습니다.', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold))),
      const Divider(height: 1),
      Expanded(child: candidates.isEmpty ? const Center(child: Text('검색 결과가 없습니다.', style: TextStyle(color: Colors.grey))) : GridView.builder(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2), gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columnCount, childAspectRatio: 3.4, crossAxisSpacing: 8, mainAxisSpacing: 4), itemCount: candidates.length, itemBuilder: (ctx, idx) { final p = candidates[idx]; final String displayName = '${p.name} (${p.tier})'; final bool isAlreadyRegistered = isTeam ? _isPlayerAlreadyRegistered(displayName) : currentEvent!.players.any((e) => e.name == displayName); final circleColor = isAlreadyRegistered ? Colors.blue : const Color(0xFF1A535C); final bool canAdd = canAddPlayer && !isAlreadyRegistered; return Card(elevation: 1, margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), child: Row(children: [GestureDetector(onTap: canAdd ? () { if (isTeam) { _addPlayerToTeamInput(p); } else { _secureSettingUpdate(() { currentEvent!.players.insert(0, Player(id: p.id != null ? p.id!.toString() : uuid.v4(), name: displayName, affiliation: p.affiliation.isNotEmpty ? p.affiliation : (p.city.isNotEmpty ? p.city : '개인'))); saveData(); }, isPlayerAction: true); } } : null, child: CircleAvatar(backgroundColor: circleColor, radius: 16, child: Text(p.playerNumber.isNotEmpty ? p.playerNumber : '${idx + 1}', style: const TextStyle(color: Colors.white, fontSize: 10)))), const SizedBox(width: 10), Expanded(child: FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown, child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(displayName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis), Text('${p.city} · ${p.affiliation}', style: const TextStyle(fontSize: 12, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis)])))]))); }))
    ]);
  }

  void _handleEditPlayer(int index, Player player) {
    bool isKnockoutStarted = currentEvent!.knockoutRounds != null && currentEvent!.knockoutRounds!.isNotEmpty;
    if (isKnockoutStarted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('본선이 시작되어 선수 정보를 수정할 수 없습니다.'), backgroundColor: Colors.redAccent)); return; }
    bool isTeam = currentEvent!.teamSize > 1; final editNameController = TextEditingController(text: player.name); final editAffController = TextEditingController(text: player.affiliation);
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(isTeam ? '팀 정보 수정' : '선수 정보 수정'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: editAffController, decoration: InputDecoration(labelText: isTeam ? '팀명 (클럽명)' : '소속 클럽명')), const SizedBox(height: 12), TextField(controller: editNameController, decoration: InputDecoration(labelText: isTeam ? '팀원 명단' : '이름(부수)'))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')), TextButton(onPressed: () { _secureSettingUpdate(() { final idx = currentEvent!.players.indexWhere((e) => e.id == player.id); if (idx >= 0) { currentEvent!.players[idx] = Player(id: player.id, name: editNameController.text.trim(), affiliation: editAffController.text.trim()); } saveData(); Navigator.pop(ctx); }, isPlayerAction: true); }, child: const Text('수정'))]));
  }

  void _addPlayer() {
    // 본선이 시작되었는지 확인
    final bool isKnockoutStarted = currentEvent!.knockoutRounds != null && currentEvent!.knockoutRounds!.isNotEmpty;
    // 예선전 게임이 모두 종료되었는지 확인
    final groups = currentEvent!.groups ?? [];
    final bool isSkipMode = currentEvent!.settings.skipGroupStage;
    bool canProceed = false;
    if (isSkipMode) { canProceed = true; }
    else {
      canProceed = groups.isNotEmpty &&
                   groups.every((g) => g.matches.isNotEmpty &&
                   g.matches.every((m) => m.status == MatchStatus.completed || m.status == MatchStatus.withdrawal));
    }
    // 선수 추가 가능 여부: 본선이 시작되지 않았고, 예선전 게임이 모두 종료되지 않은 상태
    final bool canAddPlayer = !isKnockoutStarted && (isSkipMode || !canProceed || groups.isEmpty);
    
    if (!canAddPlayer) { 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('본선 토너먼트가 시작되어 선수를 추가할 수 없습니다.'), backgroundColor: Colors.redAccent)); 
      return; 
    }
    _secureSettingUpdate(() {
      bool isTeam = currentEvent!.teamSize > 1;
      if (isTeam) {
        if (_teamNameController.text.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('팀명을 입력해주세요.'))); return; }
        final teamName = _teamNameController.text.trim();
        if (_editingTeamId != null) {
          final existingTeam = currentEvent!.players.firstWhere((e) => e.id == _editingTeamId, orElse: () => Player(id: '', name: '', affiliation: ''));
          if (existingTeam.affiliation != teamName) { if (currentEvent!.players.any((p) => p.id != _editingTeamId && p.affiliation.trim() == teamName)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('같은 이름의 팀이 등록되었습니다.'), duration: Duration(seconds: 2))); return; } }
        } else { if (currentEvent!.players.any((p) => p.affiliation.trim() == teamName)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('같은 이름의 팀이 등록되었습니다.'), duration: Duration(seconds: 2))); return; } }
        _updateTeamMemberControllers(currentEvent!.teamSize);
        List<String> names = []; final int totalMembers = currentEvent!.teamSize + 1;
        for (int i = 0; i < totalMembers && i < _teamMemberControllers.length; i++) {
          if (_teamMemberControllers[i].text.isNotEmpty) {
            final playerName = _teamMemberControllers[i].text.trim();
            bool isInCurrentEditingTeam = false;
            if (_editingTeamId != null) { final existingTeam = currentEvent!.players.firstWhere((e) => e.id == _editingTeamId, orElse: () => Player(id: '', name: '', affiliation: '')); final existingMembers = existingTeam.name.split(', ').map((s) => s.trim()).toList(); isInCurrentEditingTeam = existingMembers.contains(playerName); }
            if (!isInCurrentEditingTeam && _isPlayerInRegisteredTeams(playerName)) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('[$playerName] 선수는 이미 다른 팀에 등록되어 있습니다.'), duration: const Duration(seconds: 2))); return; }
            names.add(playerName);
          }
        }
        if (names.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('최소 한 명 이상의 선수를 입력해주세요.'))); return; }
        if (_editingTeamId != null) {
          final idx = currentEvent!.players.indexWhere((e) => e.id == _editingTeamId);
          if (idx >= 0) { final existingTeam = currentEvent!.players[idx]; final existingMembers = existingTeam.name.split(', ').map((s) => s.trim()).toList(); for (var newName in names) { if (!existingMembers.contains(newName) && _isPlayerInRegisteredTeams(newName)) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('[$newName] 선수는 이미 다른 팀에 등록되어 있습니다.'), duration: const Duration(seconds: 2))); return; } } currentEvent!.players[idx] = Player(id: _editingTeamId!, name: names.join(', '), affiliation: _teamNameController.text.trim()); }
          _editingTeamId = null;
        } else { currentEvent!.players.insert(0, Player(id: uuid.v4(), name: names.join(', '), affiliation: _teamNameController.text.trim())); }
        _teamNameController.clear(); for (var c in _teamMemberControllers) c.clear(); _editingTeamId = null; currentEvent!.groups = null;
      } else {
        if (_nameController.text.isEmpty) return;
        currentEvent!.players.insert(0, Player(id: uuid.v4(), name: _nameController.text.trim(), affiliation: _affController.text.isEmpty ? '개인' : _affController.text.trim()));
        _nameController.clear(); _affController.clear();
      }
      saveData();
    }, isPlayerAction: true);
  }

  void _deleteEventDialog(int index) async { // [async 추가]
    final event = events[index]; bool hasMatchResults = false;
    if (event.groups != null) { for (var group in event.groups!) { for (var match in group.matches) { if (match.status == MatchStatus.completed) { hasMatchResults = true; break; } } if (hasMatchResults) break; } }
    if (hasMatchResults) { showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('삭제 불가'), content: const Text('예선전 경기 기록이 있어 종목을 삭제할 수 없습니다.\n먼저 경기 결과를 초기화하세요.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인'))])); return; }

    final adminPw = await FileUtils.getAdminPassword(); // [추가]
    if (!mounted) return;

    if (event.players.isNotEmpty) {
      final pwController = TextEditingController();
      showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text('종목 삭제 (주의)'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('[${event.name}] 종목을 삭제하시겠습니까?'),
          const SizedBox(height: 8),
          const Text('※ 등록된 선수 명단이 함께 삭제됩니다.', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(controller: pwController, obscureText: true, decoration: const InputDecoration(labelText: '관리자 비밀번호 입력', border: OutlineInputBorder()))
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(onPressed: () {
            if (pwController.text == adminPw) { // [변경]
              setState(() { events.removeAt(index); selectedEventIdx = 0; });
              saveData();
              Navigator.pop(ctx);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('비밀번호가 틀렸습니다.')));
            }
          }, child: const Text('삭제', style: TextStyle(color: Colors.red)))
        ]
      ));
    } else {
      showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('종목 삭제'), content: Text('[${event.name}] 종목을 삭제하시겠습니까?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')), TextButton(onPressed: () { setState(() { events.removeAt(index); selectedEventIdx = 0; }); saveData(); Navigator.pop(ctx); }, child: const Text('삭제', style: TextStyle(color: Colors.red)))]));
    }
  }

  void _handleEditTitle(File file, String currentTitle) { final editController = TextEditingController(text: currentTitle); showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('대회 이름 수정'), content: TextField(controller: editController, autofocus: true, decoration: const InputDecoration(labelText: '대회 명칭')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')), TextButton(onPressed: () async { if (editController.text.isNotEmpty) { final content = await file.readAsString(); final data = jsonDecode(content); data['title'] = editController.text; await file.writeAsString(jsonEncode(data)); if (currentFileName == file.path.split(Platform.pathSeparator).last) { setState(() { titleController.text = editController.text; }); } Navigator.pop(ctx); } }, child: const Text('수정'))])); }
  void _handleDeleteFile(File file, String fileName) { showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('대회 파일 삭제'), content: const Text('이 대회 데이터를 영구적으로 삭제하시겠습니까?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')), TextButton(onPressed: () { file.deleteSync(); if (currentFileName == fileName) setState(() => currentFileName = null); Navigator.pop(ctx); }, child: const Text('삭제', style: TextStyle(color: Colors.red)))])); }
  void _handleInitialSave() async { final dataPath = await FileUtils.getDataDirPath(); final timestamp = DateTime.now().millisecondsSinceEpoch; currentFileName = 'tournament_$timestamp.json'; await saveData(); setState(() {}); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('대회 파일이 생성되었습니다.'))); }
  void _handleReset() { showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('초기화 확인'), content: const Text('현재 작업 중인 데이터가 초기화됩니다. 새로 시작하시겠습니까?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')), TextButton(onPressed: () { setState(() { events.clear(); currentFileName = null; titleController.text = '새 탁구 대회'; }); Navigator.pop(ctx); }, child: const Text('확인', style: TextStyle(color: Colors.red)))])); }
  void _startTournament() { currentEvent!.groups ??= TournamentLogic.generateGroups(currentEvent!.players, currentEvent!.settings); saveData(); final unchecked = eventUncheckedIdsNotifier.value; final visibleEvents = events.where((e) => !unchecked.contains(e.id)).toList(); final eventsToShow = visibleEvents.isEmpty ? List<TournamentEvent>.from(events) : visibleEvents; int initialIdx = 0; if (selectedEventIdx < events.length) { final currentId = events[selectedEventIdx].id; final idx = eventsToShow.indexWhere((e) => e.id == currentId); if (idx >= 0) initialIdx = idx; } Navigator.push(context, MaterialPageRoute(builder: (context) => GroupStagePage(tournamentBaseTitle: titleController.text, allEvents: eventsToShow, initialEventIdx: initialIdx, onDataChanged: saveData))); }
}
