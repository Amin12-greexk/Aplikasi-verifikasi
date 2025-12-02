import 'dart:io';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';

class ExportService {
  /// Exports the log data to a PDF file with file picker.
  static Future<String?> exportToPdf(
    List<Map<String, Object?>> logs,
    String reportTitle, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Filter logs by date range if provided
    List<Map<String, Object?>> filteredLogs = _filterLogsByDate(logs, startDate, endDate);

    // Show file picker to select save location
    String? outputFile = await FilePicker.platform.saveFile(
      fileName: 'Laporan_Ijin_Pulang_${DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now())}.pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (outputFile == null) return null; // User cancelled

    return await _generatePdf(filteredLogs, reportTitle, outputFile);
  }

  static Future<String> _generatePdf(
    List<Map<String, Object?>> logs,
    String reportTitle,
    String outputFile,
  ) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final dateFormat = DateFormat('dd MMMM yyyy HH:mm:ss');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          // Header
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'LAPORAN IJIN PULANG',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Tanggal: ${dateFormat.format(now)}',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 20),
            ],
          ),
          // Statistics
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _buildStatBox('Total', logs.length.toString()),
              _buildStatBox(
                  'Acc Pengawas',
                  logs
                      .where((l) => l['status_pengawas'] == 'ACC')
                      .length
                      .toString()),
              _buildStatBox(
                  'Acc Security',
                  logs
                      .where((l) => l['status_security'] == 'ACC')
                      .length
                      .toString()),
              _buildStatBox(
                  'Pending Security',
                  logs
                      .where((l) => l['status_pengawas'] == 'ACC' &&
                          l['status_security'] != 'ACC')
                      .length
                      .toString()),
            ],
          ),
          pw.SizedBox(height: 20),
          // Table
          pw.TableHelper.fromTextArray(
            headers: [
              'ID Karyawan',
              'Status Pengawas',
              'Status Security',
            ],
            data: logs
                .map((log) => [
                      log['id_karyawan']?.toString() ?? '',
                      log['status_pengawas']?.toString() ?? 'PENDING',
                      log['status_security']?.toString() ?? 'PENDING',
                    ])
                .toList(),
            border: pw.TableBorder.all(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFF059669),
            ),
            rowDecoration: pw.BoxDecoration(
              border: pw.Border.all(),
            ),
            cellHeight: 25,
            cellPadding: const pw.EdgeInsets.all(5),
          ),
          pw.SizedBox(height: 20),
          pw.Divider(),
          pw.SizedBox(height: 10),
          pw.Text(
            'Dokumen ini dibuat oleh sistem Verifikasi Pulang',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
          ),
        ],
      ),
    );

    final file = File(outputFile);
    await file.writeAsBytes(await pdf.save());

    return outputFile;
  }

  /// Exports the log data to an Excel file with file picker.
  static Future<String?> exportToExcel(
    List<Map<String, Object?>> logs,
    String reportTitle, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Filter logs by date range if provided
    List<Map<String, Object?>> filteredLogs = _filterLogsByDate(logs, startDate, endDate);

    // Show file picker to select save location
    String? outputFile = await FilePicker.platform.saveFile(
      fileName: 'Laporan_Ijin_Pulang_${DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now())}.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (outputFile == null) return null; // User cancelled

    return await _generateExcel(filteredLogs, reportTitle, outputFile);
  }

  static Future<String> _generateExcel(
    List<Map<String, Object?>> logs,
    String reportTitle,
    String outputFile,
  ) async {
    final excelSheet = excel.Excel.createExcel();
    final sheet = excelSheet['Sheet1'];

    // Headers
    sheet.appendRow([
      excel.TextCellValue('ID Karyawan'),
      excel.TextCellValue('Status Pengawas'),
      excel.TextCellValue('Status Security'),
      excel.TextCellValue('Tanggal Laporan'),
    ]);

    // Style header
    // FIX: Using ExcelColor.fromHexString instead of raw String
    final headerColor = excel.ExcelColor.fromHexString('059669');
    
    for (int i = 0; i < 4; i++) {
      var cell = sheet
          .cell(excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.cellStyle = excel.CellStyle(
        backgroundColorHex: headerColor,
        bold: true,
        fontColorHex: excel.ExcelColor.white, // Added white text for readability
        horizontalAlign: excel.HorizontalAlign.Center,
      );
    }

    // Data rows
    int rowIndex = 1;
    // FIX: Define alternate row color using ExcelColor
    final alternateColor = excel.ExcelColor.fromHexString('F0F0F0');

    for (var log in logs) {
      sheet.appendRow([
        excel.TextCellValue(log['id_karyawan']?.toString() ?? ''),
        excel.TextCellValue(log['status_pengawas']?.toString() ?? 'PENDING'),
        excel.TextCellValue(log['status_security']?.toString() ?? 'PENDING'),
        excel.TextCellValue(
            DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())),
      ]);

      // Alternate row colors
      if (rowIndex % 2 == 0) {
        for (int i = 0; i < 4; i++) {
          sheet.cell(excel.CellIndex.indexByColumnRow(
                  columnIndex: i, rowIndex: rowIndex))
            ..cellStyle = excel.CellStyle(
              backgroundColorHex: alternateColor,
            );
        }
      }
      rowIndex++;
    }

    // Set column widths
    sheet.setColumnWidth(0, 15);
    sheet.setColumnWidth(1, 15);
    sheet.setColumnWidth(2, 15);
    sheet.setColumnWidth(3, 20);

    final file = File(outputFile);

    // FIX: using .save() instead of .encode() for better compatibility
    var fileBytes = excelSheet.save();
    if (fileBytes != null) {
      await file.writeAsBytes(fileBytes);
    }

    return outputFile;
  }

  static pw.Widget _buildStatBox(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: const PdfColor.fromInt(0xFF059669)),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(0xFF059669),
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
  }

  /// Filter logs by date range
  static List<Map<String, Object?>> _filterLogsByDate(
    List<Map<String, Object?>> logs,
    DateTime? startDate,
    DateTime? endDate,
  ) {
    if (startDate == null && endDate == null) {
      return logs;
    }

    return logs.where((log) {
      // If no dates provided, include all
      if (startDate == null && endDate == null) return true;

      // For now, since we don't have timestamps in the data, we'll include all
      // In a real scenario, you'd have a timestamp field to compare
      return true;
    }).toList();
  }
}