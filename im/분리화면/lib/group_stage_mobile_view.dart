import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'models.dart';
import 'tournament_logic.dart';
import 'knockout_page.dart';
import 'match_sheet_page.dart';

class GroupStageMobileView extends StatefulWidget {
  final String tournamentBaseTitle;
  final List<TournamentEvent> allEvents;
  final int initialEventIdx;
  final VoidCallback onDataChanged;

  const GroupStageMobileView({
    super.key,
    required this.tournamentBaseTitle,
    required this.allEvents,
    required this.initialEventIdx,
    required this.onDataChanged,
  });

  @override
  State<GroupStageMobileView> createState() => _GroupStageMobileViewState();
}

class _GroupStageMobileViewState extends State<GroupStageMobileView> {
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

    return Scaffold(
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
                        decoration: const ShapeDecoration(color: Color(0xFF1A535C), shape: StadiumBorder()),
                        child: Text('${group.name}(${group.players.length}명)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
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
    );
  }

  void _navigateToKnockout() async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => KnockoutPage(tournamentTitle: _fullTitle, rounds: _currentEvent.knockoutRounds!, onDataChanged: widget.onDataChanged, events: widget.allEvents)));
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
    setState(() { _currentEvent.knockoutRounds = targetRounds; _currentEvent.lastQualified = qualified; });
    widget.onDataChanged();
    _navigateToKnockout();
  }

  Widget _buildRankingTable(List<Player> rankings, Group group, int groupIdx) {
    final stats = TournamentLogic.getRankingStats(group);
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Table(
        border: TableBorder.all(color: Colors.grey.shade300),
        columnWidths: const { 0: FlexColumnWidth(0.5), 1: FlexColumnWidth(2.2), 2: FlexColumnWidth(0.5), 3: FlexColumnWidth(0.5), 4: FlexColumnWidth(0.5), 5: FlexColumnWidth(0.6), 6: FlexColumnWidth(0.6) },
        children: [
          TableRow(decoration: const BoxDecoration(color: Color(0x6622BABB)), children: [ for (var h in ['순위', '이름(소속)', '승', '득', '실', '득실', '조정']) _tableCell(h, isBold: true) ]),
          ...rankings.asMap().entries.map((e) {
            final index = e.key; final player = e.value; final s = stats[player]!;
            final bool isQualified = index < _currentEvent.settings.advancingCount;
            return TableRow(children: [
              _tableCell('${index + 1}', color: isQualified ? Colors.blue : Colors.black),
              TableCell(child: Padding(padding: const EdgeInsets.all(4.0), child: Text(_isTeamMatch ? player.affiliation : "${player.name}(${player.affiliation})", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))),
              _tableCell('${s['wins']}'), _tableCell('${s['won']}'), _tableCell('${s['lost']}'), _tableCell('${s['diff']}'),
              TableCell(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                GestureDetector(onTap: index == 0 ? null : () => _moveRank(groupIdx, index, -1), child: Icon(Icons.arrow_upward, size: 16, color: index == 0 ? Colors.grey : Colors.blue)),
                GestureDetector(onTap: index == rankings.length - 1 ? null : () => _moveRank(groupIdx, index, 1), child: Icon(Icons.arrow_downward, size: 16, color: index == rankings.length - 1 ? Colors.grey : Colors.red)),
              ])),
            ]);
          }),
        ],
      ),
    );
  }

  Widget _tableCell(String t, {bool isBold = false, Color color = Colors.black}) => TableCell(child: Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text(t, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color, fontSize: 11)))));

  void _moveRank(int gIdx, int cur, int dir) {
    setState(() {
      final list = _manualRankings[gIdx]!;
      final item = list.removeAt(cur);
      list.insert(cur + dir, item);
      widget.onDataChanged();
    });
  }

  Widget _buildMatchTile(Match m, int groupIdx) => ListTile(
    dense: true, title: Row(children: [
      Expanded(child: Text(_isTeamMatch ? (m.player1?.affiliation ?? 'BYE') : (m.player1?.name ?? 'BYE'), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
      Container(margin: const EdgeInsets.symmetric(horizontal: 10), child: Text('${m.score1} : ${m.score2}', style: const TextStyle(fontWeight: FontWeight.bold))),
      Expanded(child: Text(_isTeamMatch ? (m.player2?.affiliation ?? 'BYE') : (m.player2?.name ?? 'BYE'), textAlign: TextAlign.left, style: const TextStyle(fontSize: 12))),
    ]),
    onTap: () => _showScoreDialog(m),
  );

  void _showScoreDialog(Match m) {
    int s1 = m.score1; int s2 = m.score2;
    showModalBottomSheet(context: context, builder: (context) => StatefulBuilder(builder: (context, setS) => Container(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _counter((v) => setS(() => s1 = v), s1),
          const Text(':', style: TextStyle(fontSize: 30)),
          _counter((v) => setS(() => s2 = v), s2),
        ]),
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
