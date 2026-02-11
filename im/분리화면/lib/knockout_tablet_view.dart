import 'package:flutter/material.dart';
import 'models.dart';
import 'tournament_logic.dart';
import 'knockout_print_logic.dart';
import 'dart:math' as math;

class KnockoutTabletView extends StatefulWidget {
  final String tournamentTitle;
  final List<Round> rounds;
  final VoidCallback onDataChanged;
  final List<TournamentEvent> events;

  const KnockoutTabletView({
    super.key,
    required this.tournamentTitle,
    required this.rounds,
    required this.onDataChanged,
    required this.events,
  });

  @override
  State<KnockoutTabletView> createState() => _KnockoutTabletViewState();
}

class _KnockoutTabletViewState extends State<KnockoutTabletView> {
  // 태블릿용에서는 디자인 수치를 조금 더 넉넉하게 가져갈 수 있습니다.
  final double matchWidth = 240.0;
  final double roundWidth = 320.0;
  
  double get matchHeight => _isTeamMatch ? 180.0 : 100.0;
  double get itemHeight => _isTeamMatch ? 250.0 : 160.0;

  final Set<String> _selectedMatchIds = {};
  bool _isSelectionExpanded = true; // 태블릿은 기본적으로 확장해서 보여줌

  String get _eventName {
    if (widget.tournamentTitle.contains(' - ')) {
      return widget.tournamentTitle.split(' - ').last;
    }
    return widget.tournamentTitle;
  }

  bool get _isTeamMatch => _eventName.contains('단체');

  @override
  Widget build(BuildContext context) {
    int firstCount = widget.rounds[0].matches.length;
    double totalH = (firstCount * itemHeight) + 300, totalW = (widget.rounds.length + 1) * roundWidth;
    
    return Scaffold(
      backgroundColor: const Color(0xFFE9EEF5), // 태블릿은 조금 더 고급스러운 배경색
      appBar: AppBar(
        title: Text(_eventName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
        actions: [
          if (_selectedMatchIds.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () async {
                await KnockoutPrintLogic.showPrintPreview(context, widget.tournamentTitle, widget.rounds, _selectedMatchIds, () { setState(() {}); widget.onDataChanged(); });
                setState(() { _selectedMatchIds.clear(); });
              },
              icon: const Icon(Icons.print),
              label: Text('${_selectedMatchIds.length}개 인쇄'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            ),
          const SizedBox(width: 20),
        ],
      ),
      body: Row(
        children: [
          // 사이드바 영역 (나중에 종목 리스트 등을 여기에 고정할 수 있습니다)
          if (_isSelectionExpanded)
            Container(
              width: 250,
              color: Colors.white,
              child: Column(
                children: [
                  const Padding(padding: EdgeInsets.all(16), child: Text('경기 목록', style: TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(
                    child: ListView.builder(
                      itemCount: widget.events.length,
                      itemBuilder: (context, index) => ListTile(
                        title: Text(widget.events[index].name, style: const TextStyle(fontSize: 14)),
                        selected: widget.events[index].name == _eventName,
                        onTap: () => Navigator.pop(context, index),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // 메인 대진표 영역
          Expanded(
            child: InteractiveViewer(
              constrained: false,
              boundaryMargin: const EdgeInsets.all(500),
              minScale: 0.05,
              maxScale: 3.0,
              child: Container(
                width: totalW,
                height: totalH,
                padding: const EdgeInsets.all(100),
                child: Stack(clipBehavior: Clip.none, children: [
                  CustomPaint(
                      size: Size(totalW, totalH),
                      painter: BracketLinkPainter(
                          rounds: widget.rounds, matchWidth: matchWidth, matchHeight: matchHeight, roundWidth: roundWidth, itemHeight: itemHeight, activeColor: const Color(0xFF4ECDC4))),
                  ..._buildBracketNodes(),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ... 나머지 UI 빌드 로직은 모바일과 유사하되 태블릿 전용으로 커스텀 가능 ...
  // (지면 관계상 핵심 구조만 작성하며, 실제 구현 시 모바일 코드를 기반으로 확장합니다)
  List<Widget> _buildBracketNodes() {
    List<Widget> nodes = [];
    for (int r = 0; r < widget.rounds.length; r++) {
      nodes.add(Positioned(left: r * roundWidth, top: 0, child: Container(width: matchWidth, alignment: Alignment.center, child: Text(widget.rounds[r].name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)))));
      for (int m = 0; m < widget.rounds[r].matches.length; m++) {
        double topPos = (m * math.pow(2, r) + (math.pow(2, r) - 1) / 2) * itemHeight + 20;
        nodes.add(Positioned(left: r * roundWidth, top: topPos - 32, child: _buildMatchCard(widget.rounds[r].matches[m], r, m)));
      }
    }
    return nodes;
  }

  Widget _buildMatchCard(Match m, int r, int idx) {
    // 태블릿에서는 클릭 시 showDialog(중앙 팝업)를 띄우도록 설계할 예정입니다.
    return Container(
      width: matchWidth,
      height: matchHeight,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
      child: Center(child: Text(m.player1?.name ?? 'TBD')),
    );
  }
}

class BracketLinkPainter extends CustomPainter {
  final List<Round> rounds; final double matchWidth, matchHeight, roundWidth, itemHeight; final Color activeColor;
  BracketLinkPainter({required this.rounds, required this.matchWidth, required this.matchHeight, required this.roundWidth, required this.itemHeight, required this.activeColor});
  @override
  void paint(Canvas canvas, Size size) {
    final pBase = Paint()..color = Colors.grey.shade400..strokeWidth = 2.0..style = PaintingStyle.stroke;
    for (int r = 0; r < rounds.length - 1; r++) {
      for (int m = 0; m < rounds[r].matches.length; m++) {
        final match = rounds[r].matches[m]; if (match.nextMatchId == null) continue;
        double sX = r * roundWidth + matchWidth, sY = (m * math.pow(2, r) + (math.pow(2, r) - 1) / 2) * itemHeight + 20 + (matchHeight / 2);
        double eX = (r + 1) * roundWidth, eY = (m ~/ 2 * math.pow(2, r + 1) + (math.pow(2, r + 1) - 1) / 2) * itemHeight + 20 + (matchHeight / 2);
        final path = Path()..moveTo(sX, sY)..lineTo(sX + (eX - sX) / 2, sY)..lineTo(sX + (eX - sX) / 2, eY)..lineTo(eX, eY);
        canvas.drawPath(path, pBase);
      }
    }
  }
  @override bool shouldRepaint(CustomPainter oldDelegate) => true;
}
