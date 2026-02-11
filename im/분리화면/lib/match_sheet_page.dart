import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:collection/collection.dart';
import 'models.dart';

class MatchSheetPage extends StatelessWidget {
  final String tournamentTitle;
  final List<Group> groups;
  final List<Round>? knockoutRounds;

  const MatchSheetPage({super.key, required this.tournamentTitle, required this.groups, this.knockoutRounds});

  Future<void> _printDocument() async {
    final doc = pw.Document();
    
    final font = await PdfGoogleFonts.nanumGothicRegular();
    final fontBold = await PdfGoogleFonts.nanumGothicBold();

    // 예선 오다지 (조별 리그 테이블) - 한 페이지에 정확히 2개씩 (절반씩)
    for (int i = 0; i < groups.length; i += 2) {
      final g1 = groups[i];
      final g2 = (i + 1 < groups.length) ? groups[i + 1] : null;

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(0), 
          build: (pw.Context context) {
            return pw.Column(
              children: [
                // 첫 번째 조 (상단 절반)
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.fromLTRB(40, 40, 40, 20),
                    child: _buildPdfGroupTable(g1, font, fontBold),
                  ),
                ),
                // 중간 절취선
                if (g2 != null) pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 1, color: PdfColors.grey400),
                
                // 두 번째 조 (하단 절반)
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.fromLTRB(40, 20, 40, 40),
                    child: g2 != null 
                      ? _buildPdfGroupTable(g2, font, fontBold)
                      : pw.SizedBox(),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
  }

  pw.Widget _buildPdfGroupTable(Group group, pw.Font font, pw.Font fontBold) {
    final players = group.players;
    
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('$tournamentTitle 예선전', style: pw.TextStyle(font: fontBold, fontSize: 14)),
            pw.Text(group.name, style: pw.TextStyle(font: fontBold, fontSize: 22, color: PdfColors.blue900)),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.8),
          columnWidths: {
            0: const pw.FlexColumnWidth(2.5),
            for (int i = 0; i < players.length; i++) i + 1: const pw.FlexColumnWidth(2),
            players.length + 1: const pw.FlexColumnWidth(1.0),
            players.length + 2: const pw.FlexColumnWidth(1.0),
            players.length + 3: const pw.FlexColumnWidth(0.8),
          },
          children: [
            pw.TableRow(
              children: [
                _pdfCell(group.name, fontBold, center: true, bgColor: PdfColors.grey200, fontSize: 11),
                ...players.map((p) => pw.Container(
                  alignment: pw.Alignment.center,
                  padding: const pw.EdgeInsets.symmetric(vertical: 6),
                  color: PdfColors.grey200,
                  child: pw.Column(
                    children: [
                      pw.Text(p.affiliation, style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.blue800)),
                      pw.Text(p.name, style: pw.TextStyle(font: font, fontSize: 9)),
                    ],
                  ),
                )),
                _pdfCell('WL', fontBold, center: true, bgColor: PdfColors.grey200, fontSize: 11),
                _pdfCell('GL', fontBold, center: true, bgColor: PdfColors.grey200, fontSize: 11),
                _pdfCell('R', fontBold, center: true, textColor: PdfColors.white, bgColor: PdfColors.orange700, fontSize: 11),
              ],
            ),
            ...players.asMap().entries.map((entry) {
              int rowIndex = entry.key;
              Player pRow = entry.value;
              return pw.TableRow(
                children: [
                  pw.Container(
                    alignment: pw.Alignment.center,
                    padding: const pw.EdgeInsets.symmetric(vertical: 8),
                    child: pw.Column(
                      children: [
                        pw.Text(pRow.affiliation, style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.blue800)),
                        pw.Text(pRow.name, style: pw.TextStyle(font: font, fontSize: 10)),
                      ],
                    ),
                  ),
                  ...players.asMap().entries.map((colEntry) {
                    int colIndex = colEntry.key;
                    if (rowIndex == colIndex) {
                      return pw.Container(color: PdfColors.grey300, constraints: const pw.BoxConstraints(minHeight: 45));
                    }
                    return _pdfCell('', font, center: true, fontSize: 16);
                  }),
                  _pdfCell('', font, center: true),
                  _pdfCell('', font, center: true),
                  _pdfCell('', font, center: true, bgColor: PdfColors.orange100),
                ],
              );
            }),
          ],
        ),
        pw.SizedBox(height: 15),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text('경기 확인 및 서명: ________________________', style: pw.TextStyle(font: font, fontSize: 12)),
          ],
        ),
      ],
    );
  }

  pw.Widget _pdfCell(String text, pw.Font font, {bool center = false, double fontSize = 10, PdfColor? textColor, PdfColor? bgColor}) {
    return pw.Container(
      alignment: center ? pw.Alignment.center : pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      color: bgColor,
      constraints: const pw.BoxConstraints(minHeight: 40),
      child: pw.Text(text, 
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
        style: pw.TextStyle(font: font, fontSize: fontSize, color: textColor ?? PdfColors.black)
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('예선 진행 기록지 (오다지)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print, color: Colors.blue, size: 28),
            onPressed: _printDocument,
            tooltip: '기록지 출력/PDF 저장',
          ),
        ],
      ),
      body: _buildGroupView(),
    );
  }

  Widget _buildGroupView() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final players = group.players;
        return Card(
          margin: const EdgeInsets.only(bottom: 24),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$tournamentTitle', style: const TextStyle(fontSize: 14, color: Colors.blueGrey)),
                    Text(group.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF1A535C))),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Table(
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    border: TableBorder.all(color: Colors.grey.shade400, width: 1),
                    columnWidths: {
                      0: const FixedColumnWidth(130),
                      for (int i = 0; i < players.length; i++) i + 1: const FixedColumnWidth(100),
                      players.length + 1: const FixedColumnWidth(50),
                      players.length + 2: const FixedColumnWidth(50),
                      players.length + 3: const FixedColumnWidth(50),
                    },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: Colors.grey.shade200),
                        children: [
                          _uiCell(group.name, isBold: true, center: true, fontSize: 14),
                          ...players.map((p) => Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Column(
                              children: [
                                Text(p.affiliation, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue)),
                                Text(p.name, style: const TextStyle(fontSize: 11)),
                              ],
                            ),
                          )),
                          _uiCell('WL', isBold: true, center: true),
                          _uiCell('GL', isBold: true, center: true),
                          _uiCell('R', isBold: true, center: true, textColor: Colors.white, bgColor: Colors.orange),
                        ],
                      ),
                      ...players.asMap().entries.map((entry) {
                        int rowIndex = entry.key;
                        Player pRow = entry.value;
                        return TableRow(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Column(
                                children: [
                                  Text(pRow.affiliation, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue)),
                                  Text(pRow.name, style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                            ...players.asMap().entries.map((colEntry) {
                              int colIndex = colEntry.key;
                              if (rowIndex == colIndex) return Container(color: Colors.grey.shade300, height: 60);
                              return _uiCell('', center: true, fontSize: 20);
                            }),
                            _uiCell('', center: true), _uiCell('', center: true), _uiCell('', center: true, bgColor: Colors.orange.withOpacity(0.1)),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _uiCell(String text, {bool isBold = false, bool center = false, double fontSize = 14, Color? textColor, Color? bgColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      alignment: center ? Alignment.center : Alignment.centerLeft,
      color: bgColor,
      child: Text(text, 
        textAlign: center ? TextAlign.center : TextAlign.left,
        style: TextStyle(
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontSize: fontSize,
          color: textColor,
        )
      ),
    );
  }
}
