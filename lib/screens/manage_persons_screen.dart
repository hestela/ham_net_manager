import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/person.dart';
import '../repositories/net_repository.dart';

class ManagePersonsScreen extends StatefulWidget {
  const ManagePersonsScreen({super.key});

  @override
  State<ManagePersonsScreen> createState() => _ManagePersonsScreenState();
}

class _ManagePersonsScreenState extends State<ManagePersonsScreen> {
  List<Person> _persons = [];
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final persons = await NetRepository.loadPersons(activeOnly: false);
    setState(() => _persons = persons);
  }

  Future<void> _addOrEdit(Person? existing) async {
    final result = await showDialog<Person>(
      context: context,
      builder: (_) => _PersonFormDialog(initial: existing),
    );
    if (result == null) return;

    if (result.id == 0) {
      await NetRepository.insertPerson(result);
    } else {
      await NetRepository.updatePerson(result);
    }
    await _load();
  }

  Future<void> _toggleActive(Person person) async {
    await NetRepository.setPersonActive(person.id, !person.isActive);
    await _load();
  }

  Future<void> _deletePerson(Person person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Member'),
        content: Text(
          'Permanently delete "${person.displayName}"?\n\n'
          'This will also remove all their check-in history and cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await NetRepository.deletePerson(person.id);
    await _load();
  }

  bool _matches(Person p) {
    if (_query.isEmpty) return true;
    return (p.firstName.toLowerCase().contains(_query)) ||
        (p.lastName?.toLowerCase().contains(_query) ?? false) ||
        (p.fccCallsign?.toLowerCase().contains(_query) ?? false) ||
        (p.gmrsCallsign?.toLowerCase().contains(_query) ?? false) ||
        (p.city?.toLowerCase().contains(_query) ?? false) ||
        (p.neighborhood?.toLowerCase().contains(_query) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _persons.where(_matches).toList();
    final active = filtered.where((p) => p.isActive).toList();
    final inactive = filtered.where((p) => !p.isActive).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Members'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'CSV format help',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const _CsvHelpDialog(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export to CSV',
            onPressed: _exportCsv,
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Import from CSV',
            onPressed: _importCsv,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEdit(null),
        tooltip: 'Add person',
        child: const Icon(Icons.person_add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
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
            child: _persons.isEmpty
                ? const Center(child: Text('No members yet. Tap + to add one.'))
                : filtered.isEmpty
                    ? const Center(child: Text('No members match your search.'))
                    : ListView(
                        children: [
                          ...active.map((p) => _buildTile(p)),
                          if (inactive.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                              child: Text(
                                'INACTIVE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            const Divider(height: 1),
                            ...inactive.map((p) => _buildTile(p)),
                          ],
                          const SizedBox(height: 80),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv() async {
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Export members to CSV',
      fileName: 'members.csv',
      allowedExtensions: ['csv'],
      type: FileType.custom,
    );
    if (savePath == null) return;

    final rows = <List<dynamic>>[
      ['first_name', 'last_name', 'fcc_callsign', 'gmrs_callsign', 'member', 'city', 'neighborhood'],
      ..._persons.map((p) => [
            p.firstName,
            p.lastName ?? '',
            p.fccCallsign ?? '',
            p.gmrsCallsign ?? '',
            p.isMember ? 'yes' : '',
            p.city ?? '',
            p.neighborhood ?? '',
          ]),
    ];

    final csv = const CsvEncoder().convert(rows);
    await File(savePath).writeAsString(csv);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported ${_persons.length} members to $savePath')),
    );
  }

  Future<void> _importCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) return;

    final content = await File(path).readAsString();
    final rows = const CsvDecoder().convert(content);
    if (rows.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV has no data rows.')),
        );
      }
      return;
    }

    // Detect column mapping from header row
    final headers =
        rows.first.map((h) => h.toString().trim().toLowerCase()).toList();
    final mapping = _detectColumns(headers);
    if (!mapping.containsKey('first_name')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Could not find a "first name" column in the CSV header.')),
        );
      }
      return;
    }

    // Parse data rows into Person objects
    final persons = <Person>[];
    for (int i = 1; i < rows.length; i++) {
      final person = _rowToPerson(rows[i], mapping);
      if (person != null) persons.add(person);
    }

    if (persons.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid rows found in CSV.')),
        );
      }
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _ImportPreviewDialog(persons: persons, mapping: mapping),
    );
    if (confirmed != true) return;

    final count = await NetRepository.importPersons(persons);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported $count of ${persons.length} members.')),
    );
  }

  static Map<String, int> _detectColumns(List<String> headers) {
    const aliases = {
      'first_name': [
        'first_name', 'first name', 'firstname', 'first',
        'first name + initial', 'first name +initial',
      ],
      'last_name': ['last_name', 'last name', 'lastname', 'last'],
      'fcc_callsign': [
        'fcc_callsign', 'fcc callsign', 'callsign',
        'call_sign', 'call sign', 'call',
      ],
      'gmrs_callsign': [
        'gmrs_callsign', 'gmrs callsign', 'gmrs call sign', 'gmrs',
      ],
      'is_member': ['is_member', 'member'],
      'city': ['city'],
      'neighborhood': ['neighborhood', 'hood'],
    };

    final mapping = <String, int>{};
    for (int i = 0; i < headers.length; i++) {
      final h = headers[i];
      for (final entry in aliases.entries) {
        if (entry.value.contains(h) && !mapping.containsKey(entry.key)) {
          mapping[entry.key] = i;
          break;
        }
      }
    }
    return mapping;
  }

  static Person? _rowToPerson(
      List<dynamic> row, Map<String, int> mapping) {
    String? field(String name) {
      final idx = mapping[name];
      if (idx == null || idx >= row.length) return null;
      final val = row[idx].toString().trim();
      return val.isEmpty ? null : val;
    }

    var firstName = field('first_name');
    var lastName = field('last_name');
    if (firstName == null) return null;

    // If there's no last_name column, try to split "Bob H" into first + initial
    if (lastName == null && firstName.contains(' ')) {
      final lastSpace = firstName.lastIndexOf(' ');
      final tail = firstName.substring(lastSpace + 1).trim();
      if (tail.length <= 2) {
        lastName = tail;
        firstName = firstName.substring(0, lastSpace).trim();
      }
    }

    final memberStr = field('is_member')?.toLowerCase();
    final isMember = memberStr == 'x' ||
        memberStr == 'true' ||
        memberStr == '1' ||
        memberStr == 'yes';

    return Person(
      firstName: firstName,
      lastName: lastName,
      fccCallsign: field('fcc_callsign')?.toUpperCase(),
      gmrsCallsign: field('gmrs_callsign')?.toUpperCase(),
      isMember: isMember,
      city: field('city'),
      neighborhood: field('neighborhood'),
    );
  }

  Widget _buildTile(Person person) {
    return ListTile(
      leading: Icon(
        person.isMember ? Icons.star_rounded : Icons.person_outline,
        color: person.isActive
            ? (person.isMember ? Colors.amber.shade700 : Colors.grey)
            : Colors.grey.shade400,
      ),
      title: Text(
        [
          if (person.fccCallsign != null) person.fccCallsign!,
          person.displayName,
        ].join('  —  '),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: person.isActive ? null : Colors.grey,
        ),
      ),
      subtitle: Text(
        [
          if (person.isMember) 'Member',
          if (person.gmrsCallsign != null) 'GMRS: ${person.gmrsCallsign}',
          if (person.city != null) person.city!,
        ].join(' · '),
        style: TextStyle(color: person.isActive ? null : Colors.grey),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              person.isActive ? Icons.visibility : Icons.visibility_off,
              color: person.isActive ? null : Colors.grey,
            ),
            tooltip: person.isActive
                ? 'Hide from weekly check-in list'
                : 'Show in weekly check-in list',
            onPressed: () => _toggleActive(person),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => _addOrEdit(person),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
            tooltip: 'Delete member',
            onPressed: () => _deletePerson(person),
          ),
        ],
      ),
    );
  }
}

// ── Person form dialog ────────────────────────────────────────────────────────

class _PersonFormDialog extends StatefulWidget {
  final Person? initial;
  const _PersonFormDialog({this.initial});

  @override
  State<_PersonFormDialog> createState() => _PersonFormDialogState();
}

class _PersonFormDialogState extends State<_PersonFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _firstName =
      TextEditingController(text: widget.initial?.firstName ?? '');
  late final _lastName =
      TextEditingController(text: widget.initial?.lastName ?? '');
  late final _fccCall =
      TextEditingController(text: widget.initial?.fccCallsign ?? '');
  late final _gmrsCall =
      TextEditingController(text: widget.initial?.gmrsCallsign ?? '');
  late bool _isMember = widget.initial?.isMember ?? false;
  List<String> _cities = [];
  List<String> _neighborhoods = [];
  String? _selectedCity;
  String? _selectedNeighborhood;

  @override
  void initState() {
    super.initState();
    // Don't set _selectedCity/_selectedNeighborhood until their respective
    // lists are loaded — otherwise the dropdowns assert on a value not in items.
    _loadCities(
      initial: widget.initial?.city,
      initialNeighborhood: widget.initial?.neighborhood,
    );
  }

  Future<void> _loadCities({String? initial, String? initialNeighborhood}) async {
    final cities = await NetRepository.loadCities();
    setState(() {
      _cities = cities;
      if (initial != null && cities.contains(initial)) {
        _selectedCity = initial;
      } else if (_selectedCity != null && !cities.contains(_selectedCity)) {
        _selectedCity = null;
        _selectedNeighborhood = null;
        _neighborhoods = [];
      }
    });
    if (_selectedCity != null) {
      await _loadNeighborhoods(_selectedCity!, initial: initialNeighborhood);
    }
  }

  Future<void> _loadNeighborhoods(String city, {String? initial}) async {
    final hoods = await NetRepository.loadNeighborhoods(city);
    setState(() {
      _neighborhoods = hoods;
      if (initial != null) {
        _selectedNeighborhood = hoods.contains(initial) ? initial : null;
      } else if (_selectedNeighborhood != null &&
          !hoods.contains(_selectedNeighborhood)) {
        _selectedNeighborhood = null;
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_firstName, _lastName, _fccCall, _gmrsCall]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addCity() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add City'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'City name'),
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
              child: const Text('Add')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await NetRepository.insertCity(name);
    await _loadCities();
    setState(() {
      _selectedCity = name;
      _selectedNeighborhood = null;
      _neighborhoods = [];
    });
  }

  Future<void> _addNeighborhood() async {
    if (_selectedCity == null) return;
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Neighborhood to $_selectedCity'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Neighborhood name'),
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
              child: const Text('Add')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await NetRepository.insertNeighborhood(_selectedCity!, name);
    await _loadNeighborhoods(_selectedCity!);
    setState(() => _selectedNeighborhood = name);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    String? nonEmpty(String s) => s.trim().isEmpty ? null : s.trim();
    Navigator.pop(
      context,
      Person(
        id: widget.initial?.id ?? 0,
        firstName: _firstName.text.trim(),
        lastName: nonEmpty(_lastName.text),
        fccCallsign: nonEmpty(_fccCall.text.toUpperCase()),
        gmrsCallsign: nonEmpty(_gmrsCall.text.toUpperCase()),
        isMember: _isMember,
        isActive: widget.initial?.isActive ?? true,
        city: _selectedCity,
        neighborhood: _selectedNeighborhood,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.initial == null;
    return AlertDialog(
      title: Text(isNew ? 'Add Member' : 'Edit Member'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _firstName,
                  decoration:
                      const InputDecoration(labelText: 'First Name *'),
                  autofocus: true,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                  textCapitalization: TextCapitalization.words,
                  onFieldSubmitted: (_) => _save(),
                ),
                TextFormField(
                  controller: _lastName,
                  decoration: const InputDecoration(labelText: 'Last Name'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _fccCall,
                  decoration:
                      const InputDecoration(labelText: 'FCC Callsign'),
                  textCapitalization: TextCapitalization.characters,
                ),
                TextFormField(
                  controller: _gmrsCall,
                  decoration:
                      const InputDecoration(labelText: 'GMRS Callsign'),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  title: const Text('Member'),
                  value: _isMember,
                  onChanged: (v) => setState(() => _isMember = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                const SizedBox(height: 8),
                // City dropdown + add button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        key: ValueKey(_cities.length),
                        initialValue: _selectedCity,
                        decoration: const InputDecoration(labelText: 'City'),
                        items: [
                          const DropdownMenuItem<String?>(
                              value: null, child: Text('(none)')),
                          ..._cities.map((c) => DropdownMenuItem<String?>(
                                value: c,
                                child: Text(c),
                              )),
                        ],
                        onChanged: (v) {
                          setState(() {
                            _selectedCity = v;
                            _selectedNeighborhood = null;
                            _neighborhoods = [];
                          });
                          if (v != null) _loadNeighborhoods(v);
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: 'Add new city',
                      onPressed: _addCity,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Neighborhood dropdown + add button (only when a city is selected)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        key: ValueKey('hood_${_selectedCity}_${_neighborhoods.length}'),
                        initialValue: _selectedNeighborhood,
                        decoration: const InputDecoration(labelText: 'Neighborhood'),
                        items: [
                          const DropdownMenuItem<String?>(
                              value: null, child: Text('(none)')),
                          ..._neighborhoods.map((n) => DropdownMenuItem<String?>(
                                value: n,
                                child: Text(n),
                              )),
                        ],
                        onChanged: _selectedCity == null
                            ? null
                            : (v) => setState(() => _selectedNeighborhood = v),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: 'Add new neighborhood',
                      onPressed: _selectedCity == null ? null : _addNeighborhood,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

// ── Import preview dialog ─────────────────────────────────────────────────────

class _ImportPreviewDialog extends StatelessWidget {
  final List<Person> persons;
  final Map<String, int> mapping;

  const _ImportPreviewDialog({
    required this.persons,
    required this.mapping,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Import ${persons.length} Members'),
      content: SizedBox(
        width: 560,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detected columns: ${mapping.keys.join(', ')}',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 4),
            const Text(
              'Existing members with the same FCC callsign will be skipped.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    columnSpacing: 16,
                    columns: const [
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('FCC Call')),
                      DataColumn(label: Text('GMRS')),
                      DataColumn(label: Text('Member')),
                      DataColumn(label: Text('City')),
                      DataColumn(label: Text('Neighborhood')),
                    ],
                    rows: persons
                        .take(50)
                        .map((p) => DataRow(cells: [
                              DataCell(Text(p.displayName)),
                              DataCell(Text(p.fccCallsign ?? '')),
                              DataCell(Text(p.gmrsCallsign ?? '')),
                              DataCell(Text(p.isMember ? 'Yes' : '')),
                              DataCell(Text(p.city ?? '')),
                              DataCell(Text(p.neighborhood ?? '')),
                            ]))
                        .toList(),
                  ),
                ),
              ),
            ),
            if (persons.length > 50)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('… and ${persons.length - 50} more',
                    style: const TextStyle(color: Colors.black54)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import')),
      ],
    );
  }
}

// ── CSV format help dialog ────────────────────────────────────────────────────

class _CsvHelpDialog extends StatelessWidget {
  const _CsvHelpDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('CSV Import Format'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The first row must be a header row. Columns are matched '
                'by name (case-insensitive). Only "First Name" is required; '
                'all other columns are optional.',
              ),
              const SizedBox(height: 16),
              _section('Recognized column headers'),
              _headerRow('First Name', 'first_name, first, first name + initial'),
              _headerRow('Last Name', 'last_name, last'),
              _headerRow('FCC Callsign', 'fcc_callsign, callsign, call sign, call'),
              _headerRow('GMRS Callsign', 'gmrs_callsign, gmrs callsign, gmrs call sign, gmrs'),
              _headerRow('Member', 'is_member, member  (values: X, true, 1, yes)'),
              _headerRow('City', 'city'),
              _headerRow('Neighborhood', 'neighborhood, hood'),
              const SizedBox(height: 16),
              _section('Example'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const SelectableText(
                  'first_name,last_name,callsign,gmrs,member,city,neighborhood\n'
                  'Bob,Henderson,KD234,,X,Berkeley,\n'
                  'Ken,Davis,W4412A,,X,San Francisco,Buena Vista\n'
                  'Kelly,Adams,AF13KK,WBSK140,,Los Angeles,Civic Center',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'If there is no "Last Name" column but the "First Name" '
                'column contains values like "Bob H", the initial will be '
                'used as the last name automatically.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              const Text(
                'Duplicate members (matched by FCC callsign) are skipped. '
                'Any new cities found in the CSV are added automatically.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    );
  }

  static Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      );

  static Widget _headerRow(String field, String aliases) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(field,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: Text(aliases,
                  style:
                      const TextStyle(fontSize: 13, color: Colors.black54)),
            ),
          ],
        ),
      );
}
