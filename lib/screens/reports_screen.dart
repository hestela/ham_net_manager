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
  List<DateTime> _availableWeeks = [];
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  List<WeekSummary> _summaries = [];
  bool _loading = true;
  bool _loadingSummaries = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Set<DateTime> dates = await NetRepository.loadDatesWithCheckins();
    final List<DateTime> sorted = dates.toList()..sort();
    if (!mounted) return;
    setState(() {
      _availableWeeks = sorted;
      _rangeStart = sorted.isNotEmpty ? sorted.first : null;
      _rangeEnd = sorted.isNotEmpty ? sorted.last : null;
      _loading = false;
    });
    await _loadSummaries();
  }

  Future<void> _pickStart() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _rangeStart ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _rangeStart = picked);
    _loadSummaries();
  }

  Future<void> _pickEnd() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _rangeEnd ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _rangeEnd = picked);
    _loadSummaries();
  }

  Future<void> _loadSummaries() async {
    if (_rangeStart == null || _rangeEnd == null) return;
    if (_rangeStart!.isAfter(_rangeEnd!)) return;
    setState(() => _loadingSummaries = true);
    final List<WeekSummary> summaries =
        await NetRepository.loadWeekSummaries(_rangeStart!, _rangeEnd!);
    if (!mounted) return;
    setState(() {
      _summaries = summaries;
      _loadingSummaries = false;
    });
  }

  Future<void> _exportXlsx() async {
    if (_rangeStart == null || _rangeEnd == null) return;
    if (_rangeStart!.isAfter(_rangeEnd!)) return;
    setState(() => _exporting = true);

    final List<Map<String, dynamic>> checkinRows =
        await NetRepository.loadCheckinsForRange(_rangeStart!, _rangeEnd!);

    final excel = Excel.createExcel();

    // ── Sheet 1: Daily Counts ─────────────────────────────────────────────────
    final Sheet countsSheet = excel['Daily Counts'];
    excel.delete('Sheet1'); // remove default blank sheet

    final boldStyle = CellStyle(bold: true);

    void appendRow(Sheet sheet, List<CellValue?> values,
        {bool bold = false}) {
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

    appendRow(countsSheet, [
      TextCellValue('Date'),
      TextCellValue('Non-GMRS Members'),
      TextCellValue('All Members'),
      TextCellValue('Non-GMRS Guests'),
      TextCellValue('All Guests'),
    ], bold: true);

    for (final WeekSummary s in _summaries) {
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

    // Totals row
    appendRow(countsSheet, [
      TextCellValue('Total'),
      IntCellValue(_summaries.fold(0, (sum, s) => sum + s.hamOnlyMembers)),
      IntCellValue(_summaries.fold(0, (sum, s) => sum + s.allMembers)),
      IntCellValue(_summaries.fold(0, (sum, s) => sum + s.hamOnlyGuests)),
      IntCellValue(_summaries.fold(0, (sum, s) => sum + s.allGuests)),
    ], bold: true);

    // Column widths for Daily Counts sheet
    countsSheet.setColumnWidth(0, 13); // Date
    countsSheet.setColumnWidth(1, 20); // Non-GMRS Members
    countsSheet.setColumnWidth(2, 14); // All Members
    countsSheet.setColumnWidth(3, 18); // Non-GMRS Guests
    countsSheet.setColumnWidth(4, 13); // All Guests

    // ── Sheet 2: Check-ins ────────────────────────────────────────────────────
    final Sheet detailSheet = excel['Check-ins'];

    appendRow(detailSheet, [
      TextCellValue('Date'),
      TextCellValue('GMRS Callsign'),
      TextCellValue('FCC Callsign'),
      TextCellValue('Name'),
      TextCellValue('Member/Guest'),
      ...kCheckInMethods.map(
          (m) => TextCellValue(kMethodLabels[m]!.replaceAll('\n', ' '))),
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

    // Column widths for Check-ins sheet
    detailSheet.setColumnWidth(0, 13);  // Date
    detailSheet.setColumnWidth(1, 16);  // GMRS Callsign
    detailSheet.setColumnWidth(2, 14);  // FCC Callsign
    detailSheet.setColumnWidth(3, 22);  // Name
    detailSheet.setColumnWidth(4, 14);  // Member/Guest
    detailSheet.setColumnWidth(5, 18);  // Repeater Check-In
    detailSheet.setColumnWidth(6, 17);  // Simplex Check-In
    detailSheet.setColumnWidth(7, 15);  // Active on DMR
    detailSheet.setColumnWidth(8, 18);  // GMRS Net Check-in
    detailSheet.setColumnWidth(9, 16);  // Packet Check-In
    detailSheet.setColumnWidth(10, 14); // Active on HF
    detailSheet.setColumnWidth(11, 16); // City
    detailSheet.setColumnWidth(12, 16); // Neighborhood

    // ── Save ──────────────────────────────────────────────────────────────────
    String fmtDate(DateTime dt) =>
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

    final String startStr = fmtDate(_rangeStart!);
    final String endStr = fmtDate(_rangeEnd!);
    final String netName =
        DatabaseHelper.currentCity.replaceAll(RegExp(r'[\s/]+'), '-');
    final filename = '$netName-report-$startStr-to-$endStr.xlsx';

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

  String _fmtDate(DateTime dt) =>
      '${dt.month}/${dt.day}/${dt.year.toString().substring(2)}';

  bool get _rangeInvalid =>
      _rangeStart != null &&
      _rangeEnd != null &&
      _rangeStart!.isAfter(_rangeEnd!);

  static const double _wDate = 120.0;
  static const double _wNum = 130.0;
  static const double _tableWidth = _wDate + _wNum * 4;
  static const double _rowH = 40.0;

  Widget _buildTableHeader() {
    const style = TextStyle(fontWeight: FontWeight.bold, fontSize: 13);
    return ColoredBox(
      color: Colors.grey.shade300,
      child: Row(
        children: [
          SizedBox(
              width: _wDate,
              child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text('Date', style: style))),
          SizedBox(
              width: _wNum,
              child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text('Non-GMRS\nMembers', style: style))),
          SizedBox(
              width: _wNum,
              child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text('All\nMembers', style: style))),
          SizedBox(
              width: _wNum,
              child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text('Non-GMRS\nGuests', style: style))),
          SizedBox(
              width: _wNum,
              child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text('All\nGuests', style: style))),
        ],
      ),
    );
  }

  Widget _buildTableRow(String date, int hamMembers, int allMembers,
      int hamGuests, int allGuests,
      {bool bold = false, Color? color}) {
    final style =
        TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    Widget cell(String text, double w) => SizedBox(
          width: w,
          height: _rowH,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
                alignment: Alignment.centerLeft, child: Text(text, style: style)),
          ),
        );
    return ColoredBox(
      color: color ?? Colors.transparent,
      child: Row(
        children: [
          cell(date, _wDate),
          cell('$hamMembers', _wNum),
          cell('$allMembers', _wNum),
          cell('$hamGuests', _wNum),
          cell('$allGuests', _wNum),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Controls (fixed, horizontally scrollable) ────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Text('Start:'),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(_rangeStart != null
                            ? _fmtDate(_rangeStart!)
                            : 'Pick date'),
                        onPressed: _pickStart,
                      ),
                      const SizedBox(width: 24),
                      const Text('End:'),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(_rangeEnd != null
                            ? _fmtDate(_rangeEnd!)
                            : 'Pick date'),
                        onPressed: _pickEnd,
                      ),
                      const SizedBox(width: 24),
                      for (final (String label, int days) in [
                        ('1 day', 0),
                        ('1 week', 7),
                        ('2 weeks', 14),
                        ('4 weeks', 28),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: OutlinedButton(
                            onPressed: _rangeEnd == null
                                ? null
                                : () {
                                    setState(() => _rangeStart =
                                        _rangeEnd!
                                            .subtract(Duration(days: days)));
                                    _loadSummaries();
                                  },
                            child: Text(label),
                          ),
                        ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        icon: _exporting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.download),
                        label: const Text('Download XLSX Report'),
                        onPressed: (_rangeInvalid || _exporting)
                            ? null
                            : _exportXlsx,
                      ),
                    ],
                  ),
                ),

                if (_rangeInvalid)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Start date must be before end date.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),

                const Divider(height: 1),

                // ── Table (fills remaining space, scrolls both axes) ─────
                if (_loadingSummaries)
                  const Expanded(
                      child: Center(child: CircularProgressIndicator()))
                else if (_availableWeeks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No check-ins recorded yet.'),
                  )
                else if (_summaries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No check-ins in selected range.'),
                  )
                else
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final double w = _tableWidth > constraints.maxWidth
                            ? _tableWidth
                            : constraints.maxWidth;
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: w,
                            child: Column(
                              children: [
                                _buildTableHeader(),
                                const Divider(height: 1),
                                Flexible(
                                  child: ListView.separated(
                                    itemCount: _summaries.length + 1,
                                    separatorBuilder: (_, __) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, i) {
                                      if (i < _summaries.length) {
                                        final WeekSummary s = _summaries[i];
                                        final DateTime dt = s.weekEnding;
                                        final label =
                                            '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                                        return _buildTableRow(
                                          label,
                                          s.hamOnlyMembers,
                                          s.allMembers,
                                          s.hamOnlyGuests,
                                          s.allGuests,
                                          color: i.isEven
                                              ? Colors.grey.shade50
                                              : null,
                                        );
                                      } else {
                                        // Totals row
                                        return _buildTableRow(
                                          'Total',
                                          _summaries.fold(
                                              0,
                                              (sum, s) =>
                                                  sum + s.hamOnlyMembers),
                                          _summaries.fold(
                                              0,
                                              (sum, s) =>
                                                  sum + s.allMembers),
                                          _summaries.fold(
                                              0,
                                              (sum, s) =>
                                                  sum + s.hamOnlyGuests),
                                          _summaries.fold(
                                              0,
                                              (sum, s) =>
                                                  sum + s.allGuests),
                                          bold: true,
                                          color: Colors.grey.shade200,
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}
