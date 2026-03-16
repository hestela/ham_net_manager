import 'package:excel/excel.dart';
import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../repositories/net_repository.dart';
import '../utils/file_io.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  // Daily Check-in Data range
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  bool _exporting = false;

  // Member Check-in History range
  DateTime? _historyStart;
  DateTime? _historyEnd;
  bool _exportingHistory = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _rangeStart = today.subtract(const Duration(days: 7));
    _rangeEnd = today;
    _historyStart = DateTime(now.year - 1, now.month, now.day);
    _historyEnd = today;
  }

  // ── Preset buttons (affect both date ranges) ────────────────────────────────

  void _applyPreset(int daysBack) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime start;
    if (daysBack == 0) {
      start = today;
    } else if (daysBack == 7) {
      start = today.subtract(const Duration(days: 7));
    } else if (daysBack == 30) {
      start = DateTime(now.year, now.month - 1, now.day);
    } else {
      // 1 year
      start = DateTime(now.year - 1, now.month, now.day);
    }
    setState(() {
      _rangeStart = start;
      _rangeEnd = today;
      _historyStart = start;
      _historyEnd = today;
    });
  }

  // ── Export: Daily Check-in Data ─────────────────────────────────────────────

  Future<void> _exportXlsx() async {
    if (_rangeStart == null || _rangeEnd == null) return;
    if (_rangeStart!.isAfter(_rangeEnd!)) return;
    setState(() => _exporting = true);

    final List<WeekSummary> summaries =
        await NetRepository.loadWeekSummaries(_rangeStart!, _rangeEnd!);
    final List<Map<String, dynamic>> checkinRows =
        await NetRepository.loadCheckinsForRange(_rangeStart!, _rangeEnd!);

    final excel = Excel.createExcel();

    final boldStyle = CellStyle(bold: true);

    void appendRow(Sheet sheet, List<CellValue?> values, {bool bold = false}) {
      sheet.appendRow(values);
      if (bold) {
        final int rowIdx = sheet.maxRows - 1;
        for (var c = 0; c < values.length; c++) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIdx))
              .cellStyle = boldStyle;
        }
      }
    }

    // ── Sheet 1: Daily Counts ─────────────────────────────────────────────────
    final Sheet countsSheet = excel['Daily Counts'];
    excel.delete('Sheet1');

    appendRow(countsSheet, [
      TextCellValue('Date'),
      TextCellValue('Non-GMRS Members'),
      TextCellValue('All Members'),
      TextCellValue('Non-GMRS Guests'),
      TextCellValue('All Guests'),
    ], bold: true);

    for (final s in summaries) {
      final DateTime dt = s.weekEnding;
      final label =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      appendRow(countsSheet, [
        TextCellValue(label),
        IntCellValue(s.hamOnlyMembers),
        IntCellValue(s.allMembers),
        IntCellValue(s.hamOnlyGuests),
        IntCellValue(s.allGuests),
      ]);
    }

    appendRow(countsSheet, [
      TextCellValue('Total'),
      IntCellValue(summaries.fold(0, (sum, s) => sum + s.hamOnlyMembers)),
      IntCellValue(summaries.fold(0, (sum, s) => sum + s.allMembers)),
      IntCellValue(summaries.fold(0, (sum, s) => sum + s.hamOnlyGuests)),
      IntCellValue(summaries.fold(0, (sum, s) => sum + s.allGuests)),
    ], bold: true);

    countsSheet.setColumnWidth(0, 13);
    countsSheet.setColumnWidth(1, 20);
    countsSheet.setColumnWidth(2, 14);
    countsSheet.setColumnWidth(3, 18);
    countsSheet.setColumnWidth(4, 13);

    // ── Sheet 2: Check-ins ────────────────────────────────────────────────────
    final Sheet detailSheet = excel['Check-ins'];

    appendRow(detailSheet, [
      TextCellValue('Date'),
      TextCellValue('GMRS Callsign'),
      TextCellValue('FCC Callsign'),
      TextCellValue('Name'),
      TextCellValue('Member/Guest'),
      ...kCheckInMethods
          .map((m) => TextCellValue(kMethodLabels[m]!.replaceAll('\n', ' '))),
      TextCellValue('City'),
      TextCellValue('Neighborhood'),
    ], bold: true);

    for (final row in checkinRows) {
      final Set<String> methodSet =
          (row['methods'] as String).split(',').toSet();
      final String name =
          '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'.trim();
      final isMember = (row['is_member'] as int) == 1;
      appendRow(detailSheet, [
        TextCellValue(row['week_ending'] as String),
        TextCellValue(row['gmrs_callsign'] as String? ?? ''),
        TextCellValue(row['fcc_callsign'] as String? ?? ''),
        TextCellValue(name),
        TextCellValue(isMember ? 'Member' : 'Guest'),
        ...kCheckInMethods
            .map((m) => TextCellValue(methodSet.contains(m) ? 'X' : '')),
        TextCellValue(row['city'] as String? ?? ''),
        TextCellValue(row['neighborhood'] as String? ?? ''),
      ]);
    }

    detailSheet.setColumnWidth(0, 13);
    detailSheet.setColumnWidth(1, 16);
    detailSheet.setColumnWidth(2, 14);
    detailSheet.setColumnWidth(3, 22);
    detailSheet.setColumnWidth(4, 14);
    detailSheet.setColumnWidth(5, 18);
    detailSheet.setColumnWidth(6, 17);
    detailSheet.setColumnWidth(7, 15);
    detailSheet.setColumnWidth(8, 18);
    detailSheet.setColumnWidth(9, 16);
    detailSheet.setColumnWidth(10, 14);
    detailSheet.setColumnWidth(11, 16);
    detailSheet.setColumnWidth(12, 16);

    // ── Save ──────────────────────────────────────────────────────────────────
    String fmtDate(DateTime dt) =>
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

    final String netName =
        DatabaseHelper.currentCity.replaceAll(RegExp(r'[\s/]+'), '-');
    final filename =
        '$netName-report-${fmtDate(_rangeStart!)}-to-${fmtDate(_rangeEnd!)}.xlsx';

    final List<int>? bytes = excel.encode();

    if (!mounted) return;
    setState(() => _exporting = false);

    if (bytes == null) return;
    final String? savedPath = await saveXlsxFile(filename, bytes);
    if (savedPath == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${checkinRows.length} check-ins.')),
      );
    }
  }

  // ── Export: Member Check-in History ─────────────────────────────────────────

  Future<void> _exportHistoryXlsx() async {
    if (_historyStart == null || _historyEnd == null) return;
    if (_historyStart!.isAfter(_historyEnd!)) return;
    setState(() => _exportingHistory = true);

    final List<Map<String, dynamic>> rows =
        await NetRepository.loadMemberCheckinHistory(
            _historyStart!, _historyEnd!);

    final excel = Excel.createExcel();
    final Sheet sheet = excel['Member Check-in History'];
    excel.delete('Sheet1');

    final boldStyle = CellStyle(bold: true);

    void appendRow(List<CellValue?> values, {bool bold = false}) {
      sheet.appendRow(values);
      if (bold) {
        final int rowIdx = sheet.maxRows - 1;
        for (var c = 0; c < values.length; c++) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIdx))
              .cellStyle = boldStyle;
        }
      }
    }

    appendRow([
      TextCellValue('Name'),
      TextCellValue('GMRS Callsign'),
      TextCellValue('FCC Callsign'),
      TextCellValue('Member/Guest'),
      TextCellValue('Last Check-in'),
      TextCellValue('Check-ins in Period'),
    ], bold: true);

    for (final row in rows) {
      final String name =
          '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'.trim();
      final isMember = (row['is_member'] as int) == 1;
      appendRow([
        TextCellValue(name),
        TextCellValue(row['gmrs_callsign'] as String? ?? ''),
        TextCellValue(row['fcc_callsign'] as String? ?? ''),
        TextCellValue(isMember ? 'Member' : 'Guest'),
        TextCellValue(row['last_checkin_date'] as String? ?? ''),
        IntCellValue(row['checkin_count'] as int),
      ]);
    }

    sheet.setColumnWidth(0, 22);
    sheet.setColumnWidth(1, 16);
    sheet.setColumnWidth(2, 14);
    sheet.setColumnWidth(3, 14);
    sheet.setColumnWidth(4, 16);
    sheet.setColumnWidth(5, 20);

    String fmtDate(DateTime dt) =>
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

    final String netName =
        DatabaseHelper.currentCity.replaceAll(RegExp(r'[\s/]+'), '-');
    final filename =
        '$netName-member-history-${fmtDate(_historyStart!)}-to-${fmtDate(_historyEnd!)}.xlsx';

    final List<int>? bytes = excel.encode();

    if (!mounted) return;
    setState(() => _exportingHistory = false);

    if (bytes == null) return;
    final String? savedPath = await saveXlsxFile(filename, bytes);
    if (savedPath == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${rows.length} members.')),
      );
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _fmtDate(DateTime dt) =>
      '${dt.month}/${dt.day}/${dt.year.toString().substring(2)}';

  bool get _rangeInvalid =>
      _rangeStart != null &&
      _rangeEnd != null &&
      _rangeStart!.isAfter(_rangeEnd!);

  bool get _historyInvalid =>
      _historyStart != null &&
      _historyEnd != null &&
      _historyStart!.isAfter(_historyEnd!);

  Future<void> _pickDate(
      BuildContext context, DateTime? current, void Function(DateTime) onPicked) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) onPicked(picked);
  }

  TableRow _buildReportTableRow({
    required BuildContext context,
    required String label,
    required DateTime? start,
    required DateTime? end,
    required bool invalid,
    required bool exporting,
    required VoidCallback onExport,
    required void Function(DateTime) onStartPicked,
    required void Function(DateTime) onEndPicked,
  }) {
    return TableRow(
      children: [
        // Export button (column width driven by widest label)
        Padding(
          padding: const EdgeInsets.only(right: 16, bottom: 8),
          child: ElevatedButton.icon(
            icon: exporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: Text(label),
            onPressed: (invalid || exporting) ? null : onExport,
          ),
        ),
        // From / To date pickers
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('From:'),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(start != null ? _fmtDate(start) : 'Pick date'),
                    onPressed: () => _pickDate(context, start, onStartPicked),
                  ),
                  const SizedBox(width: 12),
                  const Text('To:'),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(end != null ? _fmtDate(end) : 'Pick date'),
                    onPressed: () => _pickDate(context, end, onEndPicked),
                  ),
                ],
              ),
              if (invalid)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Start date must be before end date.',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Preset buttons ───────────────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: () => _applyPreset(0),
                    child: const Text('1 day'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _applyPreset(7),
                    child: const Text('1 Week'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _applyPreset(30),
                    child: const Text('1 Month'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _applyPreset(365),
                    child: const Text('1 Year'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Report rows (Table keeps buttons column width in sync) ────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                _buildReportTableRow(
                  context: context,
                  label: 'Daily Check-in Data',
                  start: _rangeStart,
                  end: _rangeEnd,
                  invalid: _rangeInvalid,
                  exporting: _exporting,
                  onExport: _exportXlsx,
                  onStartPicked: (d) => setState(() => _rangeStart = d),
                  onEndPicked: (d) => setState(() => _rangeEnd = d),
                ),
                _buildReportTableRow(
                  context: context,
                  label: 'Member Check-in History',
                  start: _historyStart,
                  end: _historyEnd,
                  invalid: _historyInvalid,
                  exporting: _exportingHistory,
                  onExport: _exportHistoryXlsx,
                  onStartPicked: (d) => setState(() => _historyStart = d),
                  onEndPicked: (d) => setState(() => _historyEnd = d),
                ),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }
}
