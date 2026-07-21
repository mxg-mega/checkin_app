// lib/features/admin/reports/report_exporter.dart
//
// Turns a List<ReportRow> into a downloadable CSV or PDF file.
// Uses file_saver so this works identically on mobile (native share/save)
// and PWA (browser download) without platform-specific branching here.

import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'report_data_repository.dart';

class ReportExporter {
  Future<void> exportCsv(List<ReportRow> rows, {required String filenamePrefix}) async {
    final header = [
      'Employee',
      'Date',
      'Worked (hrs)',
      'Expected (hrs)',
      'Adjustment (hrs)',
      'Net (hrs)',
      'Dangling Punch',
    ];

    final data = rows
        .map((r) => [
              r.fullName,
              DateFormat('yyyy-MM-dd').format(r.workDate),
              r.workedHours.toStringAsFixed(2),
              r.expectedHours.toStringAsFixed(2),
              r.adjustmentHours.toStringAsFixed(2),
              r.netHours.toStringAsFixed(2),
              r.hasDanglingPunch ? 'Yes' : 'No',
            ])
        .toList();

    final csvString = const ListToCsvConverter().convert([header, ...data]);
    final bytes = Uint8List.fromList(utf8.encode(csvString));

    await FileSaver.instance.saveFile(
      name: '$filenamePrefix.csv',
      bytes: bytes,
      mimeType: MimeType.csv,
    );
  }

  Future<void> exportPdf(
    List<ReportRow> rows, {
    required String filenamePrefix,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final doc = pw.Document();
    final dateFormat = DateFormat('MMM d, yyyy');

    // Group rows by employee for a cleaner per-person breakdown.
    final byEmployee = <String, List<ReportRow>>{};
    for (final row in rows) {
      byEmployee.putIfAbsent(row.fullName, () => []).add(row);
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Attendance & Hours Report', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text('${dateFormat.format(startDate)} – ${dateFormat.format(endDate)}'),
            pw.Divider(),
          ],
        ),
        build: (context) => byEmployee.entries.map((entry) {
          final name = entry.key;
          final employeeRows = entry.value;
          final totalNet = employeeRows.fold<double>(0, (sum, r) => sum + r.netHours);

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(height: 12),
              pw.Text(name, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Text(
                totalNet >= 0
                    ? 'Net: +${totalNet.toStringAsFixed(2)} hrs overtime'
                    : 'Net: ${totalNet.toStringAsFixed(2)} hrs to repay',
                style: pw.TextStyle(
                  color: totalNet >= 0 ? PdfColors.green800 : PdfColors.red800,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headers: ['Date', 'Worked', 'Expected', 'Adjustment', 'Net', 'Flag'],
                data: employeeRows
                    .map((r) => [
                          DateFormat('MMM d').format(r.workDate),
                          r.workedHours.toStringAsFixed(2),
                          r.expectedHours.toStringAsFixed(2),
                          r.adjustmentHours.toStringAsFixed(2),
                          r.netHours.toStringAsFixed(2),
                          r.hasDanglingPunch ? '!' : '',
                        ])
                    .toList(),
              ),
            ],
          );
        }).toList(),
      ),
    );

    final bytes = await doc.save();
    await FileSaver.instance.saveFile(
      name: '$filenamePrefix.pdf',
      bytes: bytes,
      mimeType: MimeType.pdf,
    );
  }
}
