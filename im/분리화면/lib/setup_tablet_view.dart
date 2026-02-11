import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'tournament_logic.dart';
import 'group_stage_page.dart';

class SetupTabletView extends StatefulWidget {
  const SetupTabletView({super.key});
  @override
  State<SetupTabletView> createState() => _SetupTabletViewState();
}

class _SetupTabletViewState extends State<SetupTabletView> {
  final _uuid = const Uuid();
  final _titleController = TextEditingController(text: '새 탁구 대회');
  final List<TournamentEvent> _events = [];
  int _selectedEventIdx = 0;
  String? _currentFileName;
  List<String> _presets = [];

  // 입력 컨트롤러
  final _nameController = TextEditingController();
  final _affController = TextEditingController();
  final List<TextEditingController> _teamMemberControllers = List.generate(5, (_) => TextEditingController());
  final _teamNameController = TextEditingController();

  TournamentEvent? get _currentEvent => _events.isNotEmpty ? _events[_selectedEventIdx] : null;

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  // --- 기존 로직 함수들 (모바일 버전과 동일) ---
  Future<void> _loadPresets() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/presets.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        setState(() { _presets = List<String>.from(jsonDecode(content)); });
      } else {
        setState(() { _presets = ['남자 단식', '여자 단식', '남자 복식', '여자 복식', '혼합 복식']; });
      }
    } catch (_) {}
  }

  Future<void> _saveData() async {
    if (_currentFileName == null) return;
    try {
      final data = {
        'title': _titleController.text,
        'events': _events.map((e) => _eventToMap(e)).toList(),
      };
      final jsonString = jsonEncode(data);
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_currentFileName');
      await file.writeAsString(jsonString);
    } catch (_) {}
  }

  Map<String, dynamic> _eventToMap(TournamentEvent e) => {
    'id': e.id, 'name': e.name, 'teamSize': e.teamSize, 'groupSize': e.settings.groupSize, 'advancingCount': e.settings.advancingCount,
    'players': e.players.map((p) => {'id': p.id, 'name': p.name, 'affiliation': p.affiliation}).toList(),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      body: Row(
        children: [
          // 1. 왼쪽 사이드바 (대회명 및 종목 선택)
          _buildSidebar(),
          
          // 2. 중앙 영역 (설정 및 입력 창)
          Expanded(
            flex: 4,
            child: _buildMainContent(),
          ),
          
          // 3. 오른쪽 영역 (현재 등록된 명단 현황)
          Expanded(
            flex: 3,
            child: _buildPlayerStatusSide(),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
      color: const Color(0xFF1A535C),
      child: Column(
        children: [
          const SizedBox(height: 50),
          const Icon(Icons.sports_score, color: Colors.white, size: 48),
          const SizedBox(height: 10),
          const Text('탁구 대회 관리 시스템', style: TextStyle(color: Colors.white70, fontSize: 12)),
          const Divider(color: Colors.white24, height: 40, indent: 20, endIndent: 20),
          
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _sidebarMenu(Icons.folder_open, '대회 불러오기', Colors.amber, () {}),
                _sidebarMenu(Icons.save, '현재 상태 저장', Colors.blue, _saveData),
                _sidebarMenu(Icons.refresh, '대회 초기화', Colors.redAccent, () {}),
                const SizedBox(height: 30),
                const Text('진행 종목', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                ..._events.asMap().entries.map((e) => _eventTile(e.key, e.value)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {}, // 종목 추가 로직
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('종목 추가'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white30)),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(20.0),
            child: Text('v1.0.0 (Tablet Mode)', style: TextStyle(color: Colors.white24, fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Widget _sidebarMenu(IconData i, String l, Color c, VoidCallback o) => ListTile(
    leading: Icon(i, color: c, size: 20),
    title: Text(l, style: const TextStyle(color: Colors.white, fontSize: 14)),
    onTap: o,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );

  Widget _eventTile(int idx, TournamentEvent e) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    decoration: BoxDecoration(
      color: _selectedEventIdx == idx ? Colors.white.withOpacity(0.15) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
    ),
    child: ListTile(
      dense: true,
      title: Text(e.name, style: TextStyle(color: Colors.white, fontWeight: _selectedEventIdx == idx ? FontWeight.bold : FontWeight.normal)),
      onTap: () => setState(() => _selectedEventIdx = idx),
      trailing: _selectedEventIdx == idx ? const Icon(Icons.chevron_right, color: Colors.white, size: 16) : null,
    ),
  );

  Widget _buildMainContent() {
    if (_currentEvent == null) return const Center(child: Text('왼쪽 메뉴에서 종목을 선택하거나 추가하세요.'));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopHeader(),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildSettingsCard()),
              const SizedBox(width: 20),
              Expanded(child: _buildExcelCard()),
            ],
          ),
          const SizedBox(height: 24),
          _buildTabletInputCard(),
        ],
      ),
    );
  }

  Widget _buildTopHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleController,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1A535C)),
          decoration: const InputDecoration(border: InputBorder.none, hintText: '대회 제목을 입력하세요'),
        ),
        Text('${_currentEvent!.name} - 설정 및 참가 등록', style: const TextStyle(color: Colors.grey, fontSize: 16)),
      ],
    );
  }

  Widget _buildSettingsCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [Icon(Icons.settings, size: 18), SizedBox(width: 8), Text('경기 규칙 설정', style: TextStyle(fontWeight: FontWeight.bold))]),
            const SizedBox(height: 20),
            _dropdownField('조별 인원', _currentEvent!.settings.groupSize, [3, 4, 5], (v) => setState(() => _currentEvent!.settings.groupSize = v!)),
            const SizedBox(height: 16),
            _dropdownField('본선 진출 인원', _currentEvent!.settings.advancingCount, [1, 2, 3], (v) => setState(() => _currentEvent!.settings.advancingCount = v!)),
          ],
        ),
      ),
    );
  }

  Widget _buildExcelCard() {
    return Card(
      elevation: 0,
      color: const Color(0xFFE8F5E9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.table_view, color: Colors.green, size: 40),
            const SizedBox(height: 12),
            const Text('엑셀 일괄 등록', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            const SizedBox(height: 8),
            const Text('많은 인원을 한 번에 등록하려면\n엑셀 파일을 불러오세요.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), child: const Text('파일 불러오기')),
          ],
        ),
      ),
    );
  }

  Widget _buildTabletInputCard() {
    bool isTeam = _currentEvent!.teamSize > 1;
    return Card(
      elevation: 4,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isTeam ? '단체전 팀 등록' : '개인전 선수 등록', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            if (isTeam) ...[
              TextField(controller: _teamNameController, decoration: const InputDecoration(labelText: '팀명 / 클럽명', border: OutlineInputBorder())),
              const SizedBox(height: 20),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: List.generate(_currentEvent!.teamSize, (i) => SizedBox(
                  width: 200,
                  child: TextField(controller: _teamMemberControllers[i], decoration: InputDecoration(labelText: '${i + 1}번 선수 이름(부수)', border: const OutlineInputBorder())),
                )),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(child: TextField(controller: _nameController, decoration: const InputDecoration(labelText: '선수 이름(부수)', border: OutlineInputBorder()))),
                  const SizedBox(width: 16),
                  Expanded(child: TextField(controller: _affController, decoration: const InputDecoration(labelText: '소속 클럽', border: OutlineInputBorder()))),
                ],
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () {}, // 등록 로직
                icon: const Icon(Icons.person_add),
                label: const Text('명단에 추가하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B6B), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerStatusSide() {
    if (_currentEvent == null) return const SizedBox();
    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)]),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('참가 명단', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFF0F4F8), borderRadius: BorderRadius.circular(20)),
                  child: Text('총 ${_currentEvent!.players.length}명', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A535C))),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _currentEvent!.players.isEmpty
              ? const Center(child: Text('등록된 선수가 없습니다.', style: TextStyle(color: Colors.grey)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _currentEvent!.players.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final p = _currentEvent!.players[index];
                    return ListTile(
                      tileColor: const Color(0xFFF8FAFC),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      leading: CircleAvatar(backgroundColor: Colors.white, child: Text('${index + 1}', style: const TextStyle(fontSize: 12))),
                      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(p.affiliation, style: const TextStyle(fontSize: 12)),
                      trailing: IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent), onPressed: () {}),
                    );
                  },
                ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: ElevatedButton(
              onPressed: _currentEvent!.players.length < 2 ? null : () {}, // 예선 생성 로직
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A535C),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('예선 대진표 생성 및 관리 시작', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdownField(String label, int value, List<int> items, ValueChanged<int?> onChanged) {
    return DropdownButtonFormField<int>(
      value: value,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: items.map((i) => DropdownMenuItem(value: i, child: Text('$i명'))).toList(),
      onChanged: onChanged,
    );
  }
}
