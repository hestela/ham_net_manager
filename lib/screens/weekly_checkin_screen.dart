import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_version.dart';
import '../database/database_helper.dart';
import '../models/person.dart';
import '../repositories/net_repository.dart';
import 'manage_cities_screen.dart';
import 'manage_persons_screen.dart';
import 'net_control_script_dialog.dart';
import 'setup_screen.dart';

// ── Column widths ─────────────────────────────────────────────────────────────

const _wGmrs = 95.0;
const _wCall = 95.0;
const _wName = 135.0;
const _wMember = 62.0;
const _wMethod = 88.0; // ×6
const _wCity = 105.0;
const _wNeighborhood = 150.0;
const _wCheckedIn = 58.0;

const _totalTableWidth = _wGmrs +
    _wCall +
    _wName +
    _wMember +
    _wMethod * 6 +
    _wCity +
    _wNeighborhood +
    _wCheckedIn;

// Row height for person rows — tight but readable
const _rowH = 42.0;

// ── Sort columns ──────────────────────────────────────────────────────────────

enum _SortColumn { callSign, name, member, city }

// ── Screen ────────────────────────────────────────────────────────────────────

class WeeklyCheckinScreen extends StatefulWidget {
  const WeeklyCheckinScreen({super.key});

  @override
  State<WeeklyCheckinScreen> createState() => _WeeklyCheckinScreenState();
}

class _WeeklyCheckinScreenState extends State<WeeklyCheckinScreen> {
  DateTime _weekEnding = _defaultWeekEnding();
  int? _weekId;
  List<Person> _persons = [];
  Map<int, Set<String>> _checkins = {}; // personId → checked methods
  Map<String, Map<String, dynamic>> _netRoles = {}; // 'Day|role' → DB row
  bool _membersExpanded = true;
  bool _guestsExpanded = false;
  bool _loading = true;
  _SortColumn? _sortColumn = _SortColumn.name;
  bool _sortAscending = true;
  final _searchController = TextEditingController();
  String _query = '';
  bool _scriptPanelOpen = false;
  double _scriptPanelWidth = 400;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
    _loadInitialDate();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialDate() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString('last_selected_date');
    if (savedDate != null) {
      _weekEnding = DateTime.parse(savedDate);
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final persons = await NetRepository.loadPersons();
    final weekId = await NetRepository.findOrCreateWeek(_weekEnding);
    final methods = await NetRepository.loadCheckins(weekId);
    final netRoles = await NetRepository.loadNetRoles(weekId);

    setState(() {
      _persons = persons;
      _weekId = weekId;
      _checkins = methods;
      _netRoles = netRoles;
      _loading = false;
    });
    _applySorting();
  }

  void _toggleSort(_SortColumn column) {
    setState(() {
      if (_sortColumn == column) {
        if (_sortAscending) {
          _sortAscending = false;
        } else {
          // Third click: clear sort
          _sortColumn = null;
          _sortAscending = true;
        }
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
    _applySorting();
  }

  void _applySorting() {
    if (_sortColumn == null) return;
    setState(() {
      _persons.sort((a, b) {
        int cmp;
        switch (_sortColumn!) {
          case _SortColumn.callSign:
            cmp = (a.fccCallsign ?? '').compareTo(b.fccCallsign ?? '');
          case _SortColumn.name:
            cmp = a.displayName.toLowerCase().compareTo(
                b.displayName.toLowerCase());
          case _SortColumn.member:
            // Members first when ascending
            cmp = (b.isMember ? 1 : 0) - (a.isMember ? 1 : 0);
          case _SortColumn.city:
            cmp = (a.city ?? '').compareTo(b.city ?? '');
        }
        return _sortAscending ? cmp : -cmp;
      });
    });
  }

  // ── Date picking ────────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _weekEnding,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'Select net date',
    );
    if (picked != null && picked != _weekEnding) {
      _weekEnding = picked;
      // Save the selected date
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_selected_date', _weekEnding.toIso8601String());
      await _load();
    }
  }

  // ── CSV export ──────────────────────────────────────────────────────────────

  String _sanitizeFilename(String name) {
    // Replace spaces and forward slashes with hyphens for cross-platform compatibility
    return name.replaceAll(RegExp(r'[\s/]+'), '-');
  }

  Future<void> _exportCsv() async {
    final dateStr =
        '${_weekEnding.year}-${_weekEnding.month.toString().padLeft(2, '0')}-${_weekEnding.day.toString().padLeft(2, '0')}';

    // Header row
    final header = [
      'GMRS Callsign',
      'FCC Callsign',
      'Name',
      'Member',
      ...kCheckInMethods.map((m) => kMethodLabels[m]!.replaceAll('\n', ' ')),
      'City',
      'Neighborhood',
      'Checked In',
    ];

    // Data rows — only persons who checked in
    final rows = <List<String>>[];
    for (final person in _persons) {
      final methods = _checkins[person.id] ?? {};
      if (methods.isEmpty) continue;
      rows.add([
        person.gmrsCallsign ?? '',
        person.fccCallsign ?? '',
        person.displayName,
        person.isMember ? 'Yes' : 'No',
        ...kCheckInMethods.map((m) => methods.contains(m) ? 'X' : ''),
        person.city ?? '',
        person.neighborhood ?? '',
        'Yes',
      ]);
    }

    final csv = const CsvEncoder().convert([header, ...rows]);

    final sanitizedNetName = _sanitizeFilename(DatabaseHelper.currentCity);
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export CSV',
      fileName: '$sanitizedNetName-$dateStr.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null) return;

    final file = File(result);
    await file.writeAsString(csv);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${rows.length} check-ins to ${p.basename(result)}')),
      );
    }
  }

  // ── Check-in toggling ───────────────────────────────────────────────────────

  Future<void> _toggleMethod(int personId, String method, bool checked) async {
    if (_weekId == null) return;
    await NetRepository.setMethod(_weekId!, personId, method, checked);
    setState(() {
      if (checked) {
        _checkins.putIfAbsent(personId, () => {}).add(method);
      } else {
        _checkins[personId]?.remove(method);
        if (_checkins[personId]?.isEmpty ?? false) _checkins.remove(personId);
      }
    });
  }

  // ── Net roles editing ───────────────────────────────────────────────────────

  Future<void> _fillFromPreviousWeek() async {
    if (_weekId == null) return;
    final prev = await NetRepository.loadPreviousNetRoles(_weekId!);
    if (prev.isEmpty) return;
    for (final entry in prev.entries) {
      final parts = entry.key.split('|');
      final day = parts[0];
      final role = parts[1];
      final row = entry.value;
      await NetRepository.setNetRole(
        _weekId!, day, role,
        personId: row['person_id'] as int?,
        displayName: row['display_name'] as String?,
      );
    }
    final roles = await NetRepository.loadNetRoles(_weekId!);
    setState(() => _netRoles = roles);
  }

  Future<void> _editNetRole(String day, String role) async {
    if (_weekId == null) return;

    final key = '$day|$role';
    final current = _netRoles[key];
    final currentPersonId = current?['person_id'] as int?;
    Person? selected = currentPersonId != null
        ? _persons.where((p) => p.id == currentPersonId).firstOrNull
        : null;
    final textCtrl =
        TextEditingController(text: current?['display_name'] as String? ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('$day — ${kNetRoleLabels[role]}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButton<Person?>(
                value: selected,
                isExpanded: true,
                hint: const Text('Select person…'),
                items: [
                  const DropdownMenuItem<Person?>(
                      value: null, child: Text('(none)')),
                  ..._persons.map((p) => DropdownMenuItem<Person?>(
                        value: p,
                        child:
                            Text('${p.displayName} / ${p.fccCallsign ?? '?'}'),
                      )),
                ],
                onChanged: (p) => setS(() => selected = p),
              ),
              if (day == 'Other') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: textCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Free-text (First Name/Call)',
                    hintText: 'e.g. Jane/KG6XYZ',
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await NetRepository.setNetRole(_weekId!, day, role);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Clear'),
            ),
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final displayName =
                    day == 'Other' && textCtrl.text.trim().isNotEmpty
                        ? textCtrl.text.trim()
                        : null;
                await NetRepository.setNetRole(
                  _weekId!, day, role,
                  personId: selected?.id,
                  displayName: displayName,
                );
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    textCtrl.dispose();
    if (saved == true && _weekId != null) {
      final roles = await NetRepository.loadNetRoles(_weekId!);
      setState(() => _netRoles = roles);
    }
  }

  // ── Computed counts ─────────────────────────────────────────────────────────

  bool _matchesSearch(Person p) {
    if (_query.isEmpty) return true;
    return p.firstName.toLowerCase().contains(_query) ||
        (p.lastName?.toLowerCase().contains(_query) ?? false) ||
        (p.fccCallsign?.toLowerCase().contains(_query) ?? false) ||
        (p.gmrsCallsign?.toLowerCase().contains(_query) ?? false) ||
        (p.city?.toLowerCase().contains(_query) ?? false) ||
        (p.neighborhood?.toLowerCase().contains(_query) ?? false);
  }

  List<Person> get _memberPersons =>
      _persons.where((p) => p.isMember && _matchesSearch(p)).toList();
  List<Person> get _guestPersons =>
      _persons.where((p) => !p.isMember && _matchesSearch(p)).toList();

  int get _hamOnlyCount => _persons
      .where((p) =>
          p.isMember &&
          (_checkins[p.id]?.any(kHamOnlyMethods.contains) ?? false))
      .length;

  int get _includingGmrsCount => _persons
      .where((p) => p.isMember && (_checkins[p.id]?.isNotEmpty ?? false))
      .length;

  int get _guestHamOnlyCount => _persons
      .where((p) =>
          !p.isMember &&
          (_checkins[p.id]?.any(kHamOnlyMethods.contains) ?? false))
      .length;

  int get _guestIncludingGmrsCount => _persons
      .where((p) => !p.isMember && (_checkins[p.id]?.isNotEmpty ?? false))
      .length;

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      drawer: _buildDrawer(),
      appBar: AppBar(
        title: Text(DatabaseHelper.currentCity),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export CSV',
            onPressed: _exportCsv,
          ),
          IconButton(
            icon: const Icon(Icons.location_city),
            tooltip: 'Manage Cities',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ManageCitiesScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.group),
            tooltip: 'Manage Members',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const ManagePersonsScreen()),
              );
              _load(); // refresh in case persons changed
            },
          ),
        ],
      ),
      body: Row(
        children: [
          // ── Main content ───────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeaderSection(),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event.logicalKey == LogicalKeyboardKey.escape) {
                        _searchController.clear();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by name, callsign, city…',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: _searchController.clear,
                              )
                            : null,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: _totalTableWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Member Check-ins ────────────────────────────
                          _buildSectionHeader(
                            'Member Check-ins',
                            _membersExpanded,
                            () => setState(() =>
                                _membersExpanded = !_membersExpanded),
                          ),
                          if (_membersExpanded) ...[
                            _buildTableHeader(),
                            Flexible(
                              child: ListView(
                                children: _memberPersons.asMap().entries
                                    .map((e) =>
                                        _buildPersonRow(e.value, e.key))
                                    .toList(),
                              ),
                            ),
                            _buildTotalsRow(_memberPersons),
                          ],
                          _buildUniqueCountsSection(),
                          // ── Guest & Visitor Check-ins ──────────────────
                          _buildSectionHeader(
                            'Guest & Visitor Check-ins',
                            _guestsExpanded,
                            () => setState(() =>
                                _guestsExpanded = !_guestsExpanded),
                          ),
                          if (_guestsExpanded) ...[
                            _buildTableHeader(),
                            Flexible(
                              child: ListView(
                                children: _guestPersons.asMap().entries
                                    .map((e) =>
                                        _buildPersonRow(e.value, e.key))
                                    .toList(),
                              ),
                            ),
                            _buildTotalsRow(_guestPersons),
                          ],
                          _buildGuestUniqueCountsSection(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Script side panel ──────────────────────────────────────
          if (_scriptPanelOpen) ...[
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _scriptPanelWidth =
                        (_scriptPanelWidth - details.delta.dx).clamp(250, 800);
                  });
                },
                child: Container(
                  width: 6,
                  color: Colors.grey.shade300,
                ),
              ),
            ),
            SizedBox(
              width: _scriptPanelWidth,
              child: NetControlScriptPanel(
                onClose: () => setState(() => _scriptPanelOpen = false),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Drawer ─────────────────────────────────────────────────────────────────

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.inversePrimary,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text(
                  'Net Manager',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Text(
                  'v$kAppVersion',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Your Info'),
            subtitle: const Text('Your name & callsign'),
            onTap: _editYourInfo,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text('Rename Net'),
            subtitle: Text(DatabaseHelper.currentCity),
            onTap: _renameNet,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('New Database'),
            subtitle: const Text('Create new Net/City'),
            onTap: _createNewDatabase,
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Switch Database'),
            subtitle: const Text('Switch to a different Net/City'),
            onTap: _switchDatabase,
          ),
          ListTile(
            leading: const Icon(Icons.save_as),
            title: const Text('Save Database As...'),
            subtitle: const Text('Export to a different location'),
            onTap: _saveDatabaseAs,
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.error),
            title: Text('Remove Current Database',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            subtitle: const Text('Remove from list or delete file'),
            onTap: _removeCurrentDatabase,
          ),
        ],
      ),
    );
  }

  Future<void> _editYourInfo() async {
    Navigator.of(context).pop(); // close drawer

    final prefs = await SharedPreferences.getInstance();
    final firstCtrl =
        TextEditingController(text: prefs.getString('user_first_name') ?? '');
    final lastCtrl =
        TextEditingController(text: prefs.getString('user_last_name') ?? '');
    final callCtrl =
        TextEditingController(text: prefs.getString('user_callsign') ?? '');

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your Info'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: firstCtrl,
                decoration: const InputDecoration(labelText: 'First Name'),
                textCapitalization: TextCapitalization.words,
                autofocus: true,
              ),
              TextField(
                controller: lastCtrl,
                decoration: const InputDecoration(labelText: 'Last Name'),
                textCapitalization: TextCapitalization.words,
              ),
              TextField(
                controller: callCtrl,
                decoration: const InputDecoration(labelText: 'Callsign'),
                textCapitalization: TextCapitalization.characters,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await prefs.setString(
                  'user_first_name', firstCtrl.text.trim());
              await prefs.setString(
                  'user_last_name', lastCtrl.text.trim());
              await prefs.setString(
                  'user_callsign', callCtrl.text.trim().toUpperCase());
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    firstCtrl.dispose();
    lastCtrl.dispose();
    callCtrl.dispose();
  }

  Future<void> _renameNet() async {
    Navigator.of(context).pop(); // close drawer
    final ctrl = TextEditingController(text: DatabaseHelper.currentCity);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Net'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Net name'),
          textCapitalization: TextCapitalization.words,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await DatabaseHelper.setNetName(name);
    setState(() {}); // refresh app bar title
  }

  Future<void> _createNewDatabase() async {
    Navigator.of(context).pop(); // close drawer

    final ctrl = TextEditingController();
    final cityName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Database'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'City / Net Name',
            hintText: 'e.g. Palo Alto',
          ),
          textCapitalization: TextCapitalization.words,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (cityName == null || cityName.isEmpty || !mounted) return;

    await DatabaseHelper.close();
    if (!mounted) return;
    await DatabaseHelper.initialize(cityName);
    if (!mounted) return;

    setState(() {
      _weekEnding = _defaultWeekEnding();
      _weekId = null;
      _persons = [];
      _checkins = {};
      _netRoles = {};
    });
    await _load();
  }

  Future<void> _switchDatabase() async {
    Navigator.of(context).pop(); // close drawer

    final existing = await DatabaseHelper.findExistingDatabases();
    if (!mounted) return;

    final currentPath = DatabaseHelper.dbPath;

    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch Database'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (existing.isNotEmpty) ...[
                const Text('Existing databases:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                ...existing.map((path) {
                  final isCurrent = path == currentPath;
                  return ListTile(
                    leading: Icon(
                      isCurrent ? Icons.check_circle : Icons.storage,
                      color: isCurrent ? Colors.green : null,
                    ),
                    title: Text(
                      p.basenameWithoutExtension(path),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: isCurrent ? FontWeight.bold : null,
                      ),
                    ),
                    subtitle: Text(path,
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                    enabled: !isCurrent,
                    onTap: () => Navigator.pop(ctx, path),
                  );
                }),
                const Divider(height: 24),
              ],
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Open database file...'),
                subtitle: const Text('Import a .sqlite file from elsewhere'),
                onTap: () => Navigator.pop(ctx, '_pick_file_'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (chosen == null || !mounted) return;

    String? pathToOpen;

    if (chosen == '_pick_file_') {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Open Database File',
        type: FileType.any,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      pathToOpen = result.files.single.path;
      if (pathToOpen == null) return;
    } else {
      pathToOpen = chosen;
    }

    await DatabaseHelper.close();
    if (!mounted) return;
    await DatabaseHelper.openExisting(pathToOpen);
    if (!mounted) return;

    setState(() {
      _weekEnding = _defaultWeekEnding();
      _weekId = null;
      _persons = [];
      _checkins = {};
      _netRoles = {};
    });
    await _load();
  }

  Future<void> _saveDatabaseAs() async {
    Navigator.of(context).pop(); // close drawer
    final sourcePath = DatabaseHelper.dbPath;
    if (sourcePath.isEmpty) return;

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Database As',
      fileName: p.basename(sourcePath),
      type: FileType.any,
    );
    if (result == null) return;

    try {
      await File(sourcePath).copy(result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Database saved to $result')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    }
  }

  Future<void> _removeCurrentDatabase() async {
    Navigator.of(context).pop(); // close drawer

    final path = DatabaseHelper.dbPath;
    final name = DatabaseHelper.currentCity;

    final result = await showDialog<_RemoveAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove database'),
        content: Text('What would you like to do with "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _RemoveAction.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _RemoveAction.hideOnly),
            child: const Text('Remove from list'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, _RemoveAction.deleteFile),
            child: const Text('Delete file'),
          ),
        ],
      ),
    );

    if (result == null || result == _RemoveAction.cancel || !mounted) return;

    await DatabaseHelper.close();
    await DatabaseHelper.removeDatabase(
      path,
      deleteFile: result == _RemoveAction.deleteFile,
    );

    if (!mounted) return;
    final existing = await DatabaseHelper.findExistingDatabases();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SetupScreen(existingPaths: existing),
      ),
    );
  }

  // ── Header section (week selector + net roles) ────────────────────────────

  Widget _buildHeaderSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWeekCard(),
          const SizedBox(width: 16),
          Expanded(child: _buildNetRolesTable()),
        ],
      ),
    );
  }

  Widget _buildWeekCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('Net Date',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(width: 16),
                TextButton(
                  onPressed: _pickDate,
                  style:
                      TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                  child: Text(
                    '${_weekEnding.month}/${_weekEnding.day}/${_weekEnding.year}',
                    style:
                        const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.today),
                  tooltip: 'Jump to today',
                  onPressed: () async {
                    _weekEnding = DateTime.now();
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('last_selected_date', _weekEnding.toIso8601String());
                    await _load();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.description, size: 18),
              label: const Text('Net Control Script'),
              onPressed: _openNetControlScript,
            ),
          ],
        ),
      ),
    );
  }

  void _openNetControlScript() {
    setState(() => _scriptPanelOpen = !_scriptPanelOpen);
  }

  Widget _buildNetRolesTable() {
    return Table(
      border: TableBorder.all(color: Colors.grey.shade400),
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
        3: FlexColumnWidth(),
        4: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        // Day headers
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade200),
          children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: TextButton(
                onPressed: _fillFromPreviousWeek,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 11),
                ),
                child: const Text('Get Previous'),
              ),
            ),
            ...kNetRoleDays.map((d) => Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(d,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center),
                )),
          ],
        ),
        // Net Control row
        _netRoleTableRow('net_control'),
        // Scribe row
        _netRoleTableRow('scribe'),
      ],
    );
  }

  TableRow _netRoleTableRow(String role) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(kNetRoleLabels[role]!,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        ...kNetRoleDays.map((day) => _netRoleCell(day, role)),
      ],
    );
  }

  Widget _netRoleCell(String day, String role) {
    final text = _netRoleDisplay(day, role);
    return GestureDetector(
      onTap: () => _editNetRole(day, role),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        constraints: const BoxConstraints(minHeight: 32),
        child: Text(
          text.isEmpty ? ' ' : text,
          style: TextStyle(
            color: Colors.blue.shade700,
            fontStyle: FontStyle.italic,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  String _netRoleDisplay(String day, String role) {
    final data = _netRoles['$day|$role'];
    if (data == null) return '';
    final override = data['display_name'] as String?;
    if (override != null && override.isNotEmpty) return override;
    final first = data['first_name'] as String?;
    if (first == null) return '';
    final last = data['last_name'] as String?;
    final call = data['fcc_callsign'] as String? ?? '?';
    final name = (last != null && last.isNotEmpty) ? '$first ${last[0]}' : first;
    return '$name/$call';
  }

  // ── Section header ────────────────────────────────────────────────────────

  Widget _buildSectionHeader(
      String title, bool expanded, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _totalTableWidth,
        color: Colors.blueGrey.shade100,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 20),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  // ── Main table ────────────────────────────────────────────────────────────

  Widget _buildTableHeader() {
    const style = TextStyle(fontWeight: FontWeight.bold, fontSize: 12);
    return Container(
      color: Colors.grey.shade300,
      child: Row(
        children: [
          _hdrCell('GMRS\nCall Sign', _wGmrs, style),
          _sortableHdrCell('Call Sign', _wCall, style, _SortColumn.callSign),
          _sortableHdrCell(
              'First Name +\nInitial', _wName, style, _SortColumn.name),
          _sortableHdrCell(
              'Member', _wMember, style, _SortColumn.member, center: true),
          ...kCheckInMethods
              .map((m) => _hdrCell(kMethodLabels[m]!, _wMethod, style, center: true)),
          _sortableHdrCell('City', _wCity, style, _SortColumn.city),
          _hdrCell('Neighborhood', _wNeighborhood, style),
          // Rotated "Checked in"
          SizedBox(
            width: _wCheckedIn,
            height: 60,
            child: Center(
              child: RotatedBox(
                quarterTurns: 3,
                child: Text('Checked in', style: style),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hdrCell(String text, double w, TextStyle style,
      {bool center = false}) {
    return Container(
      width: w,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: Colors.grey.shade400)),
      ),
      child: Text(text,
          style: style,
          textAlign: center ? TextAlign.center : TextAlign.left),
    );
  }

  Widget _sortableHdrCell(String text, double w, TextStyle style,
      _SortColumn column, {bool center = false}) {
    final isActive = _sortColumn == column;
    return GestureDetector(
      onTap: () => _toggleSort(column),
      child: Container(
        width: w,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: Colors.grey.shade400)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment:
              center ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(text,
                  style: style,
                  textAlign: center ? TextAlign.center : TextAlign.left),
            ),
            if (isActive)
              Icon(
                _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonRow(Person person, int rowIndex) {
    final methods = _checkins[person.id] ?? {};
    final checkedIn = methods.isNotEmpty;

    // Alternating colors: white and light blue
    final bg = rowIndex.isEven ? Colors.white : Colors.blue.shade50;

    return Container(
      height: _rowH,
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          _dataCell(person.gmrsCallsign ?? '', _wGmrs),
          _dataCell(person.fccCallsign ?? '', _wCall,
              bold: true),
          _dataCell(person.displayName, _wName),
          _dataCell(person.isMember ? 'X' : '', _wMember, center: true),
          ...kCheckInMethods.map(
              (m) => _methodCell(person, m, methods.contains(m))),
          _dataCell(person.city ?? '', _wCity),
          _dataCell(person.neighborhood ?? '', _wNeighborhood),
          // Checked-in indicator
          SizedBox(
            width: _wCheckedIn,
            child: Center(
              child: Text(
                checkedIn ? 'X' : '',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataCell(String text, double w,
      {bool bold = false, bool center = false}) {
    return Container(
      width: w,
      height: _rowH,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: Colors.grey.shade300)),
      ),
      alignment: center ? Alignment.center : Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          fontWeight: bold ? FontWeight.bold : null,
          fontSize: 13,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _methodCell(Person person, String method, bool checked) {
    return Container(
      width: _wMethod,
      height: _rowH,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: checked,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) =>
                  _toggleMethod(person.id, method, v ?? false),
            ),
          ),
        ],
      ),
    );
  }

  // ── Totals row ────────────────────────────────────────────────────────────

  Widget _buildTotalsRow(List<Person> persons) {
    final counts = <String, int>{};
    for (final p in persons) {
      for (final m in _checkins[p.id] ?? {}) {
        counts[m] = (counts[m] ?? 0) + 1;
      }
    }

    const style = TextStyle(fontWeight: FontWeight.bold, fontSize: 13);

    return Container(
      height: _rowH,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        border: Border(top: BorderSide(color: Colors.grey.shade500, width: 2)),
      ),
      child: Row(
        children: [
          SizedBox(width: _wGmrs + _wCall + _wName + _wMember),
          ...kCheckInMethods.map((m) => Container(
                width: _wMethod,
                decoration: BoxDecoration(
                    border: Border(
                        right: BorderSide(color: Colors.grey.shade400))),
                alignment: Alignment.center,
                child:
                    Text('${counts[m] ?? 0}', style: style),
              )),
          SizedBox(width: _wCity + _wNeighborhood + _wCheckedIn),
        ],
      ),
    );
  }

  // ── Unique counts ─────────────────────────────────────────────────────────

  Widget _buildUniqueCountsSection() {
    return Container(
      width: _totalTableWidth,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade400),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Non-GMRS Check-ins:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_hamOnlyCount',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'All Check-ins:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_includingGmrsCount',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestUniqueCountsSection() {
    return Container(
      width: _totalTableWidth,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade400),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Non-GMRS Check-ins:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_guestHamOnlyCount',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'All Check-ins:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_guestIncludingGmrsCount',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

// ── Helpers ───────────────────────────────────────────────────────────────────

DateTime _defaultWeekEnding() {
  // Returns the most recent Tuesday (or today if today is Tuesday).
  var d = DateTime.now();
  while (d.weekday != DateTime.tuesday) {
    d = d.subtract(const Duration(days: 1));
  }
  return DateTime(d.year, d.month, d.day);
}

enum _RemoveAction { cancel, hideOnly, deleteFile }
