import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'ctrl_wheel_zoom.dart';
import 'models.dart';
import 'tournament_logic.dart';
import 'knockout_page.dart';
import 'match_sheet_page.dart';
import 'main.dart';
import 'file_utils.dart'; // [추가]

class GroupStageTabletView extends StatefulWidget {
  final String tournamentBaseTitle;
  final List<TournamentEvent> allEvents;
  final int initialEventIdx;
  final VoidCallback onDataChanged;

  const GroupStageTabletView({
    super.key,
    required this.tournamentBaseTitle,
    required this.allEvents,
    required this.initialEventIdx,
    required this.onDataChanged,
  });

  @override
  State<GroupStageTabletView> createState() => _GroupStageTabletViewState();
}

class _GroupStageTabletViewState extends State<GroupStageTabletView> with TickerProviderStateMixin {
  late int _currentEventIdx;
  final Map<int, List<Player>> _manualRankings = {};
  final List<Player> _waitingPlayers = [];
  bool _stickyPanelVisible = true;
  double _stickyPanelOpacity = 0.5;
  String _rightPanelSearchQuery = "";
  final List<GlobalKey> _groupCardKeys = [];
  late TabController _rightTabController;

  TournamentEvent get _currentEvent => widget.allEvents[_currentEventIdx];
  bool get _isTeamMatch => _currentEvent.teamSize > 1;

  @override
  void initState() {
    super.initState();
    _currentEventIdx = widget.initialEventIdx;
    _rightTabController = TabController(length: 2, vsync: this);
    _refreshRankings();
    _findWaitingPlayers();
  }

  @override
  void dispose() {
    _rightTabController.dispose();
    super.dispose();
  }

  void _findWaitingPlayers() {
    _waitingPlayers.clear();
    if (_currentEvent.groups == null) return;
    final assignedIds = _currentEvent.groups!.expand((g) => g.players).map((p) => p.id).toSet();
    for (var p in _currentEvent.players) {
      if (!assignedIds.contains(p.id)) _waitingPlayers.add(p);
    }
  }

  void _refreshRankings() {
    _manualRankings.clear();
    if (_currentEvent.groups != null) {
      for (int i = 0; i < _currentEvent.groups!.length; i++) {
        _manualRankings[i] = TournamentLogic.getGroupRankings(_currentEvent.groups![i]);
      }
    }
  }

  bool _hasMatchRecord(Player p, Group g) {
    return g.matches.any((m) => 
      (m.player1?.id == p.id || m.player2?.id == p.id) && 
      (m.status == MatchStatus.completed || m.status == MatchStatus.withdrawal)
    );
  }

  void _addNewGroup() {
    setState(() {
      _currentEvent.groups ??= [];
      int nextGroupNum = _currentEvent.groups!.length + 1;
      _currentEvent.groups!.add(Group(name: '예선 $nextGroupNum조', players: [], matches: []));
      _refreshRankings();
    });
    widget.onDataChanged();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('예선 ${_currentEvent.groups!.length}조가 생성되었습니다.')));
  }

  @override
  Widget build(BuildContext context) {
    final groups = _currentEvent.groups ?? [];
    final bool isSkipMode = _currentEvent.settings.skipGroupStage;
    bool canProceed = false;
    if (isSkipMode) { canProceed = true; }
    else {
      canProceed = groups.isNotEmpty && 
                   groups.every((g) => g.matches.isNotEmpty && 
                   g.matches.every((m) => m.status == MatchStatus.completed || m.status == MatchStatus.withdrawal));
    }
    bool hasWaiting = _waitingPlayers.isNotEmpty;

    return PopScope(
      canPop: !hasWaiting,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && hasWaiting) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('대기 명단에 선수가 있습니다. 모든 선수를 조에 배정해주세요.')));
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4F8),
        appBar: AppBar(
          elevation: 0, backgroundColor: const Color(0xFF1A535C), foregroundColor: Colors.white,
          title: Text('${widget.tournamentBaseTitle} - ${_currentEvent.name}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('메인화면', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                if (_currentEvent.knockoutRounds != null && _currentEvent.knockoutRounds!.isNotEmpty) {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => KnockoutPage(tournamentTitle: '${widget.tournamentBaseTitle} - ${_currentEvent.name}', rounds: _currentEvent.knockoutRounds!, onDataChanged: widget.onDataChanged, events: widget.allEvents)));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('본선 대진을 먼저 생성해주세요. (본선 진출 생성 버튼)')));
                }
              },
              child: const Text('본선토너먼트', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            const VerticalDivider(color: Colors.white24, indent: 15, endIndent: 15),
            _appBarAction(Icons.group_add_outlined, '조 추가', Colors.cyanAccent, (_currentEvent.knockoutRounds == null || _currentEvent.knockoutRounds!.isEmpty) ? _addNewGroup : null),
            const VerticalDivider(color: Colors.white24, indent: 15, endIndent: 15),
            if (!isSkipMode) IconButton(icon: const Icon(Icons.casino_outlined, color: Colors.orangeAccent), onPressed: hasWaiting ? null : _fillRandomScores, tooltip: '테스트 점수 입력'),
            _appBarAction(Icons.assignment_outlined, '기록지 출력', Colors.amber, hasWaiting ? null : () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => MatchSheetPage(tournamentTitle: '${widget.tournamentBaseTitle} - ${_currentEvent.name}', groups: _currentEvent.groups!, knockoutRounds: _currentEvent.knockoutRounds)));
            }),
            if (groups.isNotEmpty) ...[
              const VerticalDivider(color: Colors.white24, indent: 15, endIndent: 15),
              IconButton(icon: Icon(_stickyPanelVisible ? Icons.visibility : Icons.visibility_off, color: Colors.white), tooltip: _stickyPanelVisible ? '진행 현황 패널 숨기기' : '진행 현황 패널 보기', onPressed: () => setState(() => _stickyPanelVisible = !_stickyPanelVisible)),
            ],
            const SizedBox(width: 10),
          ],
        ),
        body: groups.isEmpty
            ? Column(children: [_buildEventTabBar(), const Expanded(child: Center(child: Text('예선 조가 없습니다. [조 추가]를 눌러주세요.')))])
            : Builder(
                builder: (context) {
                  while (_groupCardKeys.length < groups.length) { _groupCardKeys.add(GlobalKey()); }
                  return Stack(
                    children: [
                      CustomScrollView(
                        slivers: [
                          SliverPersistentHeader(pinned: true, delegate: _StickyHeaderDelegate(height: 60, selectedIndex: _currentEventIdx, child: Material(elevation: 2, color: Colors.white, child: _buildEventTabBar()))),
                          if (hasWaiting) SliverToBoxAdapter(child: _buildWaitingListArea()),
                          SliverPadding(
                            padding: const EdgeInsets.all(20),
                            sliver: SliverToBoxAdapter(
                              child: CtrlWheelZoomScope(
                                child: InteractiveViewer(
                                  minScale: 1.0, maxScale: 3.0, scaleEnabled: false, panEnabled: true,
                                  child: Center(child: Wrap(spacing: 20, runSpacing: 20, children: List.generate(groups.length, (index) => SizedBox(key: _groupCardKeys[index], width: _isTeamMatch ? ((MediaQuery.of(context).size.width - 140) / 3) * 1.3 : (MediaQuery.of(context).size.width - 140) / 4, child: _buildGroupCard(groups[index], index))))),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_stickyPanelVisible) Positioned(right: 0, top: 60, bottom: 0, child: LayoutBuilder(builder: (context, constraints) => SizedBox(width: 200, height: constraints.maxHeight, child: _buildRightStickyProgressPanel(groups)))),
                    ],
                  );
                },
              ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
          decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))]),
          child: ElevatedButton.icon(onPressed: (!canProceed || hasWaiting) ? null : _generateKnockout, icon: Icon(hasWaiting ? Icons.warning_amber_rounded : Icons.account_tree_rounded), label: Text(hasWaiting ? '대기 명단 배정 필요' : '본선 진출 생성 및 이동', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: hasWaiting ? Colors.redAccent.shade100 : const Color(0xFF1A535C), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 64), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
        ),
      ),
    );
  }

  Widget _appBarAction(IconData icon, String label, Color color, VoidCallback? onTap) => TextButton.icon(onPressed: onTap, icon: Icon(icon, color: color, size: 20), label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)));

  Widget _buildEventTabBar() => Container(height: 60, color: Colors.white, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), itemCount: widget.allEvents.length, itemBuilder: (context, index) {
    final isSelected = _currentEventIdx == index;
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10), child: ChoiceChip(label: Text(widget.allEvents[index].name), selected: isSelected, selectedColor: const Color(0xFF1A535C), labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black, fontWeight: FontWeight.bold), onSelected: (v) { if (v) { if (_waitingPlayers.isNotEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('대기 명단 선수를 먼저 배정해주세요.'))); return; } setState(() { _currentEventIdx = index; _refreshRankings(); _findWaitingPlayers(); }); } }));
  }));

  Widget _buildWaitingListArea() => Container(
    width: double.infinity, margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.hourglass_empty_rounded, color: Colors.orange, size: 20), const SizedBox(width: 8), Text('대기 명단 (${_waitingPlayers.length}명)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900, fontSize: 16)), const Spacer(), const Text('선수 이름을 클릭하여 조에 배정하세요.', style: TextStyle(color: Colors.orange, fontSize: 12))]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: _waitingPlayers.map((p) => ActionChip(label: Text(_isTeamMatch ? p.affiliation : p.name), onPressed: () => _showAssignToGroupDialog(p))).toList()),
    ]),
  );

  Widget _buildRightStickyProgressPanel(List<Group> groups) {
    return Opacity(
      opacity: _stickyPanelOpacity.clamp(0.0, 1.0),
      child: Material(
        elevation: 4, color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: const Color(0xFF1A535C),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TabBar(controller: _rightTabController, tabs: const [Tab(text: '참가 현황'), Tab(text: '선수 선택')], labelColor: Colors.white, unselectedLabelColor: Colors.white70, indicatorColor: Colors.cyanAccent, indicatorWeight: 3, labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Row(children: [const Text('투명도', style: TextStyle(color: Colors.white70, fontSize: 11)), Expanded(child: Slider(value: _stickyPanelOpacity, onChanged: (v) => setState(() => _stickyPanelOpacity = v), activeColor: Colors.white, inactiveColor: Colors.white24))])),
                ],
              ),
            ),
            Expanded(child: TabBarView(controller: _rightTabController, children: [_buildProgressTab(groups), _buildPlayerSelectionTab()])),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressTab(List<Group> groups) {
    return SingleChildScrollView(padding: const EdgeInsets.all(10), child: Wrap(spacing: 4, runSpacing: 4, children: List.generate(groups.length, (gIdx) => SizedBox(width: 42, height: 42, child: _buildGroupProgressBox(groups[gIdx], gIdx + 1, onTap: () => _scrollToGroupCard(gIdx))))));
  }

  Widget _buildPlayerSelectionTab() {
    final query = _rightPanelSearchQuery.toLowerCase(); List<Map<String, dynamic>> allPlayersInfo = [];
    if (_currentEvent.groups != null) { for (int i = 0; i < _currentEvent.groups!.length; i++) { for (var p in _currentEvent.groups![i].players) { if (query.isEmpty || p.name.toLowerCase().contains(query) || p.affiliation.toLowerCase().contains(query)) { allPlayersInfo.add({'player': p, 'groupIdx': i, 'groupName': _currentEvent.groups![i].name}); } } } }
    for (var p in _waitingPlayers) { if (query.isEmpty || p.name.toLowerCase().contains(query) || p.affiliation.toLowerCase().contains(query)) { allPlayersInfo.add({'player': p, 'groupIdx': -1, 'groupName': '대기 명단'}); } }
    return Column(children: [
      Padding(padding: const EdgeInsets.all(8.0), child: TextField(style: const TextStyle(fontSize: 13), decoration: InputDecoration(hintText: '이름/소속 검색', prefixIcon: const Icon(Icons.search, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(vertical: 8)), onChanged: (v) => setState(() => _rightPanelSearchQuery = v))),
      Expanded(child: ListView.separated(padding: EdgeInsets.zero, itemCount: allPlayersInfo.length, separatorBuilder: (ctx, i) => const Divider(height: 1), itemBuilder: (ctx, idx) { final info = allPlayersInfo[idx]; final Player p = info['player']; final String gName = info['groupName']; final int gIdx = info['groupIdx']; return ListTile(dense: true, visualDensity: VisualDensity.compact, title: Text(_isTeamMatch ? p.affiliation : p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(gName, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)), onTap: () { if (gIdx >= 0) { _scrollToGroupCard(gIdx); } else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('대기 명단에 있는 선수입니다.'), duration: Duration(seconds: 1))); } }); }))
    ]);
  }

  void _scrollToGroupCard(int groupIndex) { if (groupIndex < 0 || groupIndex >= _groupCardKeys.length) return; final key = _groupCardKeys[groupIndex]; final ctx = key.currentContext; if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.2, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut); }

  Widget _buildGroupProgressBox(Group group, int groupNumber, {VoidCallback? onTap}) {
    final allDone = group.matches.isEmpty || group.matches.every((m) => m.status == MatchStatus.completed || m.status == MatchStatus.withdrawal);
    final box = Container(width: 36, height: 36, alignment: Alignment.center, decoration: BoxDecoration(color: allDone ? Colors.blue : Colors.grey.shade200, borderRadius: BorderRadius.circular(8), border: Border.all(color: allDone ? Colors.blue.shade700 : Colors.grey.shade400)), child: Text('$groupNumber', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: allDone ? Colors.white : Colors.grey.shade700)));
    if (onTap == null) return box;
    return Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(8), onTap: onTap, child: box));
  }

  void _showAssignToGroupDialog(Player p) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('${p.name} 배정할 조 선택'),
      content: SizedBox(width: double.maxFinite, child: Column(mainAxisSize: MainAxisSize.min, children: [
        ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4), child: ListView.builder(shrinkWrap: true, itemCount: _currentEvent.groups?.length ?? 0, itemBuilder: (ctx, idx) {
          final g = _currentEvent.groups![idx]; final canAdd = g.players.length < _currentEvent.settings.groupSize;
          return ListTile(title: Text(g.name), subtitle: Text('${g.players.length}명 배정됨'), trailing: Icon(canAdd ? Icons.add_circle_outline : Icons.warning, color: canAdd ? Colors.green : Colors.orange), onTap: () { setState(() { g.players.add(p); _waitingPlayers.remove(p); TournamentLogic.syncGroupMatches(g, idx + 1); _refreshRankings(); }); widget.onDataChanged(); Navigator.pop(ctx); });
        })),
        const Divider(),
        ListTile(leading: const Icon(Icons.add_box_outlined, color: Colors.blue), title: const Text('새로운 조 생성 및 배정', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)), onTap: () { Navigator.pop(ctx); _addNewGroup(); final lastIdx = _currentEvent.groups!.length - 1; final newGroup = _currentEvent.groups![lastIdx]; setState(() { newGroup.players.add(p); _waitingPlayers.remove(p); TournamentLogic.syncGroupMatches(newGroup, lastIdx + 1); _refreshRankings(); }); widget.onDataChanged(); }),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소'))],
    ));
  }

  Widget _buildGroupCard(Group group, int groupIdx) {
    final rankings = _manualRankings[groupIdx] ?? TournamentLogic.getGroupRankings(group);
    final maxGroupSize = _currentEvent.settings.groupSize; final isUnder = group.players.length < maxGroupSize;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: isUnder ? 4 : 1,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20), decoration: BoxDecoration(color: isUnder ? Colors.red.shade50 : const Color(0xFFF8F9FA), borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(group.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isUnder ? Colors.red : const Color(0xFF1A535C))),
            Row(children: [Text('${group.players.length} / $maxGroupSize명', style: TextStyle(color: isUnder ? Colors.red : Colors.grey, fontSize: 14, fontWeight: isUnder ? FontWeight.bold : FontWeight.normal)), const SizedBox(width: 10), IconButton(icon: const Icon(Icons.print, color: Colors.blue, size: 24), onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (context) => MatchSheetPage(tournamentTitle: '${widget.tournamentBaseTitle} - ${_currentEvent.name}', groups: [group], knockoutRounds: _currentEvent.knockoutRounds))); }, padding: EdgeInsets.zero, constraints: const BoxConstraints())]),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(16), child: Column(children: [_buildRankingTable(rankings, group, groupIdx), const SizedBox(height: 16), const Divider(), ...group.matches.map((m) => _buildMatchTile(m, group))])),
      ]),
    );
  }

  Widget _buildRankingTable(List<Player> rankings, Group group, int groupIdx) {
    final stats = TournamentLogic.getRankingStats(group);
    return Table(border: TableBorder.all(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)), columnWidths: const { 0: IntrinsicColumnWidth(), 1: FlexColumnWidth(3), 2: FixedColumnWidth(42), 3: FixedColumnWidth(42), 4: FixedColumnWidth(42), 5: FixedColumnWidth(42), 6: IntrinsicColumnWidth() }, defaultVerticalAlignment: TableCellVerticalAlignment.middle, children: [
      TableRow(decoration: BoxDecoration(color: Colors.grey.shade100), children: [ for (var h in ['순위', '이름(소속)', '승', '득', '실', '득실', '조정']) _tableCell(h, isBold: true, fontSize: 12) ]),
      ...rankings.asMap().entries.map((e) {
        final index = e.key; final p = e.value; final s = stats[p]!; final isAdv = index < _currentEvent.settings.advancingCount;
        return TableRow(children: [
          _tableCell('${index + 1}', color: isAdv ? Colors.blue : Colors.black, isBold: isAdv),
          TableCell(child: InkWell(onTap: () => _showPlayerActionDialog(p, groupIdx), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10), child: Text(_isTeamMatch ? p.affiliation : "${p.name}(${p.affiliation})", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dotted))))),
          _tableCell('${s['wins']}'), _tableCell('${s['won']}'), _tableCell('${s['lost']}'), _tableCell('${s['diff']}'),
          TableCell(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [GestureDetector(onTap: index == 0 ? null : () => _moveRank(groupIdx, index, -1), child: Icon(Icons.arrow_upward, size: 18, color: index == 0 ? Colors.grey.shade200 : Colors.blue)), const SizedBox(width: 1), GestureDetector(onTap: index == rankings.length - 1 ? null : () => _moveRank(groupIdx, index, 1), child: Icon(Icons.arrow_downward, size: 18, color: index == rankings.length - 1 ? Colors.grey.shade200 : Colors.red))])))
        ]);
      }),
    ]);
  }

  Widget _tableCell(String t, {bool isBold = false, Color color = Colors.black, double fontSize = 13}) => TableCell(child: Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2), child: Text(t, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color, fontSize: fontSize)))));

  Widget _buildMatchTile(Match m, Group group) {
    if (!_isTeamMatch) {
      return Container(margin: const EdgeInsets.only(bottom: 4), decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(8)), child: ListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12), visualDensity: VisualDensity.compact, title: Row(children: [Expanded(child: Text("${m.player1?.name ?? 'BYE'} (${m.player1?.affiliation ?? ''})", textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), margin: const EdgeInsets.symmetric(horizontal: 10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)), child: Text('${m.score1} : ${m.score2}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.redAccent))), Expanded(child: Text("${m.player2?.name ?? 'BYE'} (${m.player2?.affiliation ?? ''})", textAlign: TextAlign.left, style: const TextStyle(fontSize: 13)))]), onTap: () => _maybeShowScoreDialog(m, group)));
    }
    return InkWell(
      onTap: () => _maybeShowScoreDialog(m, group),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5, offset: const Offset(0, 2))]),
        child: Column(children: [
          Row(children: [Expanded(child: _clubLabel(m.player1?.affiliation ?? 'BYE')), const SizedBox(width: 40), Expanded(child: _clubLabel(m.player2?.affiliation ?? 'BYE'))]),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: _playerNamesGrid(m.player1?.name ?? '')), Container(width: 80, alignment: Alignment.center, child: Text(m.status == MatchStatus.withdrawal ? '기권' : '${m.score1} : ${m.score2}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.redAccent))), Expanded(child: _playerNamesGrid(m.player2?.name ?? ''))]),
        ]),
      ),
    );
  }

  Widget _clubLabel(String text) => Container(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16), decoration: const ShapeDecoration(color: Color(0xFF1A535C), shape: StadiumBorder()), child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis));

  Widget _playerNamesGrid(String names) {
    if (names.isEmpty) return const SizedBox.shrink();
    List<String> list = names.split(',').map((s) => s.trim()).toList();
    List<Widget> rows = [];
    for (int i = 0; i < list.length && i < 6; i += 2) {
      rows.add(Padding(padding: const EdgeInsets.only(bottom: 2), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(list[i], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)), if (i + 1 < list.length) ...[const SizedBox(width: 8), Text(list[i + 1], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87))]])));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  void _showPlayerActionDialog(Player player, int currentGroupIdx) {
    final maxGroupSize = _currentEvent.settings.groupSize; final group = _currentEvent.groups![currentGroupIdx]; final bool canAdd = group.players.length < maxGroupSize; final bool hasRecord = _hasMatchRecord(player, group);
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text('${_isTeamMatch ? player.affiliation : player.name} 관리'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (hasRecord) const Padding(padding: EdgeInsets.all(12), child: Text('⚠️ 이 선수는 이미 경기를 치렀으므로 조 이동이 불가능합니다.', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13))),
      ListTile(leading: Icon(Icons.logout, color: hasRecord ? Colors.grey : Colors.orange), title: Text('대기 명단으로 보내기', style: TextStyle(color: hasRecord ? Colors.grey : Colors.black)), onTap: hasRecord ? null : () { setState(() { group.players.remove(player); _waitingPlayers.insert(0, player); TournamentLogic.syncGroupMatches(group, currentGroupIdx + 1); _refreshRankings(); }); widget.onDataChanged(); Navigator.pop(ctx); }),
      const Divider(),
      if (_waitingPlayers.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text('대기 선수와 교체하기', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
        ..._waitingPlayers.map((waitingP) => ListTile(dense: true, visualDensity: VisualDensity.compact, leading: Icon(Icons.swap_horiz, color: hasRecord ? Colors.grey : Colors.blue), title: Text(_isTeamMatch ? waitingP.affiliation : waitingP.name, style: TextStyle(color: hasRecord ? Colors.grey : Colors.black)), onTap: hasRecord ? null : () { setState(() { int idx = group.players.indexOf(player); if (idx != -1) { group.players[idx] = waitingP; _waitingPlayers.remove(waitingP); _waitingPlayers.insert(0, player); TournamentLogic.syncGroupMatches(group, currentGroupIdx + 1); _refreshRankings(); } }); widget.onDataChanged(); Navigator.pop(ctx); })),
        const Divider(),
        if (canAdd) ...[ const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text('대기 선수 충원하기', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))), ..._waitingPlayers.map((waitingP) => ListTile(dense: true, visualDensity: VisualDensity.compact, leading: const Icon(Icons.person_add, color: Colors.green), title: Text(_isTeamMatch ? waitingP.affiliation : waitingP.name), onTap: () { setState(() { group.players.add(waitingP); _waitingPlayers.remove(waitingP); TournamentLogic.syncGroupMatches(group, currentGroupIdx + 1); _refreshRankings(); }); widget.onDataChanged(); Navigator.pop(ctx); })), ],
      ]
    ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기'))]));
  }

  void _moveRank(int gIdx, int cur, int dir) { setState(() { final list = _manualRankings[gIdx]!; final item = list.removeAt(cur); list.insert(cur + dir, item); widget.onDataChanged(); }); }

  void _maybeShowScoreDialog(Match m, Group group) {
    final knockoutStarted = _currentEvent.knockoutRounds != null && _currentEvent.knockoutRounds!.isNotEmpty;
    final savedPassword = systemAdminPasswordNotifier.value;
    if (!knockoutStarted || savedPassword == null || savedPassword.isEmpty) { _showScoreDialog(m, group); return; }
    final controller = TextEditingController();
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('관리자 비밀번호'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('본선 토너먼트가 진행 중입니다. 예선 경기 결과를 변경하려면 관리자 비밀번호를 입력하세요.', style: TextStyle(fontSize: 13)), const SizedBox(height: 12), TextField(controller: controller, obscureText: true, decoration: const InputDecoration(hintText: '비밀번호', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)), onSubmitted: (_) => Navigator.pop(ctx, controller.text))]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')), TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('확인'))],
      ),
    ).then((result) {
      controller.dispose(); if (result == null || !mounted) return;
      if (result == savedPassword) { _showScoreDialog(m, group); }
      else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('비밀번호가 일치하지 않습니다.'))); }
    });
  }

  void _showScoreDialog(Match m, Group group) {
    int s1 = m.score1 == -1 ? 0 : m.score1; int s2 = m.score2 == -1 ? 0 : m.score2;
    showModalBottomSheet(
      context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setS) => Container(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [Expanded(child: _scoreDialogPlayerInfo(m.player1, textAlign: TextAlign.right)), const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('VS', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey))), Expanded(child: _scoreDialogPlayerInfo(m.player2, textAlign: TextAlign.left))]),
              const SizedBox(height: 40),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_scoreDialogCounter((v) => setS(() => s1 = v), s1), const Text(':', style: TextStyle(fontSize: 50, fontWeight: FontWeight.bold)), _scoreDialogCounter((v) => setS(() => s2 = v), s2)]),
              const SizedBox(height: 30),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [ElevatedButton.icon(onPressed: () => setS(() { s1 = -1; s2 = 0; }), icon: const Icon(Icons.flag), label: const Text('P1 기권'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50, foregroundColor: Colors.red)), ElevatedButton.icon(onPressed: () => setS(() { s1 = 0; s2 = -1; }), icon: const Icon(Icons.flag), label: const Text('P2 기권'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50, foregroundColor: Colors.red))]),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    m.score1 = s1; m.score2 = s2;
                    if (s1 == -1 || s2 == -1) {
                      m.status = MatchStatus.withdrawal; m.winner = s1 == -1 ? m.player2 : m.player1;
                      final withdrawingPlayer = s1 == -1 ? m.player1 : m.player2;
                      if (withdrawingPlayer != null) {
                        for (final other in group.matches) {
                          if (identical(other, m)) continue;
                          if (other.player1 == withdrawingPlayer) { other.score1 = -1; other.score2 = 0; other.status = MatchStatus.withdrawal; other.winner = other.player2; }
                          else if (other.player2 == withdrawingPlayer) { other.score1 = 0; other.score2 = -1; other.status = MatchStatus.withdrawal; other.winner = other.player1; }
                        }
                      }
                    } else { m.status = MatchStatus.completed; m.winner = s1 > s2 ? m.player1 : m.player2; }
                    _refreshRankings();
                  });
                  Navigator.pop(context); widget.onDataChanged();
                },
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 64), backgroundColor: const Color(0xFF1A535C), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('점수 저장 및 확정', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scoreDialogPlayerInfo(Player? p, {required TextAlign textAlign}) => Column(crossAxisAlignment: textAlign == TextAlign.right ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [Text(_isTeamMatch ? (p?.affiliation ?? 'TBD') : (p?.name ?? 'TBD'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis), Text(_isTeamMatch ? (p?.name ?? '') : (p?.affiliation ?? ''), style: const TextStyle(fontSize: 15, color: Colors.orange, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)]);
  Widget _scoreDialogCounter(void Function(int) onU, int v) => Column(children: [IconButton(onPressed: () => onU(v + 1), icon: const Icon(Icons.add_circle, color: Color(0xFF4ECDC4), size: 56)), Text(v == -1 ? '기권' : '$v', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Color(0xFF1A535C))), IconButton(onPressed: () => onU(v > 0 ? v - 1 : 0), icon: const Icon(Icons.remove_circle, color: Colors.redAccent, size: 56))]);
  void _fillRandomScores() { setState(() { final random = math.Random(); if (_currentEvent.groups == null) return; for (int i = 0; i < _currentEvent.groups!.length; i++) { for (var match in _currentEvent.groups![i].matches) { if (match.status == MatchStatus.pending) { bool p1Wins = random.nextBool(); match.score1 = p1Wins ? 3 : 1; match.score2 = p1Wins ? 1 : 3; match.winner = p1Wins ? match.player1 : match.player2; match.status = MatchStatus.completed; } } _manualRankings[i] = TournamentLogic.getGroupRankings(_currentEvent.groups![i]); } }); widget.onDataChanged(); }
  void _generateKnockout() { List<Player> qualified = []; if (_currentEvent.settings.skipGroupStage) { qualified = List.from(_currentEvent.players); } else { for (int i = 0; i < (_currentEvent.groups?.length ?? 0); i++) { qualified.addAll((_manualRankings[i] ?? TournamentLogic.getGroupRankings(_currentEvent.groups![i])).take(_currentEvent.settings.advancingCount)); } } var rounds = TournamentLogic.generateKnockout(qualified); setState(() { _currentEvent.knockoutRounds = rounds; _currentEvent.lastQualified = qualified; }); widget.onDataChanged(); Navigator.push(context, MaterialPageRoute(builder: (context) => KnockoutPage(tournamentTitle: '${widget.tournamentBaseTitle} - ${_currentEvent.name}', rounds: rounds, onDataChanged: widget.onDataChanged, events: widget.allEvents))); }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height; final int selectedIndex; final Widget child;
  _StickyHeaderDelegate({required this.height, required this.selectedIndex, required this.child});
  @override double get maxExtent => height;
  @override double get minExtent => height;
  @override Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;
  @override bool shouldRebuild(covariant _StickyHeaderDelegate old) => old.height != height || old.selectedIndex != selectedIndex;
}
