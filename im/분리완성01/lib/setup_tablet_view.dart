import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';
import 'tournament_logic.dart';
import 'group_stage_page.dart';
import 'setup_logic_mixin.dart';

class SetupTabletView extends StatefulWidget {
  const SetupTabletView({super.key});
  @override
  State<SetupTabletView> createState() => _SetupTabletViewState();
}

class _SetupTabletViewState extends State<SetupTabletView> with SetupLogicMixin {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      body: Row(
        children: [
          // 1. 왼쪽 사이드바 (내비게이션 및 종목 선택)
          _buildSidebar(),
          
          // 2. 중앙/오른쪽 메인 콘텐츠
          Expanded(
            child: Row(
              children: [
                Expanded(flex: 3, child: _buildMainInputArea()),
                const VerticalDivider(width: 1),
                Expanded(flex: 2, child: _buildPlayerListArea()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 260,
      color: const Color(0xFF1A535C),
      child: Column(
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.sports_tennis, color: Colors.white, size: 40),
          const SizedBox(height: 10),
          const Text('탁구 대회 관리', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(color: Colors.white24, height: 40, indent: 20, endIndent: 20),
          _sidebarItem(Icons.folder_open, '대회 목록', Colors.amber, _showLoadDialog),
          _sidebarItem(Icons.save, '데이터 저장', Colors.blue, saveData),
          _sidebarItem(Icons.refresh, '초기화', Colors.redAccent, () => setState(() => events.clear())),
          const Spacer(),
          const Padding(padding: EdgeInsets.all(16.0), child: Text('Tablet Version 1.0', style: TextStyle(color: Colors.white24))),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String label, Color color, VoidCallback onTap) => ListTile(
    leading: Icon(icon, color: color),
    title: Text(label, style: const TextStyle(color: Colors.white)),
    onTap: onTap,
  );

  Widget _buildMainInputArea() {
    if (currentEvent == null) return const Center(child: Text('먼저 종목을 추가해주세요.'));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: titleController,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(border: InputBorder.none, hintText: '대회 명칭'),
          ),
          const SizedBox(height: 24),
          _buildEventSelector(),
          const SizedBox(height: 32),
          _buildPlayerInputCard(),
        ],
      ),
    );
  }

  Widget _buildEventSelector() {
    return Wrap(
      spacing: 8,
      children: [
        ...events.asMap().entries.map((e) => ChoiceChip(
          label: Text(e.value.name),
          selected: selectedEventIdx == e.key,
          onSelected: (v) => setState(() => selectedEventIdx = e.key),
        )),
        ActionChip(label: const Text('+ 종목 추가'), onPressed: _addNewEventDialog),
      ],
    );
  }

  Widget _buildPlayerInputCard() {
    bool isTeam = currentEvent!.teamSize > 1;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (isTeam) ...[
              TextField(controller: _teamNameController, decoration: const InputDecoration(labelText: '팀명')),
              const SizedBox(height: 16),
              // 단체전 팀원 입력 로직...
            ] else ...[
              Row(
                children: [
                  Expanded(child: TextField(controller: _nameController, decoration: const InputDecoration(labelText: '이름(부수)'))),
                  const SizedBox(width: 16),
                  Expanded(child: TextField(controller: _affController, decoration: const InputDecoration(labelText: '소속'))),
                ],
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _addPlayer,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              child: const Text('명단 추가'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerListArea() {
    if (currentEvent == null) return const SizedBox();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text('참가 명단 (${currentEvent!.players.length}명)', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: currentEvent!.players.length,
            itemBuilder: (context, index) {
              final p = currentEvent!.players[index];
              return ListTile(title: Text(p.name), subtitle: Text(p.affiliation));
            },
          ),
        ),
        _buildBottomAction(),
      ],
    );
  }

  Widget _buildBottomAction() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: ElevatedButton(
        onPressed: currentEvent!.players.length < 2 ? null : _startTournament,
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A535C), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 60)),
        child: const Text('예선 관리 시작'),
      ),
    );
  }

  void _addPlayer() {
    if (_nameController.text.isNotEmpty) {
      setState(() {
        currentEvent!.players.insert(0, Player(id: uuid.v4(), name: _nameController.text, affiliation: _affController.text));
        _nameController.clear();
      });
      saveData();
    }
  }

  void _addNewEventDialog() {
    // 종목 추가 다이얼로그 로직...
  }

  void _showLoadDialog() async {
    // 저장된 파일 목록 보여주기 및 로드...
  }

  void _startTournament() {
    currentEvent!.groups ??= TournamentLogic.generateGroups(currentEvent!.players, currentEvent!.settings);
    saveData();
    Navigator.push(context, MaterialPageRoute(builder: (context) => GroupStagePage(
      tournamentBaseTitle: titleController.text,
      allEvents: events,
      initialEventIdx: selectedEventIdx,
      onDataChanged: saveData,
    )));
  }
}
