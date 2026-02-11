import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'models.dart';

class MatchSheetPage extends StatelessWidget {
  final String tournamentTitle;
  final List<Group> groups;
  final List<Round>? knockoutRounds;

  const MatchSheetPage({
    super.key,
    required this.tournamentTitle,
    required this.groups,
    this.knockoutRounds,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('예선 기록지 인쇄 미리보기'),
        backgroundColor: const Color(0xFF1A535C),
        foregroundColor: Colors.white,
      ),
      body: PdfPreview(
        build: (format) => _generatePdf(format),
        initialPageFormat: PdfPageFormat.a4,
        pdfFileName: 'group_stage_sheets.pdf',
        canChangePageFormat: false,
        allowPrinting: true,
        allowSharing: true,
        loadingWidget: const Center(child: CircularProgressIndicator()),
        onError: (context, error) => Center(child: Text('PDF 생성 오류: $error')),
      ),
    );
  }

  Future<Uint8List> _generatePdf(PdfPageFormat format) async {
    final doc = pw.Document();
    
    pw.Font font;
    pw.Font fontBold;
    try {
      font = await PdfGoogleFonts.nanumGothicRegular();
      fontBold = await PdfGoogleFonts.nanumGothicBold();
    } catch (e) {
      font = pw.Font.helvetica();
      fontBold = pw.Font.helveticaBold();
    }

    const double a4Width = 595.28;
    const double a4Height = 841.89;
    const double halfHeight = a4Height / 2;

    for (int i = 0; i < groups.length; i += 2) {
      final g1 = groups[i];
      final g2 = (i + 1 < groups.length) ? groups[i + 1] : null;

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(0),
          build: (pw.Context context) {
            return pw.Stack(
              children: [
                ..._buildAbsoluteGroupSheet(g1, 0, a4Width, halfHeight, font, fontBold),
                if (g2 != null) ...[
                  pw.Positioned(
                    top: halfHeight,
                    left: 20, right: 20,
                    child: pw.Container(
                      height: 1,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5, style: pw.BorderStyle.dashed))
                      ),
                    ),
                  ),
                  ..._buildAbsoluteGroupSheet(g2, halfHeight, a4Width, halfHeight, font, fontBold),
                ],
              ],
            );
          },
        ),
      );
    }
    return doc.save();
  }

  List<pw.Widget> _buildAbsoluteGroupSheet(
      Group group, double offsetY, double pageWidth, double pageHeight, pw.Font font, pw.Font fontBold) {
    final List<pw.Widget> widgets = [];
    final players = group.players;

    const double startX = 45.0;
    final double endX = pageWidth - 45.0;
    final double contentWidth = endX - startX;
    
    // 타이틀 박스
    const double titleBoxTop = 40.0;
    const double titleBoxHeight = 40.0;

    // 대진표 박스 (타이틀 아래 5mm = 14.17pt 여백)
    const double gap5mm = 14.17;
    final double tableBoxTop = titleBoxTop + titleBoxHeight + gap5mm;
    const double col1Width = 140.0; // 왼쪽 열 너비
    const double resultAreaWidth = 135.0; // 45 * 3
    
    // 단체전 선수명 3줄 대응을 위해 행 높이 설정
    double rowHeight = 60.0;
    if (players.length > 5) rowHeight = 50.0;
    
    final double tableHeight = (players.length + 1) * rowHeight;
    final double playerAreaWidth = contentWidth - col1Width - resultAreaWidth;
    final double playerColWidth = players.isNotEmpty ? (playerAreaWidth / players.length) : playerAreaWidth;

    // 1. 타이틀 박스 디자인 (이중 테두리 적용)
    widgets.add(pw.Positioned(
      top: offsetY + titleBoxTop,
      left: startX,
      child: pw.Container(
        width: contentWidth,
        height: titleBoxHeight,
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
        padding: const pw.EdgeInsets.symmetric(horizontal: 15),
        alignment: pw.Alignment.centerLeft,
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(tournamentTitle, style: pw.TextStyle(font: fontBold, fontSize: 11)),
            pw.Text(group.name, style: pw.TextStyle(font: fontBold, fontSize: 18)),
          ],
        ),
      ),
    ));
    // 타이틀 외곽 이중선
    widgets.add(pw.Positioned(
      top: offsetY + titleBoxTop - 1.5,
      left: startX - 1.5,
      child: pw.Container(width: contentWidth + 3.0, height: titleBoxHeight + 3.0, decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)))),
    );

    // 2. 대진표 헤더 (상단 가로 행)
    widgets.add(pw.Positioned(
      top: offsetY + tableBoxTop,
      left: startX,
      child: _tableCell(group.name, col1Width, rowHeight, fontBold, fontSize: 15, isHeader: true),
    ));

    for (int j = 0; j < players.length; j++) {
      // 상단 헤더: 클럽명만 표시 (선수이름 생략)
      widgets.add(pw.Positioned(
        top: offsetY + tableBoxTop,
        left: startX + col1Width + (j * playerColWidth),
        child: pw.Container(
          width: playerColWidth,
          height: rowHeight,
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5), color: PdfColors.grey100),
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(horizontal: 2),
          child: pw.Text(players[j].affiliation, style: pw.TextStyle(font: fontBold, fontSize: 10), textAlign: pw.TextAlign.center),
        ),
      ));
    }

    final labels = ['승패', '득실', '순위'];
    for (int l = 0; l < 3; l++) {
      widgets.add(pw.Positioned(
        top: offsetY + tableBoxTop,
        left: endX - resultAreaWidth + (l * 45.0),
        child: _tableCell(labels[l], 45.0, rowHeight, fontBold, fontSize: 11, isHeader: true),
      ));
    }

    // 3. 데이터 행 (왼쪽 선수 정보 및 점수칸)
    for (int i = 0; i < players.length; i++) {
      double rowY = offsetY + tableBoxTop + ((i + 1) * rowHeight);

      // 왼쪽 선수 정보 셀 (소속 + 선수명 한줄에 2명씩 3줄)
      widgets.add(pw.Positioned(
        top: rowY,
        left: startX,
        child: _teamPlayerCell(players[i], col1Width, rowHeight, font, fontBold),
      ));

      for (int j = 0; j < players.length; j++) {
        widgets.add(pw.Positioned(
          top: rowY,
          left: startX + col1Width + (j * playerColWidth),
          child: pw.Container(
            width: playerColWidth,
            height: rowHeight,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 0.5),
              color: i == j ? PdfColors.grey300 : null,
            ),
          ),
        ));
      }

      for (int l = 0; l < 3; l++) {
        widgets.add(pw.Positioned(
          top: rowY,
          left: endX - resultAreaWidth + (l * 45.0),
          child: pw.Container(width: 45.0, height: rowHeight, decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5))),
        ));
      }
    }

    // 대진표 외곽 이중선
    widgets.add(pw.Positioned(
      top: offsetY + tableBoxTop - 1.5,
      left: startX - 1.5,
      child: pw.Container(width: contentWidth + 3.0, height: tableHeight + 3.0, decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)))),
    );

    // 4. 하단 서명란
    widgets.add(pw.Positioned(
      top: offsetY + tableBoxTop + tableHeight + 20.0,
      right: startX,
      child: pw.Text('경기 확인 및 서명: ________________________', style: pw.TextStyle(font: fontBold, fontSize: 12)),
    ));

    return widgets;
  }

  pw.Widget _tableCell(String text, double w, double h, pw.Font font, {double fontSize = 10, bool isHeader = false}) {
    return pw.Container(
      width: w, height: h,
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5), color: isHeader ? PdfColors.grey100 : null),
      alignment: pw.Alignment.center,
      child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: fontSize)),
    );
  }

  pw.Widget _teamPlayerCell(Player p, double w, double h, pw.Font font, pw.Font fontBold) {
    List<String> playerNames = p.name.split(',').map((e) => e.trim()).toList();
    List<pw.Widget> nameRows = [];

    // 소속과 선수명 폰트 크기를 9pt로 통일
    const double fontSize = 9.0;

    for (int i = 0; i < playerNames.length && i < 6; i += 2) {
      String line = playerNames[i];
      if (i + 1 < playerNames.length) line += ", ${playerNames[i+1]}";
      nameRows.add(pw.Text(line, style: pw.TextStyle(font: font, fontSize: fontSize), maxLines: 1));
    }

    return pw.Container(
      width: w, height: h,
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(p.affiliation, style: pw.TextStyle(font: fontBold, fontSize: fontSize), maxLines: 1),
          if (nameRows.isNotEmpty) pw.SizedBox(height: 1),
          ...nameRows,
        ],
      ),
    );
  }
}
