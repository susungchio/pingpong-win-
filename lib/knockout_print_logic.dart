import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' show BuildContext, Scaffold, AppBar, Text, Navigator, MaterialPageRoute, VoidCallback;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart';
import 'models.dart';

class KnockoutPrintLogic {
  static Future<void> showPrintPreview(
    BuildContext context,
    String tournamentTitle,
    List<Round> rounds,
    Set<String> selectedMatchIds,
    VoidCallback onPrinted,
  ) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('경기 기록지 인쇄 미리보기')),
          body: PdfPreview(
            build: (format) {
              for (var round in rounds) {
                for (var m in round.matches) {
                  if (selectedMatchIds.contains(m.id)) {
                    m.printCount++;
                  }
                }
              }
              onPrinted();
              return _generatePdf(format, tournamentTitle, rounds, selectedMatchIds);
            },
            allowPrinting: true,
            allowSharing: true,
            initialPageFormat: PdfPageFormat.a4.portrait,
            pdfFileName: 'match_sheets.pdf',
            canChangePageFormat: false,
          ),
        ),
      ),
    );
  }

  static Future<Uint8List> _generatePdf(
    PdfPageFormat format,
    String tournamentTitle,
    List<Round> rounds,
    Set<String> selectedMatchIds,
  ) async {
    final doc = pw.Document();

    // --- 폰트 로드 로직 수정 (오프라인 대응) ---
    final exePath = File(Platform.resolvedExecutable).parent.path;
    final fontPath = join(exePath, 'fonts', 'NanumGothic.ttf');
    final fontBoldPath = join(exePath, 'fonts', 'NanumGothic-Bold.ttf');

    pw.Font font;
    pw.Font fontBold;

    // 로컬 fonts 폴더에 파일이 있으면 사용, 없으면 구글 폰트(온라인) 사용
    if (await File(fontPath).exists()) {
      final fontData = await File(fontPath).readAsBytes();
      font = pw.Font.ttf(fontData.buffer.asByteData());
    } else {
      font = await PdfGoogleFonts.nanumGothicRegular();
    }

    if (await File(fontBoldPath).exists()) {
      final fontData = await File(fontBoldPath).readAsBytes();
      fontBold = pw.Font.ttf(fontData.buffer.asByteData());
    } else {
      fontBold = await PdfGoogleFonts.nanumGothicBold();
    }

    final iconFont = await PdfGoogleFonts.materialIcons();

    List<Map<String, dynamic>> standardTasks = [];
    List<Map<String, dynamic>> bracketTasks = [];

    for (int r = 0; r < rounds.length; r++) {
      for (var m in rounds[r].matches) {
        if (selectedMatchIds.contains(m.id)) {
          bool parentWillIncludeMe = false;
          if (m.nextMatchId != null && selectedMatchIds.contains(m.nextMatchId)) {
            try {
              final parentMatch = rounds[r + 1].matches.firstWhere((pm) => pm.id == m.nextMatchId);
              bool parentBothPlayersKnown = parentMatch.player1 != null && parentMatch.player2 != null;
              if (!parentBothPlayersKnown) {
                parentWillIncludeMe = true;
              }
            } catch (_) {}
          }
          
          if (!parentWillIncludeMe) {
            final task = {'match': m, 'roundIdx': r, 'roundName': rounds[r].name};
            bool bothPlayersKnown = m.player1 != null && m.player2 != null;
            if (r == 0 || bothPlayersKnown) {
              standardTasks.add(task);
            } else {
              bracketTasks.add(task);
            }
          }
        }
      }
    }

    for (int i = 0; i < standardTasks.length; i += 2) {
      final t1 = standardTasks[i];
      final t2 = (i + 1 < standardTasks.length) ? standardTasks[i + 1] : null;

      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 25),
        build: (context) => pw.Column(children: [
          _buildStandardSheet(t1['match'], t1['roundName'], tournamentTitle, font, fontBold),
          if (t2 != null) ...[
            _buildCuttingLine(iconFont),
            _buildStandardSheet(t2['match'], t2['roundName'], tournamentTitle, font, fontBold),
          ],
        ]),
      ));
    }

    for (int i = 0; i < bracketTasks.length; i += 2) {
      final t1 = bracketTasks[i];
      final t2 = (i + 1 < bracketTasks.length) ? bracketTasks[i + 1] : null;

      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 15, vertical: 25),
        build: (context) => pw.Column(children: [
          pw.Expanded(child: _buildBracketSection(t1['match'], t1['roundIdx'], rounds, tournamentTitle, font, fontBold)),
          _buildCuttingLine(iconFont),
          if (t2 != null)
            pw.Expanded(child: _buildBracketSection(t2['match'], t2['roundIdx'], rounds, tournamentTitle, font, fontBold))
          else
            pw.Spacer(),
        ]),
      ));
    }
    
    return doc.save();
  }

  static pw.Widget _buildStandardSheet(Match m, String rName, String title, pw.Font font, pw.Font fontBold) {
    const double rowH = 38.0;
    final cyanColor = PdfColor.fromHex('#B3E5FC');

    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
      child: pw.Column(children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Column(children: [
            pw.Text(title, style: pw.TextStyle(font: fontBold, fontSize: 16)),
            pw.SizedBox(height: 2),
            pw.Text(rName, style: pw.TextStyle(font: font, fontSize: 12)),
          ]),
        ),
        pw.Table(
          border: pw.TableBorder.all(),
          columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FixedColumnWidth(100), 2: const pw.FlexColumnWidth(2)},
          children: [
            pw.TableRow(decoration: pw.BoxDecoration(color: cyanColor), children: [
              _cell('선 수', fontBold, 22), _cell('세 트', fontBold, 22), _cell('선 수', fontBold, 22),
            ]),
            pw.TableRow(children: [
              _playerBox(m.player1, font, fontBold, rowH * 5),
              pw.Column(children: List.generate(5, (i) => _setRow(i + 1, fontBold, rowH))),
              _playerBox(m.player2, font, fontBold, rowH * 5),
            ]),
            pw.TableRow(children: [
              pw.Container(height: 40, decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5))),
              pw.Container(height: 40, decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5))),
              pw.Container(height: 40, decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5))),
            ]),
          ],
        ),
      ]),
    );
  }

  static pw.Widget _buildBracketSection(Match headMatch, int rIdx, List<Round> rounds, String title, pw.Font font, pw.Font fontBold) {
    List<Match> children = rounds[rIdx - 1].matches.where((m) => m.nextMatchId == headMatch.id).toList();
    Match? leftMatch = children.isNotEmpty ? children[0] : null;
    Match? rightMatch = children.length > 1 ? children[1] : null;

    return pw.Column(children: [
      pw.SizedBox(height: 5),
      pw.Text(title, style: pw.TextStyle(font: fontBold, fontSize: 22, letterSpacing: 1.5)),
      pw.SizedBox(height: 25),
      _tournamentBox(title: '진출선수', subtitle: '', font: font, fontBold: fontBold),
      _buildBracketLine(label: '${rounds[rIdx].name}전', width: 340, font: font),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _buildBracketColumn(leftMatch, rounds[rIdx-1].name, PdfColor.fromHex('#D9DCFC'), font, fontBold),
          pw.SizedBox(width: 30),
          _buildBracketColumn(rightMatch, rounds[rIdx-1].name, PdfColor.fromHex('#F7DCE2'), font, fontBold),
        ],
      ),
    ]);
  }

  static pw.Widget _buildBracketColumn(Match? m, String label, PdfColor scoreColor, pw.Font font, pw.Font fontBold) {
    return pw.Column(children: [
      _tournamentBox(
        title: m?.winner?.name ?? 'TBD',
        subtitle: m?.winner?.affiliation ?? '',
        showScore: true,
        scoreColor: scoreColor,
        font: font,
        fontBold: fontBold,
      ),
      _buildBracketLine(label: '${label}전', width: 140, font: font),
      pw.Row(children: [
        _tournamentBox(title: m?.player1?.name ?? 'TBD', subtitle: m?.player1?.affiliation ?? '', showScore: true, scoreColor: scoreColor, font: font, fontBold: fontBold),
        pw.SizedBox(width: 10),
        _tournamentBox(title: m?.player2?.name ?? 'TBD', subtitle: m?.player2?.affiliation ?? '', showScore: true, scoreColor: scoreColor, font: font, fontBold: fontBold),
      ]),
    ]);
  }

  static pw.Widget _tournamentBox({required String title, required String subtitle, bool showScore = false, PdfColor? scoreColor, required pw.Font font, required pw.Font fontBold}) {
    return pw.Container(
      width: 110,
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
      child: pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Column(children: [
            pw.Text(title, style: pw.TextStyle(font: fontBold, fontSize: 13), overflow: pw.TextOverflow.clip),
            if (subtitle.isNotEmpty) pw.Text(subtitle, style: pw.TextStyle(font: font, fontSize: 9), overflow: pw.TextOverflow.clip)
            else if (!showScore) pw.SizedBox(height: 10),
          ]),
        ),
        pw.Divider(height: 1, thickness: 0.8),
        if (showScore)
          pw.Container(
            height: 24,
            child: pw.Row(children: [
              pw.Expanded(child: pw.Container(color: scoreColor, alignment: pw.Alignment.center, child: pw.Text('세트승수', style: pw.TextStyle(font: fontBold, fontSize: 9)))),
              pw.VerticalDivider(width: 1, thickness: 0.8),
              pw.Expanded(child: pw.SizedBox()),
            ]),
          )
        else pw.SizedBox(height: 24),
      ]),
    );
  }

  static pw.Widget _buildBracketLine({required String label, required double width, required pw.Font font}) {
    return pw.Column(children: [
      pw.Container(width: 1, height: 8, color: PdfColors.black),
      pw.Text(label, style: pw.TextStyle(font: font, fontSize: 10)),
      pw.Container(width: 1, height: 10, color: PdfColors.black),
      pw.Container(
        width: width,
        height: 15,
        decoration: pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(width: 0.8),
            left: pw.BorderSide(width: 0.8),
            right: pw.BorderSide(width: 0.8),
          ),
        ),
      ),
    ]);
  }

  static pw.Widget _buildCuttingLine(pw.Font iconFont) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 15),
      child: pw.Row(children: [
        pw.Text(String.fromCharCode(0xe14e), style: pw.TextStyle(font: iconFont, fontSize: 22, color: PdfColors.red)),
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5),
            child: pw.Divider(height: 1, thickness: 1, borderStyle: pw.BorderStyle.dashed, color: PdfColors.grey400),
          ),
        ),
        pw.Text(String.fromCharCode(0xe14e), style: pw.TextStyle(font: iconFont, fontSize: 22, color: PdfColors.red)),
      ]),
    );
  }

  static pw.Widget _cell(String t, pw.Font f, double h) => pw.Container(height: h, alignment: pw.Alignment.center, child: pw.Text(t, style: pw.TextStyle(font: f, fontSize: 11)));
  static pw.Widget _playerBox(Player? p, pw.Font f, pw.Font fb, double h) => pw.Container(height: h, alignment: pw.Alignment.center, child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
    pw.Text(p?.name ?? '__________', style: pw.TextStyle(font: fb, fontSize: 18)),
    pw.SizedBox(height: 4),
    pw.Text(p?.affiliation ?? '__________', style: pw.TextStyle(font: f, fontSize: 11)),
  ]));
  static pw.Widget _setRow(int n, pw.Font fb, double h) => pw.Container(height: h, child: pw.Row(children: [
    pw.Expanded(child: pw.Container(decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)))),
    pw.Container(width: 30, height: h, color: PdfColor.fromHex('#EEEEEE'), alignment: pw.Alignment.center, child: pw.Text('$n', style: pw.TextStyle(font: fb, fontSize: 12))),
    pw.Expanded(child: pw.Container(decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)))),
  ]));
}
