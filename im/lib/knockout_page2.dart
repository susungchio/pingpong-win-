import 'dart:typed_data';
import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart' show Colors, IconButton, Icons, Scaffold, AppBar, Text, TextButton, Padding, MaterialPageRoute, Navigator, StatefulWidget, State, VoidCallback, BuildContext, InteractiveViewer, Container, Stack, Positioned, CustomPaint, Size, Canvas, Paint, PaintingStyle, Path, InkWell, GestureDetector, HitTestBehavior, SizedBox, Divider, FontWeight, TextStyle, Alignment, BorderRadius, BoxShadow, BoxDecoration, Border, Radius, BoxShape, BorderSide, Clip, Color, math, showModalBottomSheet, StatefulBuilder, Row, Expanded, Column, MainAxisSize, MainAxisAlignment, CrossAxisAlignment, TextAlign, ElevatedButton, TextOverflow, CircleAvatar, ListTile, RoundedRectangleBorder, EdgeInsets, Widget;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'models.dart';
import 'tournament_logic.dart';
import 'dart:math' as math;

/// [본선 토너먼트 페이지]
/// 대진표를 보여주고, 경기 결과 입력 및 기록지 인쇄 기능을 제공합니다.
class KnockoutPage extends StatefulWidget {
  final String tournamentTitle;
  final List<Round> rounds;
  final VoidCallback onDataChanged;

  const KnockoutPage({
    super.key,
    required this.tournamentTitle,
    required this.rounds,
    required this.onDataChanged,
  });

  @override
  State<KnockoutPage> createState() => _KnockoutPageState();
}

class _KnockoutPageState extends State<KnockoutPage> {
  final double matchWidth = 220.0, matchHeight = 100.0, roundWidth = 280.0, itemHeight = 160.0;
  final Set<String> _selectedMatchIds = {};

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
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: Text(widget.tournamentTitle),
        actions: [
          if (_selectedMatchIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: TextButton.icon(
                onPressed: _showPrintPreview,
                icon: const material.Icon(Icons.print, color: Colors.green),
                label: Text('${_selectedMatchIds.length}개 출력/미리보기', 
                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
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
                    rounds: widget.rounds,
                    matchWidth: matchWidth,
                    matchHeight: matchHeight,
                    roundWidth: roundWidth,
                    itemHeight: itemHeight,
                    activeColor: const Color(0xFF4ECDC4))),
            ..._buildBracketNodes(),
          ]),
        ),
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
        nodes.add(Positioned(left: r * roundWidth, top: topPos - 32, child: _buildMatchCard(widget.rounds[r].matches[m], r)));
      }
    }
    return nodes;
  }

  Widget _buildMatchCard(Match m, int roundIndex) {
    bool isSelected = _selectedMatchIds.contains(m.id);
    bool isFinished = m.status == MatchStatus.completed || m.status == MatchStatus.withdrawal;
    bool showIcon = !isFinished;
    if (roundIndex == 0 && m.isBye) showIcon = false;

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
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.green : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: isSelected ? Colors.green : Colors.blueGrey.withOpacity(0.3)),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                  ),
                  child: material.Icon(isSelected ? Icons.check : Icons.print, size: 18, color: isSelected ? Colors.white : Colors.blueGrey),
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
                  onTap: (m.player1 == null || m.player2 == null) ? null : () => _showKnockoutScoreDialog(m),
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
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
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

  // ===========================================================================
  // 인쇄(PDF) 관련 코드
  // ===========================================================================

  void _showPrintPreview() {
    Navigator.push(context, material.MaterialPageRoute(builder: (context) => material.Scaffold(
      appBar: material.AppBar(title: const material.Text('경기 기록지 인쇄 미리보기')),
      body: PdfPreview(
        build: (format) => _generatePdf(format),
        allowPrinting: true, allowSharing: true, initialPageFormat: PdfPageFormat.a4.landscape, 
        pdfFileName: 'match_sheets.pdf', canChangePageFormat: false,
      ),
    )));
  }

  Future<Uint8List> _generatePdf(PdfPageFormat format) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.nanumGothicRegular();
    final fontBold = await PdfGoogleFonts.nanumGothicBold();

    // 1. 블록별 경기 분류 (8인 단위)
    Map<int, List<Match>> blockGroups = {}; 
    int? getBlockIdx(String mId) {
      for (int i = 0; i < widget.rounds[0].matches.length; i++) {
        if (widget.rounds[0].matches[i].id == mId) return i ~/ 4;
      }
      if (widget.rounds.length > 1) {
        for (int i = 0; i < widget.rounds[1].matches.length; i++) {
          if (widget.rounds[1].matches[i].id == mId) return i ~/ 2;
        }
      }
      if (widget.rounds.length > 2) {
        for (int i = 0; i < widget.rounds[2].matches.length; i++) {
          if (widget.rounds[2].matches[i].id == mId) return i;
        }
      }
      return null;
    }

    // 선택된 경기 수집 및 블록화
    for (var r in widget.rounds) {
      for (var m in r.matches) {
        if (_selectedMatchIds.contains(m.id)) {
          int? bIdx = getBlockIdx(m.id);
          if (bIdx != null) blockGroups.putIfAbsent(bIdx, () => []).add(m);
        }
      }
    }

    List<dynamic> printItems = [];
    var sortedBlockIndices = blockGroups.keys.toList()..sort();

    for (var bIdx in sortedBlockIndices) {
      var matchesInBlock = blockGroups[bIdx]!;
      // 블록 내 2개 이상의 경기 선택 OR 미확정 경기(TBD)가 있으면 브래킷 사용
      bool needsBracket = matchesInBlock.length > 1 || matchesInBlock.any((m) => m.player1 == null || m.player2 == null);
      
      if (needsBracket) {
        printItems.add({'type': 'bracket', 'index': bIdx});
      } else {
        // 단일 확정 경기(2인) -> 청록색 표 양식
        Match m = matchesInBlock.first;
        String rName = "";
        for (var r in widget.rounds) if (r.matches.any((match) => match.id == m.id)) { rName = r.name; break; }
        printItems.add({'type': 'standalone', 'match': m, 'roundName': rName});
      }
    }

    // 2. 한 페이지에 2개씩 배치
    for (int i = 0; i < printItems.length; i += 2) {
      final item1 = printItems[i];
      final item2 = (i + 1 < printItems.length) ? printItems[i + 1] : null;

      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 25, vertical: 15),
        build: (context) => pw.Column(children: [
          pw.Expanded(child: _buildPrintItem(item1, font, fontBold)),
          if (item2 != null) ...[
            _buildPdfPerforation(fontBold),
            pw.Expanded(child: _buildPrintItem(item2, font, fontBold)),
          ] else pw.Expanded(child: pw.SizedBox()),
        ]),
      ));
    }
    return doc.save();
  }

  pw.Widget _buildPrintItem(dynamic item, pw.Font font, pw.Font fontBold) {
    if (item['type'] == 'bracket') return _buildPdfBracketBlock(item['index'], font, fontBold);
    return _buildPdfTableMatchSheet(item['match'], item['roundName'], font, fontBold);
  }

  /// [디자인 1: 이전 기록지 - 청록색 표 형식 (2인 완결 경기용)]
  pw.Widget _buildPdfTableMatchSheet(Match m, String roundName, pw.Font font, pw.Font fontBold) {
    final headerBgColor = PdfColor.fromHex('#98D8D8'); 
    final setNumBgColor = PdfColor.fromHex('#E8F5E9');
    const double rowHeight = 32.0;
    return pw.Container(
      margin: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black, width: 1)),
      child: pw.Column(children: [
          pw.SizedBox(height: 8),
          pw.Text(widget.tournamentTitle, style: pw.TextStyle(font: fontBold, fontSize: 18)),
          pw.Text(roundName, style: pw.TextStyle(font: font, fontSize: 13)),
          pw.SizedBox(height: 8),
          pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 15),
            child: pw.Table(columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(2), 2: const pw.FlexColumnWidth(3)},
              border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
              children: [
                pw.TableRow(decoration: pw.BoxDecoration(color: headerBgColor), children: [
                    _tableHeaderCell('선수', fontBold), _tableHeaderCell('세트', fontBold), _tableHeaderCell('선수', fontBold),
                ]),
                pw.TableRow(children: [
                    pw.Container(height: rowHeight * 5, alignment: pw.Alignment.center, child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
                          pw.Text(m.player1?.name ?? 'TBD', style: pw.TextStyle(font: fontBold, fontSize: 16)),
                          pw.Text(m.player1?.affiliation ?? '', style: pw.TextStyle(font: font, fontSize: 11)),
                    ])),
                    pw.Column(children: List.generate(5, (index) => pw.Container(height: rowHeight, decoration: index < 4 ? const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.5))) : null,
                        child: pw.Row(children: [
                            pw.Expanded(child: pw.SizedBox()),
                            pw.Container(width: 25, height: rowHeight, color: setNumBgColor, alignment: pw.Alignment.center, child: pw.Text('${index + 1}', style: pw.TextStyle(font: fontBold, fontSize: 12))),
                            pw.Expanded(child: pw.SizedBox()),
                        ])))),
                    pw.Container(height: rowHeight * 5, alignment: pw.Alignment.center, child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
                          pw.Text(m.player2?.name ?? 'TBD', style: pw.TextStyle(font: fontBold, fontSize: 16)),
                          pw.Text(m.player2?.affiliation ?? '', style: pw.TextStyle(font: font, fontSize: 11)),
                    ])),
                ]),
                pw.TableRow(children: [
                    pw.Container(height: 35, alignment: pw.Alignment.center, child: pw.Text('승자 서명:', style: pw.TextStyle(font: font, fontSize: 10))),
                    pw.Container(height: 35, alignment: pw.Alignment.center, child: pw.Text('최종 스코어', style: pw.TextStyle(font: font, fontSize: 10))),
                    pw.Container(height: 35, alignment: pw.Alignment.center, child: pw.Text('승자 서명:', style: pw.TextStyle(font: font, fontSize: 10))),
                ]),
              ])),
      ]));
  }

  /// [디자인 2: 브래킷 진행 기록표 (연계 경기용 - 잘림 방지 수정)]
  pw.Widget _buildPdfBracketBlock(int blockIndex, pw.Font font, pw.Font fontBold) {
    final accentColor = PdfColor.fromHex('#E8F5E9');
    List<Match?> r1 = List.generate(4, (i) => (blockIndex * 4 + i < widget.rounds[0].matches.length) ? widget.rounds[0].matches[blockIndex * 4 + i] : null);
    List<Match?> r2 = widget.rounds.length > 1 ? List.generate(2, (i) => (blockIndex * 2 + i < widget.rounds[1].matches.length) ? widget.rounds[1].matches[blockIndex * 2 + i] : null) : [];
    Match? r3 = (widget.rounds.length > 2 && blockIndex < widget.rounds[2].matches.length) ? widget.rounds[2].matches[blockIndex] : null;

    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black, width: 0.5)),
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Column(children: [
        pw.Text(widget.tournamentTitle, style: pw.TextStyle(font: fontBold, fontSize: 15)),
        pw.Text('${widget.rounds[0].name} 진행 기록표', style: pw.TextStyle(font: font, fontSize: 10)),
        pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 2), child: pw.Divider(color: PdfColors.black, thickness: 0.5)),
        
        pw.Expanded(child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10),
          child: pw.Stack(children: [
            pw.Positioned.fill(child: _buildPdfBracketLines()), // 배경 ㄷ자 선
            for (int i = 0; i < 4; i++) _buildBracketMatchBox(i * 56.0, 0, r1[i], font, fontBold, accentColor),
            for (int i = 0; i < 2; i++) _buildBracketMatchBox(28 + (i * 112.0), 250, r2.length > i ? r2[i] : null, font, fontBold, PdfColor.fromHex('#98D8D8'), label: '승자'),
            _buildBracketMatchBox(84, 500, r3, font, fontBold, PdfColors.yellow100, label: '최종 승자'),
          ]),
        )),
      ]),
    );
  }

  pw.Widget _buildBracketMatchBox(double top, double left, Match? m, pw.Font font, pw.Font fontBold, PdfColor color, {String? label}) {
    return pw.Positioned(
      top: top, left: left,
      child: pw.Container(
        width: 190, height: 42,
        decoration: pw.BoxDecoration(color: PdfColors.white, border: pw.Border.all(color: PdfColors.black, width: 0.8)),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center, crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(m?.player1?.name ?? (label != null ? '$label 1' : '이름: _______'), style: pw.TextStyle(font: fontBold, fontSize: 8), overflow: pw.TextOverflow.clip),
              pw.Divider(height: 2, thickness: 0.1),
              pw.Text(m?.player2?.name ?? (label != null ? '$label 2' : '이름: _______'), style: pw.TextStyle(font: fontBold, fontSize: 8), overflow: pw.TextOverflow.clip),
            ],
          ))),
          pw.Container(width: 30, decoration: pw.BoxDecoration(color: color, border: pw.Border(left: pw.BorderSide(color: PdfColors.black, width: 0.8))),
            child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
              pw.Text('점수', style: pw.TextStyle(font: font, fontSize: 6)),
              pw.Text('점수', style: pw.TextStyle(font: font, fontSize: 6)),
            ]),
          )
        ]),
      ),
    );
  }

  pw.Widget _buildPdfBracketLines() {
    return pw.CustomPaint(painter: (PdfGraphics canvas, PdfPoint size) {
      canvas.setStrokeColor(PdfColors.black); canvas.setLineWidth(0.8);
      for (int i = 0; i < 2; i++) {
        double x1 = 190, xMid = 220, x2 = 250;
        double yTop = size.y - (21 + i * 112), yBottom = size.y - (77 + i * 112), yMid = size.y - (49 + i * 112);
        canvas.moveTo(x1, yTop); canvas.lineTo(xMid, yTop);
        canvas.moveTo(x1, yBottom); canvas.lineTo(xMid, yBottom);
        canvas.moveTo(xMid, yTop); canvas.lineTo(xMid, yBottom);
        canvas.moveTo(xMid, yMid); canvas.lineTo(x2, yMid);
      }
      double rx1 = 440, rxMid = 470, rx2 = 500;
      double ryTop = size.y - 49, ryBottom = size.y - 161, ryMid = size.y - 105;
      canvas.moveTo(rx1, ryTop); canvas.lineTo(rxMid, ryTop);
      canvas.moveTo(rx1, ryBottom); canvas.lineTo(rxMid, ryBottom);
      canvas.moveTo(rxMid, ryTop); canvas.lineTo(rxMid, ryBottom);
      canvas.moveTo(rxMid, ryMid); canvas.lineTo(rx2, ryMid);
      canvas.strokePath();
    });
  }

  pw.Widget _tableHeaderCell(String text, pw.Font font) => pw.Container(height: 25, alignment: pw.Alignment.center, child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: 14)));

  pw.Widget _buildPdfPerforation(pw.Font font) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 5),
    child: pw.Row(children: [
      pw.Expanded(child: pw.Divider(color: PdfColors.red, borderStyle: pw.BorderStyle.dashed, thickness: 1)),
      pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 10), child: pw.Text('✂ 절취선 ✂', style: pw.TextStyle(font: font, color: PdfColors.red, fontSize: 10, fontWeight: pw.FontWeight.bold))),
      pw.Expanded(child: pw.Divider(color: PdfColors.red, borderStyle: pw.BorderStyle.dashed, thickness: 1)),
    ]),
  );
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
