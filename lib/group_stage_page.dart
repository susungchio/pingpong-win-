import 'dart:math' as math;
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'models.dart';
import 'tournament_logic.dart';
import 'knockout_page.dart';

/// [예선 조별 리그 페이지]
/// 각 조의 순위표를 확인하고 경기 결과를 입력하며, 본선 대진표로 이동하는 화면입니다.
class GroupStagePage extends StatefulWidget {
  final String tournamentBaseTitle; // 대회 기본 제목
  final List<TournamentEvent> allEvents; // 전체 경기 종목 리스트
  final int initialEventIdx; // 시작 시 선택된 종목 인덱스
  final VoidCallback onDataChanged; // 데이터 변경 시 저장을 위한 콜백

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

  @override
  void initState() {
    super.initState();
    _currentEventIdx = widget.initialEventIdx;
    _refreshRankings();
  }

  // 현재 종목의 순위 데이터 새로고침
  void _refreshRankings() {
    _manualRankings.clear();
    if (_currentEvent.groups != null) {
      for (int i = 0; i < _currentEvent.groups!.length; i++) {
        _manualRankings[i] = TournamentLogic.getGroupRankings(_currentEvent.groups![i]);
      }
    }
  }

  // 종목 변경 처리
  void _switchEvent(int newIdx) {
    setState(() {
      _currentEventIdx = newIdx;
      _refreshRankings();
    });
  }

  /// [테스트용] 무작위 점수 입력
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
          // 상단 앱바에 대회명을 제외하고 종목명만 표시하도록 수정
          title: Text(_currentEvent.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
          actions: [
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
                  margin: const EdgeInsets.all(12),
                  child: Column(children: [
                    ListTile(
                      tileColor: const Color(0xFF1A535C).withOpacity(0.05),
                      title: Text('${group.name} (${group.players.length}명)', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    _buildRankingTable(rankings, group, index),
                    const Divider(),
                    ...group.matches.map((m) => _buildMatchTile(m, index)),
                  ]),
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

  Widget _buildMatchTile(Match m, int groupIdx) {
    return ListTile(
      title: Row(children: [
        Expanded(child: _playerSmallInfo(m.player1, TextAlign.right)),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
          child: Text(m.status == MatchStatus.withdrawal ? '기권' : '${m.score1} : ${m.score2}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(child: _playerSmallInfo(m.player2, TextAlign.left)),
      ]),
      onTap: () => _showScoreDialog(m, groupIdx),
    );
  }

  Widget _playerSmallInfo(Player? p, TextAlign align) => Column(
    crossAxisAlignment: align == TextAlign.right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      Text(p?.name ?? 'BYE', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
      if (p != null) Text(p.affiliation, style: const TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis),
    ],
  );

  /// [예선 순위표 위젯 빌더]
  /// 조별 리그 순위 정보를 테이블 형태로 보여줍니다.
  /// 사용자가 각 열의 너비를 쉽게 조절할 수 있도록 변수로 분리하고, 화살표 버튼의 여백을 최소화했습니다.
  Widget _buildRankingTable(List<Player> rankings, Group group, int groupIdx) {
    // 경기 결과를 바탕으로 계산된 상세 통계 정보를 가져옵니다.
    final stats = TournamentLogic.getRankingStats(group);

    // --- [사용자 설정: 표 열 너비 간격 비율] ---
    // 아래의 숫자들을 수정하여 표의 각 열 간격을 원하는 대로 조절할 수 있습니다.
    final Map<int, TableColumnWidth> customColumnWidths = {
      0: const FlexColumnWidth(0.5), // '순위' 열 너비
      1: const FlexColumnWidth(2.2), // '이름(소속)' 열 너비 (가장 넓게 설정)
      2: const FlexColumnWidth(0.5), // '승' 열 너비
      3: const FlexColumnWidth(0.5), // '득' 열 너비
      4: const FlexColumnWidth(0.5), // '실' 열 너비
      5: const FlexColumnWidth(0.6), // '득실' 열 너비
      6: const FlexColumnWidth(0.6), // '조정' 열 너비 (화살표 버튼 칸)
    };

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Table(
            // 표의 테두리 색상 및 스타일 설정
            border: TableBorder.all(color: Colors.grey.shade300),
            // 위에서 정의한 사용자 정의 열 너비를 적용합니다.
            columnWidths: customColumnWidths,
            // 모든 셀 내부의 텍스트가 세로 방향 중앙에 오도록 설정합니다.
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              // 1. 테이블 헤더 (첫 줄: 각 항목의 제목)
              TableRow(
                decoration: const BoxDecoration(color: Color(0x6622BABB)), // 헤더 줄 배경색
                children: [
                  for (var h in ['순위', '이름(소속)', '승', '득', '실', '득실', '조정'])
                    _tableCell(h, isBold: true),
                ],
              ),
              
              // 2. 선수별 데이터 행 (Rankings 데이터를 기반으로 생성)
              ...rankings.asMap().entries.map((e) {
                final index = e.key;      // 순위 인덱스 (0, 1, 2...)
                final player = e.value;   // 해당 순위의 선수 정보
                final s = stats[player]!; // 해당 선수의 상세 통계 데이터

                // 본선 진출 인원 내에 포함되는 순위인지 확인 (강조 표시용)
                final bool isQualified = index < _currentEvent.settings.advancingCount;

                return TableRow(
                  children: [
                    // [순위] 본선 진출자는 파란색으로, 나머지는 검은색으로 표시
                    _tableCell('${index + 1}', color: isQualified ? Colors.blue : Colors.black),
                    
                    // [이름(소속)] 글자가 길어지면 줄바꿈 대신 생략표시(...) 사용
                    TableCell(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                        child: Text(
                          '${player.name}(${player.affiliation})',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    
                    // [승, 득, 실, 득실차] 데이터 표시 영역
                    _tableCell('${s['wins']}'),
                    _tableCell('${s['won']}'),
                    _tableCell('${s['lost']}'),
                    _tableCell('${s['diff']}'),
                    
                    // [조정 버튼] 화살표 버튼 주위와 칸 내부의 여백을 최소화하여 코딩함
                    TableCell(
                      child: Container(
                        padding: EdgeInsets.zero, // 셀 자체의 내부 여백을 없앰
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min, // 행의 너비를 필요한 만큼만 차지
                          children: [
                            // 위로 이동 버튼 (GestureDetector를 사용하여 여백 없이 클릭 구현)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: index == 0 ? null : () => _moveRank(groupIdx, index, -1),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 4.0), // 클릭을 위한 최소 여백
                                child: Icon(
                                  Icons.arrow_upward, 
                                  size: 16, 
                                  color: index == 0 ? Colors.grey.shade300 : Colors.blue,
                                ),
                              ),
                            ),
                            // 아래로 이동 버튼
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: index == rankings.length - 1 ? null : () => _moveRank(groupIdx, index, 1),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 4.0),
                                child: Icon(
                                  Icons.arrow_downward, 
                                  size: 16, 
                                  color: index == rankings.length - 1 ? Colors.grey.shade300 : Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
          
          // --- [Accept 버튼 영역] ---
          // 코딩 수정 사항을 확정하고 저장하기 위한 버튼입니다.
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: ElevatedButton.icon(
              onPressed: () {
                // 변경된 순위 데이터를 최종 확정하여 저장합니다.
                widget.onDataChanged();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('순위 조정 사항이 성공적으로 확정되었습니다.')),
                );
              },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('순위 확정 (Accept)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A535C), // 버튼 배경색
                foregroundColor: Colors.white,            // 버튼 글자색
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,                   // 버튼의 최소 크기 제약을 해제
                tapTargetSize: MaterialTapTargetSize.shrinkWrap, // 터치 영역을 버튼 크기에 맞춤
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableCell(String t, {bool isBold = false, Color color = Colors.black}) => TableCell(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(t, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color, fontSize: 12))
      )
    )
  );

  void _moveRank(int gIdx, int cur, int dir) {
    setState(() {
      final list = _manualRankings[gIdx]!;
      final item = list.removeAt(cur);
      list.insert(cur + dir, item);
    });
  }

  void _showScoreDialog(Match m, int gIdx) {
    int s1 = m.score1; int s2 = m.score2;
    showModalBottomSheet(context: context, builder: (context) => StatefulBuilder(builder: (context, setS) => Container(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Expanded(child: _playerSmallInfo(m.player1, TextAlign.right)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('VS', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: _playerSmallInfo(m.player2, TextAlign.left)),
        ]),
        const SizedBox(height: 20),
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

  Widget _counter(Function(int) onU, int v) => Column(children: [
    IconButton(onPressed: () => onU(v + 1), icon: const Icon(Icons.add_circle_outline)),
    Text('$v', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    IconButton(onPressed: () => onU(v > 0 ? v - 1 : 0), icon: const Icon(Icons.remove_circle_outline)),
  ]);
}
