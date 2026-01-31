import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart' show Colors, IconButton, Icons, Scaffold, AppBar, Text, TextButton, Padding, Navigator, StatefulWidget, State, VoidCallback, BuildContext, InteractiveViewer, Container, Stack, Positioned, CustomPaint, Size, Canvas, Paint, PaintingStyle, Path, InkWell, GestureDetector, HitTestBehavior, SizedBox, Divider, FontWeight, TextStyle, Alignment, BorderRadius, BoxShadow, BoxDecoration, Border, Radius, BoxShape, BorderSide, Clip, Color, math, showModalBottomSheet, StatefulBuilder, Row, Expanded, Column, MainAxisSize, MainAxisAlignment, CrossAxisAlignment, TextAlign, ElevatedButton, TextOverflow, RoundedRectangleBorder, EdgeInsets, Widget, PreferredSize, MaterialPageRoute;
import 'models.dart';
import 'tournament_logic.dart';
import 'knockout_print_logic.dart';
import 'dart:math' as math;

class KnockoutPage extends StatefulWidget {
  final String tournamentTitle;
  final List<Round> rounds;
  final VoidCallback onDataChanged;
  final List<TournamentEvent> events;

  const KnockoutPage({
    super.key,
    required this.tournamentTitle,
    required this.rounds,
    required this.onDataChanged,
    required this.events,
  });

  @override
  State<KnockoutPage> createState() => _KnockoutPageState();
}

class _KnockoutPageState extends State<KnockoutPage> {
  final double matchWidth = 220.0, matchHeight = 100.0, roundWidth = 280.0, itemHeight = 160.0;
  final Set<String> _selectedMatchIds = {};
  bool _isSelectionExpanded = false;

  String get _eventName {
    if (widget.tournamentTitle.contains(' - ')) {
      return widget.tournamentTitle.split(' - ').last;
    }
    return widget.tournamentTitle;
  }

  void _toggleMatchSelection(String matchId) {
    setState(() {
      if (_selectedMatchIds.contains(matchId)) {
        _selectedMatchIds.remove(matchId);
      } else {
        _selectedMatchIds.add(matchId);
        _propagateSelectionBackward(matchId);
      }
    });
  }

  void _propagateSelectionBackward(String targetMatchId) {
    for (int r = 1; r < widget.rounds.length; r++) {
      bool foundInRound = widget.rounds[r].matches.any((m) => m.id == targetMatchId);
      if (foundInRound) {
        for (var prevMatch in widget.rounds[r - 1].matches) {
          if (prevMatch.nextMatchId == targetMatchId) {
            bool isFinished = prevMatch.status == MatchStatus.completed || prevMatch.status == MatchStatus.withdrawal;
            if (!isFinished) {
              _selectedMatchIds.add(prevMatch.id);
              _propagateSelectionBackward(prevMatch.id);
            }
          }
        }
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    int firstCount = widget.rounds[0].matches.length;
    double totalH = (firstCount * itemHeight) + 200, totalW = (widget.rounds.length + 1) * roundWidth;
    
    final otherActiveEvents = widget.events.where((e) => 
      e.name != _eventName && 
      e.knockoutRounds != null && 
      e.knockoutRounds!.isNotEmpty
    ).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: Text(_eventName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: false,
        actions: [
          if (_selectedMatchIds.isNotEmpty)
            IconButton(
              onPressed: () => KnockoutPrintLogic.showPrintPreview(
                context, widget.tournamentTitle, widget.rounds, _selectedMatchIds, 
                () { setState(() {}); widget.onDataChanged(); } // 인쇄 시 상태 갱신 및 저장
              ),
              icon: const material.Icon(Icons.print, color: Colors.green),
              tooltip: '${_selectedMatchIds.length}개 경기 출력',
            ),
          IconButton(
            icon: material.Icon(_isSelectionExpanded ? Icons.expand_less : Icons.apps, color: Colors.blue),
            onPressed: () { setState(() { _isSelectionExpanded = !_isSelectionExpanded; }); },
            tooltip: '다른 종목 보기',
          ),
        ],
        bottom: _isSelectionExpanded 
          ? PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Container(
                height: 60,
                color: Colors.white,
                child: otherActiveEvents.isEmpty 
                  ? material.Center(child: Text('다른 진행 중인 종목이 없습니다.', style: TextStyle(fontSize: 12, color: Colors.grey[600])))
                  : material.ListView.builder(
                      scrollDirection: material.Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      itemCount: otherActiveEvents.length,
                      itemBuilder: (context, index) => _categoryButton(otherActiveEvents[index]),
                    ),
              ),
            )
          : null,
      ),
      body: InteractiveViewer(
        constrained: false,
        boundaryMargin: const EdgeInsets.all(100),
        minScale: 0.1,
        maxScale: 2.0,
        child: Container(
          width: totalW,
          height: totalH,
          padding: const EdgeInsets.all(40),
          child: Stack(clipBehavior: Clip.none, children: [
            CustomPaint(
                size: Size(totalW, totalH),
                painter: BracketLinkPainter(
                    rounds: widget.rounds, matchWidth: matchWidth, matchHeight: matchHeight, roundWidth: roundWidth, itemHeight: itemHeight, activeColor: const Color(0xFF4ECDC4))),
            ..._buildBracketNodes(),
          ]),
        ),
      ),
    );
  }

  Widget _categoryButton(TournamentEvent event) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: material.ActionChip(
        label: Text(event.name, style: const TextStyle(fontSize: 12)),
        backgroundColor: Colors.grey.shade100,
        side: BorderSide(color: Colors.grey.shade300),
        onPressed: () {
          setState(() { _isSelectionExpanded = false; });
          Navigator.pop(context, widget.events.indexOf(event));
        },
      ),
    );
  }

  List<Widget> _buildBracketNodes() {
    List<Widget> nodes = [];
    for (int r = 0; r < widget.rounds.length; r++) {
      nodes.add(Positioned(
          left: r * roundWidth,
          top: 0,
          child: Container(
              width: matchWidth,
              alignment: Alignment.center,
              child: Text(widget.rounds[r].name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)))));
      for (int m = 0; m < widget.rounds[r].matches.length; m++) {
        double topPos = (m * math.pow(2, r) + (math.pow(2, r) - 1) / 2) * itemHeight + 20;
        nodes.add(Positioned(left: r * roundWidth, top: topPos - 32, child: _buildMatchCard(widget.rounds[r].matches[m], r, m)));
      }
    }
    return nodes;
  }

  Widget _buildMatchCard(Match m, int roundIndex, int matchIndex) {
    bool isSelected = _selectedMatchIds.contains(m.id);
    bool isFinished = m.status == MatchStatus.completed || m.status == MatchStatus.withdrawal;
    bool showIcon = false;
    if (m.status == MatchStatus.pending) {
      if (roundIndex == 0) { showIcon = !m.isBye; } 
      else if (roundIndex == 1) { showIcon = true; } 
      else {
        int start = matchIndex * 4;
        int end = (matchIndex + 1) * 4;
        bool ancestorsFinished = true;
        List<Match> grandParentMatches = widget.rounds[roundIndex - 2].matches;
        for (int i = start; i < end; i++) {
          if (i < grandParentMatches.length) {
            Match gpMatch = grandParentMatches[i];
            if (!(gpMatch.status == MatchStatus.completed || gpMatch.status == MatchStatus.withdrawal)) { ancestorsFinished = false; break; }
          }
        }
        showIcon = ancestorsFinished;
      }
    }
    if (showIcon && m.nextMatchId != null && _selectedMatchIds.contains(m.nextMatchId)) { showIcon = false; }

    return SizedBox(
      width: matchWidth,
      height: matchHeight + 32,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          if (showIcon)
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggleMatchSelection(m.id),
                child: Stack(
                  alignment: Alignment.topRight,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.green : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: isSelected ? Colors.green : Colors.blueGrey.withOpacity(0.3)),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                      ),
                      child: material.Icon(isSelected ? Icons.check : Icons.print, size: 18, color: isSelected ? Colors.white : Colors.blueGrey),
                    ),
                    // [추가] 인쇄 횟수 표시 배지 (1회 이상인 경우만)
                    if (m.printCount > 0)
                      Positioned(
                        right: -2, top: -2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          child: Text('${m.printCount}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Container(
              width: matchWidth,
              height: matchHeight,
              decoration: BoxDecoration(
                  color: isSelected ? Colors.green.withOpacity(0.05) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isSelected ? Colors.green : isFinished ? const Color(0xFF4ECDC4) : Colors.grey.shade300, width: 2)),
              child: InkWell(
                  onTap: (m.player1 == null || m.player2 == null) ? null : () {
                          setState(() {
                            _selectedMatchIds.remove(m.id);
                            if (m.status == MatchStatus.pending) m.status = MatchStatus.inProgress;
                          });
                          _showKnockoutScoreDialog(m);
                        },
                  onLongPress: showIcon ? () => _toggleMatchSelection(m.id) : null,
                  child: Column(children: [
                    _playerRow(m.player1, m.score1, m.winner == m.player1 && m.player1 != null, m.status == MatchStatus.withdrawal && m.score1 == -1),
                    const Divider(height: 1),
                    _playerRow(m.player2, m.score2, m.winner == m.player2 && m.player2 != null, m.status == MatchStatus.withdrawal && m.score2 == -1)
                  ]))),
        ],
      ),
    );
  }

  Widget _playerRow(Player? p, int s, bool isW, bool withdrawn) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        color: isW ? const Color(0xFF4ECDC4).withOpacity(0.1) : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p?.name ?? (p == null ? 'BYE' : 'TBD'), style: TextStyle(fontWeight: isW ? FontWeight.bold : FontWeight.normal, fontSize: 13), overflow: TextOverflow.ellipsis),
                  if (p != null) Text(p.affiliation, style: const TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Text(withdrawn ? '기권' : '$s', style: TextStyle(fontWeight: FontWeight.bold, color: withdrawn ? Colors.red : Colors.black)),
          ],
        ),
      ),
    );
  }

  void _showKnockoutScoreDialog(Match m) {
    int s1 = m.score1 == -1 ? 0 : m.score1;
    int s2 = m.score2 == -1 ? 0 : m.score2;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
          builder: (context, setS) => Container(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Expanded(child: _playerPopupInfo(m.player1, textAlign: TextAlign.right)),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('VS', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey))),
                    Expanded(child: _playerPopupInfo(m.player2, textAlign: TextAlign.left)),
                  ]),
                  const SizedBox(height: 30),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _counter((v) => setS(() => s1 = v), s1),
                    const Text(':', style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
                    _counter((v) => setS(() => s2 = v), s2),
                  ]),
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: material.MainAxisAlignment.spaceEvenly, children: [
                    TextButton.icon(onPressed: () => setS(() { s1 = -1; s2 = 0; }), icon: const material.Icon(Icons.flag, color: Colors.red), label: const Text('P1 기권')),
                    TextButton.icon(onPressed: () => setS(() { s1 = 0; s2 = -1; }), icon: const material.Icon(Icons.flag, color: Colors.red), label: const Text('P2 기권')),
                  ]),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        m.score1 = s1; m.score2 = s2;
                        if (s1 == -1 || s2 == -1) { m.status = MatchStatus.withdrawal; m.winner = s1 == -1 ? m.player2 : m.player1; }
                        else { m.status = MatchStatus.completed; m.winner = s1 > s2 ? m.player1 : m.player2; }
                        TournamentLogic.updateKnockoutWinner(widget.rounds, m);
                      });
                      Navigator.pop(context); widget.onDataChanged();
                    },
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56), backgroundColor: const Color(0xFF1A535C), foregroundColor: Colors.white),
                    child: const Text('점수 저장'),
                  )
                ]),
              )),
    );
  }

  material.Widget _playerPopupInfo(Player? p, {required TextAlign textAlign}) => Column(
          crossAxisAlignment: textAlign == TextAlign.right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(p?.name ?? "TBD", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
            Text(p?.affiliation ?? "", style: const TextStyle(fontSize: 14, color: Colors.orange), overflow: TextOverflow.ellipsis),
          ]);

  material.Widget _counter(Function(int) onU, int v) => Column(children: [
        IconButton(onPressed: () => onU(v + 1), icon: const material.Icon(Icons.add_circle, color: Color(0xFF4ECDC4), size: 48)),
        Text(v == -1 ? '기권' : '$v', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Color(0xFF1A535C))),
        IconButton(onPressed: () => onU(v > 0 ? v - 1 : 0), icon: const material.Icon(Icons.remove_circle, color: Colors.redAccent, size: 48)),
      ]);
}

class BracketLinkPainter extends material.CustomPainter {
  final List<Round> rounds; final double matchWidth, matchHeight, roundWidth, itemHeight; final Color activeColor;
  BracketLinkPainter({required this.rounds, required this.matchWidth, required this.matchHeight, required this.roundWidth, required this.itemHeight, required this.activeColor});
  @override
  void paint(Canvas canvas, Size size) {
    final pBase = Paint()..color = material.Colors.grey.shade400..strokeWidth = 1.5..style = PaintingStyle.stroke;
    final pActive = Paint()..color = activeColor..strokeWidth = 2.5..style = PaintingStyle.stroke;
    for (int r = 0; r < rounds.length - 1; r++) {
      for (int m = 0; m < rounds[r].matches.length; m++) {
        final match = rounds[r].matches[m]; if (match.nextMatchId == null) continue;
        final nextMatch = rounds[r + 1].matches.firstWhere((nm) => nm.id == match.nextMatchId);
        double sX = r * roundWidth + matchWidth, sY = (m * math.pow(2, r) + (math.pow(2, r) - 1) / 2) * itemHeight + 20 + (matchHeight / 2);
        double eX = (r + 1) * roundWidth, eY = ((m ~/ 2) * math.pow(2, r + 1) + (math.pow(2, r + 1) - 1) / 2) * itemHeight + 20 + (matchHeight / 2);
        final path = Path()..moveTo(sX, sY)..lineTo(sX + (eX - sX) / 2, sY)..lineTo(sX + (eX - sX) / 2, eY)..lineTo(eX, eY);
        bool shouldHighlight = false;
        if (nextMatch.status == MatchStatus.completed || nextMatch.status == MatchStatus.withdrawal) {
          if (nextMatch.winner != null) {
            if (match.nextMatchSlot == 1 && nextMatch.winner == nextMatch.player1) shouldHighlight = true;
            if (match.nextMatchSlot == 2 && nextMatch.winner == nextMatch.player2) shouldHighlight = true;
          }
        }
        canvas.drawPath(path, shouldHighlight ? pActive : pBase);
      }
    }
  }
  @override
  bool shouldRepaint(material.CustomPainter old) => true;
}
