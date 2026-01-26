import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'models.dart';
import 'tournament_logic.dart';
import 'dart:math' as math;

class KnockoutPage extends StatefulWidget {
  final String tournamentTitle;
  final List<Round> rounds;
  const KnockoutPage({super.key, required this.tournamentTitle, required this.rounds});
  @override
  State<KnockoutPage> createState() => _KnockoutPageState();
}

class _KnockoutPageState extends State<KnockoutPage> {
  final double matchWidth = 220.0, matchHeight = 100.0, roundWidth = 280.0, itemHeight = 160.0;
  final Set<String> _selectedMatchIds = {};

  @override
  Widget build(BuildContext context) {
    int firstCount = widget.rounds[0].matches.length;
    double totalH = (firstCount * itemHeight) + 200, totalW = (widget.rounds.length + 1) * roundWidth;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: Text(widget.tournamentTitle),
        actions: [
          if (_selectedMatchIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: IconButton(
                icon: const Icon(Icons.print, size: 32, color: Colors.green),
                onPressed: _printSelectedMatches,
                tooltip: '선택한 경기 인쇄',
              ),
            ),
        ],
      ),
      body: InteractiveViewer(
        constrained: false, boundaryMargin: const EdgeInsets.all(100), minScale: 0.1, maxScale: 2.0,
        child: Container(width: totalW, height: totalH, padding: const EdgeInsets.all(40), child: Stack(children: [
          CustomPaint(size: Size(totalW, totalH), painter: BracketLinkPainter(rounds: widget.rounds, matchWidth: matchWidth, matchHeight: matchHeight, roundWidth: roundWidth, itemHeight: itemHeight, activeColor: const Color(0xFF4ECDC4))),
          ..._buildBracketNodes(),
        ])),
      ),
    );
  }

  List<Widget> _buildBracketNodes() {
    List<Widget> nodes = [];
    for (int r = 0; r < widget.rounds.length; r++) {
      nodes.add(Positioned(left: r * roundWidth, top: 0, child: Container(width: matchWidth, alignment: Alignment.center, child: Text(widget.rounds[r].name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)))));
      for (int m = 0; m < widget.rounds[r].matches.length; m++) {
        nodes.add(Positioned(
          left: r * roundWidth, 
          top: (m * math.pow(2, r) + (math.pow(2, r) - 1) / 2) * itemHeight + 50 - 30, 
          child: _buildMatchCard(widget.rounds[r].matches[m])
        ));
      }
    }
    return nodes;
  }

  void _togglePrintSelection(Match m) {
    setState(() {
      if (_selectedMatchIds.contains(m.id)) {
        _deselectAncestors(m);
      } else {
        _selectAncestors(m);
      }
    });
  }

  void _selectAncestors(Match m) {
    if (m.status == MatchStatus.pending) _selectedMatchIds.add(m.id);
    for (var round in widget.rounds) {
      for (var prevMatch in round.matches) {
        if (prevMatch.nextMatchId == m.id) _selectAncestors(prevMatch);
      }
    }
  }

  void _deselectAncestors(Match m) {
    _selectedMatchIds.remove(m.id);
    for (var round in widget.rounds) {
      for (var prevMatch in round.matches) {
        if (prevMatch.nextMatchId == m.id) _deselectAncestors(prevMatch);
      }
    }
  }

  Future<void> _printSelectedMatches() async {
    final pdf = pw.Document();
    final List<Match> selectedMatches = [];
    // 선택된 경기들을 수집
    for (var round in widget.rounds) {
      for (var match in round.matches) {
        if (_selectedMatchIds.contains(match.id)) {
          selectedMatches.add(match);
        }
      }
    }

    if (selectedMatches.isEmpty) return;

    // 한글 폰트 로드
    final font = await PdfGoogleFonts.nanumGothicBold();

    for (int i = 0; i < selectedMatches.length; i += 2) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(0),
          build: (pw.Context context) {
            return pw.Column(
              children: [
                pw.Expanded(child: _buildPdfSection(selectedMatches[i], font)),
                if (i + 1 < selectedMatches.length) ...[
                  pw.Stack(
                    alignment: pw.Alignment.center,
                    children: [
                      pw.Container(
                        width: double.infinity,
                        height: 20,
                        child: pw.CustomPaint(
                          painter: (canvas, size) {
                            canvas.setStrokeColor(PdfColors.red);
                            canvas.setLineWidth(1.5);
                            double dashWidth = 5;
                            double dashSpace = 5;
                            double currentX = 0;
                            while (currentX < size.x) {
                              canvas.moveTo(currentX, size.y / 2);
                              canvas.lineTo(math.min(currentX + dashWidth, size.x), size.y / 2);
                              currentX += dashWidth + dashSpace;
                            }
                            canvas.strokePath();
                          },
                        ),
                      ),
                      pw.Container(
                        color: PdfColors.white,
                        padding: const pw.EdgeInsets.symmetric(horizontal: 20),
                        child: pw.Text('✂ 절취선 (CUT HERE) ✂', style: pw.TextStyle(font: font, fontSize: 12, color: PdfColors.red)),
                      ),
                    ],
                  ),
                  pw.Expanded(child: _buildPdfSection(selectedMatches[i + 1], font)),
                ] else pw.Expanded(child: pw.Container()),
              ],
            );
          },
        ),
      );
    }

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  pw.Widget _buildPdfSection(Match m, pw.Font font) {
    String currentRound = "";
    String nextRound = "";
    for (int i = 0; i < widget.rounds.length; i++) {
      if (widget.rounds[i].matches.contains(m)) {
        currentRound = widget.rounds[i].name;
        if (i + 1 < widget.rounds.length) nextRound = widget.rounds[i + 1].name;
        break;
      }
    }

    return pw.Container(
      width: double.infinity,
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(widget.tournamentTitle, style: pw.TextStyle(font: font, fontSize: 28, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 20),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Column(
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    decoration: pw.BoxDecoration(color: PdfColors.blue50, borderRadius: pw.BorderRadius.circular(4)),
                    child: pw.Text(currentRound, style: pw.TextStyle(font: font, fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                  ),
                  pw.SizedBox(height: 15),
                  _playerPdfCard(m.player1, font),
                  pw.SizedBox(height: 12),
                  _playerPdfCard(m.player2, font),
                ],
              ),
              pw.Container(
                width: 80,
                height: 180,
                child: pw.Center(
                  child: pw.Container(
                    width: 40,
                    height: 110,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        top: pw.BorderSide(color: PdfColors.grey400, width: 2),
                        bottom: pw.BorderSide(color: PdfColors.grey400, width: 2),
                        right: pw.BorderSide(color: PdfColors.grey400, width: 2),
                      ),
                    ),
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Container(width: 20, height: 2, color: PdfColors.grey400),
                    ),
                  ),
                ),
              ),
              pw.Column(
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    decoration: pw.BoxDecoration(color: PdfColors.blue50, borderRadius: pw.BorderRadius.circular(4)),
                    child: pw.Text(nextRound.isNotEmpty ? nextRound : "승자", style: pw.TextStyle(font: font, fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                  ),
                  pw.SizedBox(height: 15),
                  pw.Container(
                    width: 280,
                    height: 90,
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(8)),
                    child: pw.Row(children: [pw.Expanded(child: pw.Container()), pw.Container(width: 60, color: PdfColors.blue300)]),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _playerPdfCard(Player? p, pw.Font font) {
    return pw.Container(
      width: 280,
      height: 85,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColors.grey300, width: 1),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(p?.name ?? "TBD", style: pw.TextStyle(font: font, fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text(p?.affiliation ?? "", style: pw.TextStyle(font: font, fontSize: 14, color: PdfColors.grey700)),
                ],
              ),
            ),
          ),
          pw.Container(width: 60, color: PdfColors.blue300),
        ],
      ),
    );
  }

  Widget _buildMatchCard(Match m) {
    bool showPrintIcon = m.status == MatchStatus.pending;
    bool isSelected = _selectedMatchIds.contains(m.id);
    return Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: 30, width: matchWidth, child: showPrintIcon ? Align(alignment: Alignment.bottomRight, child: GestureDetector(onTap: () => _togglePrintSelection(m), behavior: HitTestBehavior.opaque, child: Padding(padding: const EdgeInsets.only(right: 8, bottom: 4), child: Icon(Icons.print_outlined, size: 24, color: isSelected ? Colors.green : Colors.grey.shade600)))) : const SizedBox.shrink()),
        Container(width: matchWidth, height: matchHeight, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: (m.status == MatchStatus.completed || m.status == MatchStatus.withdrawal) ? const Color(0xFF4ECDC4) : Colors.grey.shade300, width: (m.status == MatchStatus.completed || m.status == MatchStatus.withdrawal) ? 2 : 1)),
          child: InkWell(onTap: (m.player1 == null || m.player2 == null) ? null : () => _showKnockoutScoreDialog(m), child: Column(children: [_playerRow(m.player1, m.score1, m.winner == m.player1 && m.player1 != null, m.status == MatchStatus.withdrawal && m.score1 == -1), const Divider(height: 1), _playerRow(m.player2, m.score2, m.winner == m.player2 && m.player2 != null, m.status == MatchStatus.withdrawal && m.score2 == -1)]))),
    ]);
  }

  Widget _playerRow(Player? p, int s, bool isW, bool withdrawn) => Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), color: isW ? const Color(0xFF4ECDC4).withOpacity(0.1) : Colors.transparent, child: Row(children: [Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(p?.name ?? (p == null ? 'BYE' : 'TBD'), style: TextStyle(fontWeight: isW ? FontWeight.bold : FontWeight.normal, fontSize: 13), overflow: TextOverflow.ellipsis), if (p != null) Text(p.affiliation, style: const TextStyle(fontSize: 13, color: Colors.grey), overflow: TextOverflow.ellipsis)])), Text(withdrawn ? '기권' : '$s', style: TextStyle(fontWeight: FontWeight.bold, color: isW ? const Color(0xFF1A535C) : (withdrawn ? Colors.red : Colors.black)))])));

  void _showKnockoutScoreDialog(Match m) {
    int s1 = m.score1 == -1 ? 0 : m.score1, s2 = m.score2 == -1 ? 0 : m.score2;
    showDialog(context: context, builder: (context) => AlertDialog(title: const Text('결과 입력'), content: StatefulBuilder(builder: (context, setS) => Column(mainAxisSize: MainAxisSize.min, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_cnt(m.player1!.name, (v) => setS(() => s1 = v), s1), const Text('VS'), _cnt(m.player2!.name, (v) => setS(() => s2 = v), s2)]), if (s1 == -1 || s2 == -1) const Padding(padding: EdgeInsets.only(top: 10), child: Text('기권 처리', style: TextStyle(color: Colors.red)))] )),
      actions: [TextButton(onPressed: () { setState(() { m.score1 = s1; m.score2 = s2; if (s1 == -1 || s2 == -1) { m.status = MatchStatus.withdrawal; m.winner = s1 == -1 ? m.player2 : m.player1; } else { m.status = MatchStatus.completed; m.winner = s1 > s2 ? m.player1 : m.player2; } _selectedMatchIds.remove(m.id); TournamentLogic.updateKnockoutWinner(widget.rounds, m); }); Navigator.pop(context); }, child: const Text('저장'))]));
  }

  Widget _cnt(String n, Function(int) onU, int v) => Column(mainAxisSize: MainAxisSize.min, children: [Text(n, style: const TextStyle(fontSize: 12)), IconButton(onPressed: () => onU(v + 1), icon: const Icon(Icons.add_circle_outline)), Text(v == -1 ? '기권' : '$v', style: TextStyle(fontSize: v == -1 ? 16 : 24, fontWeight: FontWeight.bold)), IconButton(onPressed: () => onU(v > -1 ? v - 1 : -1), icon: const Icon(Icons.remove_circle_outline))]);

  Widget _buildWinnerCard(Player w) => Container(width: matchWidth * 0.8, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1A535C), borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: const Color(0xFF4ECDC4).withOpacity(0.4), blurRadius: 10)]), child: Column(children: [const Icon(Icons.emoji_events, color: Colors.yellow, size: 24), Text(w.name, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)), Text(w.affiliation, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13))]));
}

class BracketLinkPainter extends CustomPainter {
  final List<Round> rounds;
  final double matchWidth, matchHeight, roundWidth, itemHeight;
  final Color activeColor;
  BracketLinkPainter({required this.rounds, required this.matchWidth, required this.matchHeight, required this.roundWidth, required this.itemHeight, required this.activeColor});
  @override
  void paint(Canvas canvas, Size size) {
    final pBase = Paint()..color = Colors.grey.shade400..strokeWidth = 1.5..style = PaintingStyle.stroke;
    final pActive = Paint()..color = activeColor..strokeWidth = 2.5..style = PaintingStyle.stroke;
    for (int r = 0; r < rounds.length - 1; r++) {
      for (int m = 0; m < rounds[r].matches.length; m++) {
        final match = rounds[r].matches[m];
        if (match.nextMatchId == null) continue;
        final nextMatch = rounds[r + 1].matches.firstWhere((nm) => nm.id == match.nextMatchId);
        double sX = r * roundWidth + matchWidth, sY = (m * math.pow(2, r) + (math.pow(2, r) - 1) / 2) * itemHeight + 50 + (matchHeight / 2);
        double eX = (r + 1) * roundWidth, eY = ((m ~/ 2) * math.pow(2, r + 1) + (math.pow(2, r + 1) - 1) / 2) * itemHeight + 50 + (matchHeight / 2);
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
  @override bool shouldRepaint(CustomPainter old) => true;
}
