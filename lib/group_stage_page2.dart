import 'dart:math' as math;
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'models.dart';
import 'tournament_logic.dart';
import 'knockout_page.dart';

class GroupStagePage extends StatefulWidget {
  final String tournamentTitle;
  final List<Group> groups;
  final TournamentSettings settings;
  final List<Round>? existingRounds;
  final List<Player>? lastQualified;
  final Function(List<Round>, List<Player>) onKnockoutUpdate;

  const GroupStagePage({super.key, required this.tournamentTitle, required this.groups, required this.settings, this.existingRounds, this.lastQualified, required this.onKnockoutUpdate});
  @override
  State<GroupStagePage> createState() => _GroupStagePageState();
}

class _GroupStagePageState extends State<GroupStagePage> {
  final Map<int, List<Player>> _manualRankings = {};
  List<Round>? _currentKnockoutRounds;

  @override
  void initState() {
    super.initState();
    _currentKnockoutRounds = widget.existingRounds;
    // 초기 순위 데이터 생성
    for (int i = 0; i < widget.groups.length; i++) {
      _manualRankings[i] = TournamentLogic.getGroupRankings(widget.groups[i]);
    }
  }

  void _fillRandomScores() {
    setState(() {
      final random = math.Random();
      // 설정된 승리 세트 수 (기본값 3, 없으면 3으로 간주)
      final winScore = 3;

      for (int i = 0; i < widget.groups.length; i++) {
        final group = widget.groups[i];
        for (var match in group.matches) {
          if (match.status == MatchStatus.pending) {
            bool player1Wins = random.nextBool();
            if (player1Wins) {
              match.score1 = winScore;
              match.score2 = random.nextInt(winScore); // 0, 1, 2
              match.winner = match.player1;
            } else {
              match.score1 = random.nextInt(winScore); // 0, 1, 2
              match.score2 = winScore;
              match.winner = match.player2;
            }
            match.status = MatchStatus.completed;
          }
        }
        _manualRankings[i] = TournamentLogic.getGroupRankings(group);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    bool allCompleted = widget.groups.every((g) => g.matches.isNotEmpty && g.matches.every((m) => m.status == MatchStatus.completed || m.status == MatchStatus.withdrawal));

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: Text(widget.tournamentTitle),
        actions: [
          IconButton(icon: const Icon(Icons.casino_outlined, color: Colors.orange), onPressed: _fillRandomScores),
          if (_currentKnockoutRounds != null)
            IconButton(
              icon: const Icon(Icons.arrow_forward_rounded, size: 32, color: Color(0xFF1A535C)),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => KnockoutPage(tournamentTitle: widget.tournamentTitle, rounds: _currentKnockoutRounds!, onDataChanged: () {}, events: []))),
            ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 120),
        itemCount: widget.groups.length,
        itemBuilder: (context, index) {
          final group = widget.groups[index];
          final rankings = _manualRankings[index] ?? TournamentLogic.getGroupRankings(group);

          return Card(
            margin: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ListTile(tileColor: const Color(0xFF1A535C).withOpacity(0.05), title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.bold))),
              _buildRankingTable(rankings, group, index),
              const Divider(),
              ...group.matches.map((m) => ListTile(
                title: Row(children: [
                  Expanded(child: _playerMatchInfo(m.player1, textAlign: TextAlign.right)),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                    child: Text(m.status == MatchStatus.withdrawal ? '기권' : '${m.score1 == -1 ? "-" : m.score1} : ${m.score2 == -1 ? "-" : m.score2}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Expanded(child: _playerMatchInfo(m.player2, textAlign: TextAlign.left)),
                ]),
                trailing: Icon((m.status == MatchStatus.completed || m.status == MatchStatus.withdrawal) ? Icons.check_circle : Icons.edit, color: (m.status == MatchStatus.completed || m.status == MatchStatus.withdrawal) ? Colors.green : Colors.grey),
                onTap: () => _showScoreDialog(m, index),
              )),
            ]),
          );
        },
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        child: ElevatedButton(
          onPressed: !allCompleted ? null : () async {
            // 버튼 클릭 시점에 전체 조에서 진출자를 정확히 수집
            List<Player> qualified = [];
            for (int i = 0; i < widget.groups.length; i++) {
              final groupRankings = _manualRankings[i] ?? TournamentLogic.getGroupRankings(widget.groups[i]);
              qualified.addAll(groupRankings.take(widget.settings.advancingCount));
            }

            bool shouldGenerate = true;
            if (_currentKnockoutRounds != null) {
              shouldGenerate = await _showRebuildDialog() ?? false;
            }

            if (shouldGenerate) {
              var targetRounds = TournamentLogic.generateKnockout(qualified);
              setState(() => _currentKnockoutRounds = targetRounds);
              widget.onKnockoutUpdate(targetRounds, qualified);
              Navigator.push(context, MaterialPageRoute(builder: (context) => KnockoutPage(tournamentTitle: widget.tournamentTitle, rounds: targetRounds, onDataChanged: () {}, events: [])));
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A535C), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 56)),
          child: const Text('본선 토너먼트 생성'),
        ),
      ),
    );
  }

  Future<bool?> _showRebuildDialog() {
    final controller = TextEditingController();
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('본선 대진 재생성'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('기존 본선 기록이 초기화됩니다. 계속하시겠습니까?'),
          TextField(controller: controller, obscureText: true, decoration: const InputDecoration(hintText: '비밀번호 1234')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('아니오')),
          TextButton(onPressed: () { if (controller.text == '1234') Navigator.pop(context, true); }, child: const Text('예', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Widget _playerMatchInfo(Player? p, {required TextAlign textAlign}) {
    if (p == null) return const Text('BYE');
    return Column(
      crossAxisAlignment: textAlign == TextAlign.right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(p.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
        Text(p.affiliation, style: const TextStyle(fontSize: 12, color: Colors.grey), overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _buildRankingTable(List<Player> rankings, Group group, int groupIdx) {
    final stats = TournamentLogic.getRankingStats(group);
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Table(
        border: TableBorder.all(color: Colors.grey.shade300),
        columnWidths: const {
          0: FlexColumnWidth(0.6), 
          1: FlexColumnWidth(2.5),
          2: FlexColumnWidth(0.6), 
          3: FlexColumnWidth(0.6), 
          4: FlexColumnWidth(0.6), 
          5: FlexColumnWidth(0.7), 
          6: FlexColumnWidth(1.8)
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(decoration: BoxDecoration(color: Colors.grey.shade100), children: const [
            TableCell(child: Center(child: Text('순위', style: TextStyle(fontSize: 10)))),
            TableCell(child: Center(child: Text('이름(소속)', style: TextStyle(fontSize: 10)))),
            TableCell(child: Center(child: Text('승', style: TextStyle(fontSize: 10)))),
            TableCell(child: Center(child: Text('득', style: TextStyle(fontSize: 10)))),
            TableCell(child: Center(child: Text('실', style: TextStyle(fontSize: 10)))),
            TableCell(child: Center(child: Text('득실', style: TextStyle(fontSize: 10)))),
            TableCell(child: Center(child: Text('조정', style: TextStyle(fontSize: 10)))),
          ]),
          ...rankings.asMap().entries.map((e) {
            final p = e.value;
            final s = stats[p]!;
            return TableRow(children: [
              TableCell(child: Center(child: Text('${e.key + 1}', style: TextStyle(color: e.key < widget.settings.advancingCount ? Colors.blue : Colors.black)))),
              TableCell(child: Padding(padding: const EdgeInsets.all(4.0), child: Text('${p.name}(${p.affiliation})', style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis))),
              TableCell(child: Center(child: Text('${s['wins']}'))),
              TableCell(child: Center(child: Text('${s['won']}'))),
              TableCell(child: Center(child: Text('${s['lost']}'))),
              TableCell(child: Center(child: Text('${s['diff']}'))),
              TableCell(child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.arrow_upward, size: 16),
                    onPressed: e.key == 0 ? null : () => _moveRanking(groupIdx, e.key, -1)
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.arrow_downward, size: 16),
                    onPressed: e.key == rankings.length - 1 ? null : () => _moveRanking(groupIdx, e.key, 1)
                  ),
                ],
              )),
            ]);
          }),
        ],
      ),
    );
  }

  void _moveRanking(int groupIdx, int currentIdx, int direction) {
    setState(() {
      final list = _manualRankings[groupIdx]!;
      final item = list.removeAt(currentIdx);
      list.insert(currentIdx + direction, item);
    });
  }

  void _showScoreDialog(Match m, int groupIdx) {
    int s1 = m.score1 == -1 ? 0 : m.score1;
    int s2 = m.score2 == -1 ? 0 : m.score2;
    showModalBottomSheet(context: context, builder: (context) => StatefulBuilder(builder: (context, setS) => Container(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Expanded(child: _playerMatchInfo(m.player1, textAlign: TextAlign.right)),
          const Text(' VS ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: _playerMatchInfo(m.player2, textAlign: TextAlign.left)),
        ]),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _counter((v) => setS(() => s1 = v), s1),
          const Text(':', style: TextStyle(fontSize: 30)),
          _counter((v) => setS(() => s2 = v), s2),
        ]),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: () {
          setState(() {
            m.score1 = s1; m.score2 = s2;
            m.status = MatchStatus.completed;
            m.winner = s1 > s2 ? m.player1 : (s1 < s2 ? m.player2 : null);
            _manualRankings[groupIdx] = TournamentLogic.getGroupRankings(widget.groups[groupIdx]);
          });
          Navigator.pop(context);
        }, style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: const Color(0xFF1A535C), foregroundColor: Colors.white), child: const Text('저장'))
      ]),
    )));
  }

  Widget _counter(Function(int) onU, int v) => Column(children: [
    IconButton(onPressed: () => onU(v + 1), icon: const Icon(Icons.add_circle, color: Color(0xFF4ECDC4))),
    Text('$v', style: const TextStyle(fontSize: 35, fontWeight: FontWeight.bold)),
    IconButton(onPressed: () => onU(v > 0 ? v - 1 : 0), icon: const Icon(Icons.remove_circle, color: Colors.redAccent)),
  ]);
}
