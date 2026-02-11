import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'models.dart';
import 'tournament_logic.dart';
import 'knockout_page.dart';
import 'match_sheet_page.dart';
import 'main.dart';

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
    final bool isSkipMode = _currentEvent.settings.skipGroupStage;

    // 예선 생략 모드면 항상 true, 아니면 모든 경기 완료 체크
    bool canProceed = isSkipMode || (groups.isNotEmpty && groups.every((g) => g.matches.every((m) => m.status == MatchStatus.completed || m.status == MatchStatus.withdrawal)));

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, _currentEventIdx),
        ),
        title: Text(_currentEvent.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, _currentEventIdx), child: const Text('메인화면', style: TextStyle(color: Colors.white, fontSize: 13))),
          TextButton(
            onPressed: () {
              if (_currentEvent.knockoutRounds != null && _currentEvent.knockoutRounds!.isNotEmpty) _navigateToKnockout();
              else ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('본선 대진을 먼저 생성해주세요.')));
            },
            child: const Text('본선', style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
          if (!isSkipMode)
            IconButton(icon: const Icon(Icons.casino_outlined, color: Colors.orange), onPressed: _fillRandomScores),
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
          if (_currentEvent.knockoutRounds != null)
            IconButton(
              icon: const Icon(Icons.account_tree_rounded, size: 28, color: Color(0xFF1A535C)),
              onPressed: () => _navigateToKnockout(),
            ),
        ],
      ),
      body: groups.isEmpty 
        ? const Center(child: Text('예선 조가 생성되지 않았습니다.'))
        : Column(
            children: [
              if (isSkipMode)
                Container(
                  width: double.infinity,
                  color: Colors.blue.shade50,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('예선 생략 모드: 점수 입력 없이 본선 생성 가능', style: TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
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
                          ...group.matches.map((m) => _buildMatchTile(m, group)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        child: ElevatedButton(
          onPressed: !canProceed ? null : _generateKnockout,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A535C), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 56)),
          child: Text(isSkipMode ? '즉시 본선 토너먼트 생성/이동' : '본선 토너먼트 생성/이동'),
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
    final bool isSkipMode = _currentEvent.settings.skipGroupStage;

    if (isSkipMode) {
      // 예선 생략 모드: 모든 참가 선수가 본선 진출
      qualified = List.from(_currentEvent.players);
    } else {
      for (int i = 0; i < (_currentEvent.groups?.length ?? 0); i++) {
        final groupRankings = _manualRankings[i] ?? TournamentLogic.getGroupRankings(_currentEvent.groups![i]);
        qualified.addAll(groupRankings.take(_currentEvent.settings.advancingCount));
      }
    }

    var targetRounds = TournamentLogic.generateKnockout(qualified);
    setState(() {
      _currentEvent.knockoutRounds = targetRounds;
      _currentEvent.lastQualified = qualified;
    });
    widget.onDataChanged();
    _navigateToKnockout();
  }

  Widget _buildRankingTable(List<Player> rankings, Group group, int groupIdx) {
    final stats = TournamentLogic.getRankingStats(group);
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Table(
        border: TableBorder.all(color: Colors.grey.shade300),
        columnWidths: const { 
          0: FlexColumnWidth(0.5), 
          1: FlexColumnWidth(2.2), 
          2: FlexColumnWidth(0.5), 
          3: FlexColumnWidth(0.5), 
          4: FlexColumnWidth(0.5), 
          5: FlexColumnWidth(0.6), 
          6: FlexColumnWidth(0.4)
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(decoration: const BoxDecoration(color: Color(0x6622BABB)), children: [ 
            for (var h in ['순위', '이름(소속)', '승', '득', '실', '득실', '조정']) _tableCell(h, isBold: true) 
          ]),
          ...rankings.asMap().entries.map((e) {
            final index = e.key; final player = e.value; final s = stats[player]!;
            final bool isQualified = index < _currentEvent.settings.advancingCount;
            return TableRow(children: [
              _tableCell('${index + 1}', color: isQualified ? Colors.blue : Colors.black),
              TableCell(child: Padding(padding: const EdgeInsets.all(4.0), child: Text(_isTeamMatch ? player.affiliation : "${player.name}(${player.affiliation})", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))),
              _tableCell('${s['wins']}'), _tableCell('${s['won']}'), _tableCell('${s['lost']}'), _tableCell('${s['diff']}'),
              TableCell(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center, 
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: index == 0 ? null : () => _moveRank(groupIdx, index, -1), 
                      child: Icon(Icons.arrow_upward, size: 16, color: index == 0 ? Colors.grey.shade300 : Colors.blue)
                    ),
                    const SizedBox(width: 2),
                    GestureDetector(
                      onTap: index == rankings.length - 1 ? null : () => _moveRank(groupIdx, index, 1), 
                      child: Icon(Icons.arrow_downward, size: 16, color: index == rankings.length - 1 ? Colors.grey.shade300 : Colors.red)
                    ),
                  ]
                )
              ),
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

  String _formatTeamMembers(String names) {
    if (names.isEmpty) return "";
    List<String> list = names.split(',').map((s) => s.trim()).toList();
    List<String> lines = [];
    for (int i = 0; i < list.length; i += 2) {
      if (i + 1 < list.length) lines.add("${list[i]}, ${list[i+1]}");
      else lines.add(list[i]);
    }
    return lines.take(3).join('\n');
  }

  Widget _buildMatchTile(Match m, Group group) {
    if (!_isTeamMatch) {
      return ListTile(
        dense: true,
        title: Row(children: [
          Expanded(child: Text(m.player1?.name ?? 'BYE', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
          Container(margin: const EdgeInsets.symmetric(horizontal: 10), child: Text('${m.score1} : ${m.score2}', style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(m.player2?.name ?? 'BYE', textAlign: TextAlign.left, style: const TextStyle(fontSize: 12))),
        ]),
        subtitle: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Text(m.player1?.affiliation ?? '', textAlign: TextAlign.right, style: const TextStyle(fontSize: 10, color: Colors.grey))),
          const SizedBox(width: 40),
          Expanded(child: Text(m.player2?.affiliation ?? '', textAlign: TextAlign.left, style: const TextStyle(fontSize: 10, color: Colors.grey))),
        ]),
        onTap: () => _maybeShowScoreDialog(m, group),
      );
    }

    return InkWell(
      onTap: () => _maybeShowScoreDialog(m, group),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text(m.player1?.affiliation ?? 'BYE', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1A535C)))),
                const SizedBox(width: 60),
                Expanded(child: Text(m.player2?.affiliation ?? 'BYE', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1A535C)))),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: Text(_formatTeamMembers(m.player1?.name ?? ''), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.black87, height: 1.3))),
                Container(
                  width: 60,
                  alignment: Alignment.center,
                  child: Text(m.status == MatchStatus.withdrawal ? '기권' : '${m.score1} : ${m.score2}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.redAccent)),
                ),
                Expanded(child: Text(_formatTeamMembers(m.player2?.name ?? ''), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.black87, height: 1.3))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 본선 진행 중이면 관리자 비밀번호 확인 후 점수 입력창 표시
  void _maybeShowScoreDialog(Match m, Group group) {
    final knockoutStarted = _currentEvent.knockoutRounds != null && _currentEvent.knockoutRounds!.isNotEmpty;
    final savedPassword = systemAdminPasswordNotifier.value;
    if (!knockoutStarted || savedPassword == null || savedPassword.isEmpty) {
      _showScoreDialog(m, group);
      return;
    }
    final controller = TextEditingController();
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('관리자 비밀번호'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('본선 토너먼트가 진행 중입니다. 예선 경기 결과를 변경하려면 관리자 비밀번호를 입력하세요.', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: '비밀번호',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onSubmitted: (_) => Navigator.pop(ctx, controller.text),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('확인'),
          ),
        ],
      ),
    ).then((result) {
      controller.dispose();
      if (result == null || !mounted) return;
      if (result == savedPassword) {
        _showScoreDialog(m, group);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('비밀번호가 일치하지 않습니다.')),
        );
      }
    });
  }

  /// 본선 토너먼트 점수입력창과 동일한 디자인. 기권 저장 시 같은 조 내 해당 선수의 나머지 경기도 모두 기권 처리
  void _showScoreDialog(Match m, Group group) {
    int s1 = m.score1 == -1 ? 0 : m.score1;
    int s2 = m.score2 == -1 ? 0 : m.score2;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setS) => Container(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Expanded(child: _scoreDialogPlayerInfo(m.player1, textAlign: TextAlign.right)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('VS', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey))),
                Expanded(child: _scoreDialogPlayerInfo(m.player2, textAlign: TextAlign.left)),
              ]),
              const SizedBox(height: 40),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _scoreDialogCounter((v) => setS(() => s1 = v), s1),
                const Text(':', style: TextStyle(fontSize: 50, fontWeight: FontWeight.bold)),
                _scoreDialogCounter((v) => setS(() => s2 = v), s2),
              ]),
              const SizedBox(height: 30),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                ElevatedButton.icon(onPressed: () => setS(() { s1 = -1; s2 = 0; }), icon: const Icon(Icons.flag), label: const Text('P1 기권'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50, foregroundColor: Colors.red)),
                ElevatedButton.icon(onPressed: () => setS(() { s1 = 0; s2 = -1; }), icon: const Icon(Icons.flag), label: const Text('P2 기권'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50, foregroundColor: Colors.red)),
              ]),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    m.score1 = s1;
                    m.score2 = s2;
                    if (s1 == -1 || s2 == -1) {
                      m.status = MatchStatus.withdrawal;
                      m.winner = s1 == -1 ? m.player2 : m.player1;
                      // 같은 조 내 기권한 선수의 나머지 경기도 기권 처리
                      final withdrawingPlayer = s1 == -1 ? m.player1 : m.player2;
                      if (withdrawingPlayer != null) {
                        for (final other in group.matches) {
                          if (identical(other, m)) continue;
                          if (other.player1 == withdrawingPlayer) {
                            other.score1 = -1;
                            other.score2 = 0;
                            other.status = MatchStatus.withdrawal;
                            other.winner = other.player2;
                          } else if (other.player2 == withdrawingPlayer) {
                            other.score1 = 0;
                            other.score2 = -1;
                            other.status = MatchStatus.withdrawal;
                            other.winner = other.player1;
                          }
                        }
                      }
                    } else {
                      m.status = MatchStatus.completed;
                      m.winner = s1 > s2 ? m.player1 : m.player2;
                    }
                    _refreshRankings();
                  });
                  Navigator.pop(context);
                  widget.onDataChanged();
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

  Widget _scoreDialogPlayerInfo(Player? p, {required TextAlign textAlign}) => Column(
    crossAxisAlignment: textAlign == TextAlign.right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      Text(_isTeamMatch ? (p?.affiliation ?? 'TBD') : (p?.name ?? 'TBD'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
      Text(_isTeamMatch ? (p?.name ?? '') : (p?.affiliation ?? ''), style: const TextStyle(fontSize: 15, color: Colors.orange, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
    ],
  );

  Widget _scoreDialogCounter(void Function(int) onU, int v) => Column(
    children: [
      IconButton(onPressed: () => onU(v + 1), icon: const Icon(Icons.add_circle, color: Color(0xFF4ECDC4), size: 56)),
      Text(v == -1 ? '기권' : '$v', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Color(0xFF1A535C))),
      IconButton(onPressed: () => onU(v > 0 ? v - 1 : 0), icon: const Icon(Icons.remove_circle, color: Colors.redAccent, size: 56)),
    ],
  );
}
