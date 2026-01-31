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

    // 1. 예선 오다지 (조별 리그 테이블) - 한 페이지에 3개씩
    for (int i = 0; i < groups.length; i += 3) {
      final g1 = groups[i];
      final g2 = (i + 1 < groups.length) ? groups[i + 1] : null;
      final g3 = (i + 2 < groups.length) ? groups[i + 2] : null;

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          build: (pw.Context context) {
            return pw.Column(
              children: [
                _buildPdfGroupTable(g1, font, fontBold),
                if (g2 != null) ...[
                  pw.SizedBox(height: 10),
                  pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.5),
                  pw.SizedBox(height: 10),
                  _buildPdfGroupTable(g2, font, fontBold),
                ],
                if (g3 != null) ...[
                  pw.SizedBox(height: 10),
                  pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.5),
                  pw.SizedBox(height: 10),
                  _buildPdfGroupTable(g3, font, fontBold),
                ]
              ],
            );
          },
        ),
      );
    }

    // 2. 본선 오다지 페이지 추가
    if (knockoutRounds != null && knockoutRounds!.isNotEmpty) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              pw.Center(child: pw.Text('본선 토너먼트 기록지', style: pw.TextStyle(font: fontBold, fontSize: 24))),
              pw.SizedBox(height: 20),
              for (var round in knockoutRounds!) ...[
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 10),
                  child: pw.Text('[${round.name}]', style: pw.TextStyle(font: fontBold, fontSize: 16, color: PdfColors.blue900)),
                ),
                pw.TableHelper.fromTextArray(
                  context: context,
                  cellStyle: pw.TextStyle(font: font, fontSize: 10),
                  headerStyle: pw.TextStyle(font: fontBold, fontSize: 10),
                  data: <List<String>>[
                    <String>['경기', '선수 1', '점수', '선수 2', '승자'],
                    ...round.matches.asMap().entries.map((e) => [
                      '${e.key + 1}',
                      e.value.player1?.name ?? 'TBD',
                      '',
                      e.value.player2?.name ?? 'TBD',
                      ''
                    ])
                  ],
                ),
                pw.SizedBox(height: 10),
              ]
            ];
          },
        ),
      );
    }

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
  }

  pw.Widget _buildPdfGroupTable(Group group, pw.Font font, pw.Font fontBold) {
    final players = group.players;
    
    return pw.Container(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('$tournamentTitle 예선전', style: pw.TextStyle(font: fontBold, fontSize: 13)),
              pw.Text(group.name, style: pw.TextStyle(font: fontBold, fontSize: 18)),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(2.2), // Name Column
              for (int i = 0; i < players.length; i++) i + 1: const pw.FlexColumnWidth(2),
              players.length + 1: const pw.FlexColumnWidth(0.8), // WL
              players.length + 2: const pw.FlexColumnWidth(0.8), // GL
              players.length + 3: const pw.FlexColumnWidth(0.7), // R
            },
            children: [
              // Header Row
              pw.TableRow(
                children: [
                  _pdfCell(group.name, fontBold, center: true, bgColor: PdfColors.grey100, fontSize: 9),
                  ...players.map((p) => _pdfCell('${p.name}\n${p.affiliation}', fontBold, center: true, fontSize: 8, bgColor: PdfColors.grey100)),
                  _pdfCell('WL', fontBold, center: true, bgColor: PdfColors.grey100, fontSize: 9),
                  _pdfCell('GL', fontBold, center: true, bgColor: PdfColors.grey100, fontSize: 9),
                  _pdfCell('R', fontBold, center: true, textColor: PdfColors.white, bgColor: PdfColors.orange, fontSize: 9),
                ],
              ),
              // Player Rows
              ...players.asMap().entries.map((entry) {
                int rowIndex = entry.key;
                Player pRow = entry.value;
                return pw.TableRow(
                  children: [
                    _pdfCell(pRow.name, fontBold, center: true, textColor: PdfColors.blue800, fontSize: 9), // 텍스트 가운데 정렬
                    ...players.asMap().entries.map((colEntry) {
                      int colIndex = colEntry.key;
                      Player pCol = colEntry.value;
                      if (rowIndex == colIndex) {
                        return pw.Container(
                          color: PdfColors.grey300, 
                          constraints: const pw.BoxConstraints(minHeight: 25)
                        );
                      }
                      
                      final match = group.matches.firstWhereOrNull((m) => 
                        (m.player1?.id == pRow.id && m.player2?.id == pCol.id) ||
                        (m.player1?.id == pCol.id && m.player2?.id == pRow.id)
                      );
                      String score = '';
                      if (match != null && match.status == MatchStatus.completed) {
                        score = (match.player1?.id == pRow.id) ? '${match.score1}' : '${match.score2}';
                      }
                      
                      return _pdfCell(score, font, center: true, fontSize: 12); // 점수 가운데 정렬
                    }),
                    _pdfCell('', font, center: true),
                    _pdfCell('', font, center: true),
                    _pdfCell('', font, center: true, bgColor: PdfColors.orange100),
                  ],
                );
              }),
            ],
          ),
          pw.SizedBox(height: 5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('확인: ________________ (서명)', style: pw.TextStyle(font: font, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfCell(String text, pw.Font font, {bool center = false, double fontSize = 10, PdfColor? textColor, PdfColor? bgColor}) {
    return pw.Container(
      alignment: center ? pw.Alignment.center : pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      color: bgColor,
      constraints: const pw.BoxConstraints(minHeight: 25),
      child: pw.Text(text, 
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
        style: pw.TextStyle(font: font, fontSize: fontSize, color: textColor ?? PdfColors.black)
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('진행 기록지 (오다지)'),
          actions: [
            IconButton(
              icon: const Icon(Icons.print, color: Colors.blue),
              onPressed: _printDocument,
              tooltip: '기록지 출력/PDF 저장',
            ),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: '예선전'), Tab(text: '본선')],
          ),
        ),
        body: TabBarView(
          children: [
            _buildGroupView(),
            _buildKnockoutView(),
          ],
        ),
      ),
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
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$tournamentTitle 예선전', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(group.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Table(
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    border: TableBorder.all(color: Colors.grey.shade300),
                    columnWidths: {
                      0: const FixedColumnWidth(100),
                      for (int i = 0; i < players.length; i++) i + 1: const FixedColumnWidth(80),
                      players.length + 1: const FixedColumnWidth(40),
                      players.length + 2: const FixedColumnWidth(40),
                      players.length + 3: const FixedColumnWidth(40),
                    },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: Colors.grey.shade100),
                        children: [
                          _uiCell(group.name, isBold: true, center: true),
                          ...players.map((p) => _uiCell('${p.name}\n${p.affiliation}', isBold: true, center: true, fontSize: 10)),
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
                            _uiCell(pRow.name, isBold: true, center: true, textColor: Colors.blue),
                            ...players.asMap().entries.map((colEntry) {
                              int colIndex = colEntry.key;
                              Player pCol = colEntry.value;
                              if (rowIndex == colIndex) return Container(color: Colors.grey.shade200, height: 40);
                              
                              final match = group.matches.firstWhereOrNull((m) => 
                                (m.player1?.id == pRow.id && m.player2?.id == pCol.id) ||
                                (m.player1?.id == pCol.id && m.player2?.id == pRow.id)
                              );
                              String score = '';
                              if (match != null && match.status == MatchStatus.completed) {
                                score = (match.player1?.id == pRow.id) ? '${match.score1}' : '${match.score2}';
                              }
                              return _uiCell(score, center: true, fontSize: 16);
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

  Widget _uiCell(String text, {bool isBold = false, bool center = false, double fontSize = 12, Color? textColor, Color? bgColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
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

  Widget _buildKnockoutView() {
    if (knockoutRounds == null) return const Center(child: Text('본선이 생성되지 않았습니다.'));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: knockoutRounds!.length,
      itemBuilder: (context, index) {
        final round = knockoutRounds![index];
        return Column(
          children: [
            Text(round.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ...round.matches.map((m) => ListTile(
              title: Text('${m.player1?.name ?? "TBD"} VS ${m.player2?.name ?? "TBD"}'),
              subtitle: const Text('결과 기입란: _________'),
            )),
            const Divider(),
          ],
        );
      },
    );
  }
}
