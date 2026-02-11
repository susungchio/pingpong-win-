import 'dart:math' as math;
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'models.dart';
import 'tournament_logic.dart';
import 'knockout_page.dart';
import 'match_sheet_page.dart';

class GroupStagePage extends StatefulWidget {
  final String tournamentBaseTitle; 
  final List<TournamentEvent> allEvents; 
  final int initialEventIdx; 
  final VoidCallback onDataChanged; 

  const GroupStagePage({
    super.key,
    required this.tournamentBaseTitle,
    required this.allEvents,
    required this.initialEventIdx,
    required this.onDataChanged,
  });

  @override
  State<GroupStagePage> createState() => _GroupStagePageState();
}

class _GroupStagePageState extends State<GroupStagePage> {
  late int _currentEventIdx;
  final Map<int, List<Player>> _manualRankings = {};
  
  TournamentEvent get _currentEvent => widget.allEvents[_currentEventIdx];
  String get _fullTitle => '${widget.tournamentBaseTitle} - ${_currentEvent.name}';
  
  bool get _isTeamMatch => _currentEvent.teamSize > 1;

  @override
  void initState() {
    super.initState();
    _currentEventIdx = widget.initialEventIdx;
    _refreshRankings();
  }

  void _refreshRankings() {
    _manualRankings.clear();
    if (_currentEvent.groups != null) {
      for (int i = 0; i < _currentEvent.groups!.length; i++) {
        _manualRankings[i] = TournamentLogic.getGroupRankings(_currentEvent.groups![i]);
      }
    }
  }

  void _switchEvent(int newIdx) {
    setState(() {
      _currentEventIdx = newIdx;
      _refreshRankings();
    });
  }

  void _fillRandomScores() {
    setState(() {
      final random = math.Random();
      if (_currentEvent.groups == null) return;
      for (int i = 0; i < _currentEvent.groups!.length; i++) {
        final group = _currentEvent.groups![i];
        for (var match in group.matches) {
          if (match.status == MatchStatus.pending) {
            bool p1Wins = random.nextBool();
            match.score1 = p1Wins ? 3 : random.nextInt(3);
            match.score2 = p1Wins ? random.nextInt(3) : 3;
            match.winner = p1Wins ? match.player1 : match.player2;
            match.status = MatchStatus.completed;
          }
        }
        _manualRankings[i] = TournamentLogic.getGroupRankings(group);
      }
    });
    widget.onDataChanged();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _currentEvent.groups ?? [];
    bool allCompleted = groups.isNotEmpty && groups.every((g) => g.matches.every((m) => m.status == MatchStatus.completed || m.status == MatchStatus.withdrawal));

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _currentEventIdx);
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4F8),
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _currentEventIdx),
          ),
          title: Text(_currentEvent.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
          actions: [
            IconButton(
              icon: const Icon(Icons.assignment_outlined, color: Colors.purple),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => MatchSheetPage(
                  tournamentTitle: _fullTitle, 
                  groups: _currentEvent.groups!, 
                  knockoutRounds: _currentEvent.knockoutRounds
                )));
              },
              tooltip: '기록지 보기',
            ),
            IconButton(icon: const Icon(Icons.casino_outlined, color: Colors.orange), onPressed: _fillRandomScores),
            if (_currentEvent.knockoutRounds != null)
              IconButton(
                icon: const Icon(Icons.account_tree_rounded, size: 28, color: Color(0xFF1A535C)),
                onPressed: () => _navigateToKnockout(),
              ),
          ],
        ),
        body: groups.isEmpty 
          ? const Center(child: Text('예선 조가 생성되지 않았습니다.'))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                final rankings = _manualRankings[index] ?? TournamentLogic.getGroupRankings(group);
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), 
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                          decoration: const ShapeDecoration(
                            color: Color(0xFF1A535C),
                            shape: StadiumBorder(),
                          ),
                          child: Text(
                            '${group.name}(${group.players.length}명)',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                      ),
                      _buildRankingTable(rankings, group, index),
                      const Divider(height: 1), 
                      ...group.matches.map((m) => _buildMatchTile(m, index)),
                    ],
                  ),
                );
              },
            ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.all(20),
          child: ElevatedButton(
            onPressed: !allCompleted ? null : _generateKnockout,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A535C), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 56)),
            child: const Text('본선 토너먼트 생성/이동'),
          ),
        ),
      ),
    );
  }

  void _navigateToKnockout() async {
    final result = await Navigator.push(
      context, 
      MaterialPageRoute(builder: (context) => KnockoutPage(
        tournamentTitle: _fullTitle, 
        rounds: _currentEvent.knockoutRounds!, 
        onDataChanged: widget.onDataChanged, 
        events: widget.allEvents,
      ))
    );
    if (result is int) {
      _switchEvent(result);
      Future.delayed(Duration.zero, () => _navigateToKnockout());
    }
  }

  void _generateKnockout() async {
    List<Player> qualified = [];
    for (int i = 0; i < (_currentEvent.groups?.length ?? 0); i++) {
      final groupRankings = _manualRankings[i] ?? TournamentLogic.getGroupRankings(_currentEvent.groups![i]);
      qualified.addAll(groupRankings.take(_currentEvent.settings.advancingCount));
    }
    var targetRounds = TournamentLogic.generateKnockout(qualified);
    setState(() {
      _currentEvent.knockoutRounds = targetRounds;
      _currentEvent.lastQualified = qualified;
    });
    widget.onDataChanged();
    _navigateToKnockout();
  }

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

  Widget _buildMatchTile(Match m, int groupIdx) {
    return ListTile(
      dense: true, 
      visualDensity: VisualDensity.compact,
      title: Row(children: [
        Expanded(child: _playerSmallInfo(m.player1, TextAlign.right)),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
          child: Text(m.status == MatchStatus.withdrawal ? '기권' : '${m.score1} : ${m.score2}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        Expanded(child: _playerSmallInfo(m.player2, TextAlign.left)),
      ]),
      onTap: () => _showScoreDialog(m, groupIdx),
    );
  }

  Widget _playerSmallInfo(Player? p, TextAlign align) {
    if (p == null) return Text('BYE', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), textAlign: align);
    return Column(
      crossAxisAlignment: align == TextAlign.right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(_isTeamMatch ? p.affiliation : p.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1A535C)), overflow: TextOverflow.ellipsis),
        Text(_isTeamMatch ? _formatNames(p.name) : p.affiliation, style: TextStyle(fontSize: _isTeamMatch ? 11 : 10, color: _isTeamMatch ? Colors.black87 : Colors.grey[700], fontWeight: _isTeamMatch ? FontWeight.w500 : FontWeight.normal, height: 1.2), maxLines: _isTeamMatch ? 3 : 1, overflow: TextOverflow.ellipsis, textAlign: align),
      ],
    );
  }

  Widget _buildRankingTable(List<Player> rankings, Group group, int groupIdx) {
    final stats = TournamentLogic.getRankingStats(group);
    const double cellHeightPadding = 10.0;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Table(
        border: TableBorder.all(color: Colors.grey.shade300),
        columnWidths: const {
          0: FlexColumnWidth(0.5), 1: FlexColumnWidth(2.2), 2: FlexColumnWidth(0.5), 3: FlexColumnWidth(0.5), 4: FlexColumnWidth(0.5), 5: FlexColumnWidth(0.6), 6: FlexColumnWidth(0.6),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0x6622BABB)),
            children: [
              for (var h in ['순위', '이름(소속)', '승', '득', '실', '득실', '조정'])
                _tableCell(h, isBold: true, verticalPadding: cellHeightPadding, fontSize: 13),
            ],
          ),
          ...rankings.asMap().entries.map((e) {
            final index = e.key; final player = e.value; final s = stats[player]!;
            final bool isQualified = index < _currentEvent.settings.advancingCount;
            String displayName = _isTeamMatch ? player.affiliation : "${player.name}(${player.affiliation})";
            return TableRow(
              children: [
                _tableCell('${index + 1}', color: isQualified ? Colors.blue : Colors.black, verticalPadding: cellHeightPadding, fontSize: 13),
                TableCell(child: InkWell(onTap: () => _showMoveGroupDialog(player, groupIdx), child: Padding(padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: cellHeightPadding), child: Text(displayName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black))))),
                _tableCell('${s['wins']}', verticalPadding: cellHeightPadding, fontSize: 13),
                _tableCell('${s['won']}', verticalPadding: cellHeightPadding, fontSize: 13),
                _tableCell('${s['lost']}', verticalPadding: cellHeightPadding, fontSize: 13),
                _tableCell('${s['diff']}', verticalPadding: cellHeightPadding, fontSize: 13),
                TableCell(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  GestureDetector(onTap: index == 0 ? null : () => _moveRank(groupIdx, index, -1), child: Icon(Icons.arrow_upward, size: 18, color: index == 0 ? Colors.grey.shade300 : Colors.blue)),
                  GestureDetector(onTap: index == rankings.length - 1 ? null : () => _moveRank(groupIdx, index, 1), child: Icon(Icons.arrow_downward, size: 18, color: index == rankings.length - 1 ? Colors.grey.shade300 : Colors.red)),
                ])),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _tableCell(String t, {bool isBold = false, Color color = Colors.black, double verticalPadding = 4.0, double fontSize = 11}) => TableCell(child: Center(child: Padding(padding: EdgeInsets.symmetric(vertical: verticalPadding), child: Text(t, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color, fontSize: fontSize)))));

  void _moveRank(int gIdx, int cur, int dir) {
    setState(() {
      final list = _manualRankings[gIdx]!;
      final item = list.removeAt(cur);
      list.insert(cur + dir, item);
      widget.onDataChanged();
    });
  }

  void _showMoveGroupDialog(Player player, int fromGroupIdx) {
    final availableGroups = _currentEvent.groups!.asMap().entries.where((e) => e.key != fromGroupIdx).toList();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        title: Column(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), decoration: const ShapeDecoration(color: Color(0xFF1A535C), shape: StadiumBorder()), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.swap_horiz, color: Colors.white, size: 20), const SizedBox(width: 8), Text('${player.name} 선수 조 이동', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))])),
          const SizedBox(height: 12), const Text('이동할 조를 선택하세요.', style: TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.w500)), const Divider(),
        ]),
        content: SizedBox(width: double.maxFinite, child: GridView.builder(shrinkWrap: true, itemCount: availableGroups.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 4.0, mainAxisSpacing: 6, crossAxisSpacing: 6), itemBuilder: (context, idx) {
          final entry = availableGroups[idx]; final bool isUnderLimit = entry.value.players.length < _currentEvent.settings.groupSize; final Color bgColor = (idx ~/ 2 + idx % 2) % 2 == 0 ? const Color(0xFFD1E9FF) : const Color(0xFFFFD1D1);
          return InkWell(onTap: () { _movePlayerToGroup(player, fromGroupIdx, entry.key); Navigator.pop(context); }, child: Container(decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(4)), padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(children: [Expanded(child: Text(entry.value.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)), Text('${entry.value.players.length}명', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isUnderLimit ? Colors.red : Colors.black87)), const Icon(Icons.chevron_right, size: 12)])));
        })),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))],
      ),
    );
  }

  void _movePlayerToGroup(Player player, int fromIdx, int toIdx) {
    setState(() {
      _currentEvent.groups![fromIdx].players.remove(player); _currentEvent.groups![toIdx].players.add(player);
      _currentEvent.groups![fromIdx].matches.clear(); _currentEvent.groups![fromIdx].matches.addAll(TournamentLogic.generateRoundRobin(_currentEvent.groups![fromIdx].players, fromIdx + 1));
      _currentEvent.groups![toIdx].matches.clear(); _currentEvent.groups![toIdx].matches.addAll(TournamentLogic.generateRoundRobin(_currentEvent.groups![toIdx].players, toIdx + 1));
      _refreshRankings(); widget.onDataChanged();
    });
  }

  void _showScoreDialog(Match m, int gIdx) {
    int s1 = m.score1; int s2 = m.score2;
    showModalBottomSheet(context: context, builder: (context) => StatefulBuilder(builder: (context, setS) => Container(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [Expanded(child: _playerSmallInfo(m.player1, TextAlign.right)), const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('VS', style: TextStyle(fontWeight: FontWeight.bold))), Expanded(child: _playerSmallInfo(m.player2, TextAlign.left))]),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_counter((v) => setS(() => s1 = v), s1), const Text(':', style: TextStyle(fontSize: 30)), _counter((v) => setS(() => s2 = v), s2)]),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: () {
          setState(() { m.score1 = s1; m.score2 = s2; m.status = MatchStatus.completed; m.winner = s1 > s2 ? m.player1 : m.player2; _refreshRankings(); });
          Navigator.pop(context); widget.onDataChanged();
        }, child: const Text('점수 저장')),
      ]),
    )));
  }

  Widget _counter(Function(int) onU, int v) => Column(children: [IconButton(onPressed: () => onU(v + 1), icon: const Icon(Icons.add_circle_outline)), Text('$v', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), IconButton(onPressed: () => onU(v > 0 ? v - 1 : 0), icon: const Icon(Icons.remove_circle_outline))]);
}
