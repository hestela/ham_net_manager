import 'package:flutter/material.dart';

import '../repositories/net_repository.dart';

class ManageCitiesScreen extends StatefulWidget {
  const ManageCitiesScreen({super.key});

  @override
  State<ManageCitiesScreen> createState() => _ManageCitiesScreenState();
}

class _ManageCitiesScreenState extends State<ManageCitiesScreen> {
  List<String> _cities = [];
  // city → list of neighborhoods (loaded on expand)
  Map<String, List<String>> _neighborhoods = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cities = await NetRepository.loadCities();
    final neighborhoods = <String, List<String>>{};
    for (final city in cities) {
      neighborhoods[city] = await NetRepository.loadNeighborhoods(city);
    }
    setState(() {
      _cities = cities;
      _neighborhoods = neighborhoods;
    });
  }

  // ── City CRUD ─────────────────────────────────────────────────────────────

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
    await _load();
  }

  Future<void> _addMultipleCities() async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Multiple Cities'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'City names',
              hintText: 'One city per line',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            maxLines: 10,
            minLines: 5,
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add All')),
        ],
      ),
    );
    if (confirmed != true) return;
    final names = ctrl.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    for (final name in names) {
      await NetRepository.insertCity(name);
    }
    await _load();
  }

  Future<void> _deleteCity(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete City'),
        content: Text(
            'Remove "$name" and all its neighborhoods?\n'
            'This does not affect existing person records.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await NetRepository.deleteCity(name);
    await _load();
  }

  // ── Neighborhood CRUD ─────────────────────────────────────────────────────

  Future<void> _addNeighborhood(String city) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Neighborhood to $city'),
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
    await NetRepository.insertNeighborhood(city, name);
    await _load();
  }

  Future<void> _addMultipleNeighborhoods(String city) async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Multiple Neighborhoods to $city'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Neighborhood names',
              hintText: 'One neighborhood per line',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            maxLines: 10,
            minLines: 5,
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add All')),
        ],
      ),
    );
    if (confirmed != true) return;
    final names = ctrl.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    for (final name in names) {
      await NetRepository.insertNeighborhood(city, name);
    }
    await _load();
  }

  Future<void> _deleteNeighborhood(String city, String name) async {
    await NetRepository.deleteNeighborhood(city, name);
    await _load();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Cities & Neighborhoods'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'add_cities_bulk',
            onPressed: _addMultipleCities,
            tooltip: 'Paste list of cities',
            child: const Icon(Icons.format_list_bulleted_add),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'add_city',
            onPressed: _addCity,
            tooltip: 'Add city',
            child: const Icon(Icons.add),
          ),
        ],
      ),
      body: _cities.isEmpty
          ? const Center(child: Text('No cities yet. Tap + to add one.'))
          : ListView.builder(
              itemCount: _cities.length,
              itemBuilder: (ctx, i) => _buildCityTile(_cities[i]),
            ),
    );
  }

  Widget _buildCityTile(String city) {
    final hoods = _neighborhoods[city] ?? [];

    return ExpansionTile(
      leading: const Icon(Icons.location_city_outlined),
      title: Text(city, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: hoods.isEmpty
          ? const Text('No neighborhoods',
              style: TextStyle(fontSize: 12, color: Colors.grey))
          : Text('${hoods.length} neighborhood${hoods.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.format_list_bulleted_add, size: 20),
            tooltip: 'Paste list of neighborhoods',
            onPressed: () => _addMultipleNeighborhoods(city),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            tooltip: 'Add neighborhood',
            onPressed: () => _addNeighborhood(city),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Delete city',
            onPressed: () => _deleteCity(city),
          ),
        ],
      ),
      children: [
        if (hoods.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(72, 0, 16, 12),
            child: Text('No neighborhoods yet. Tap + to add one.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
        ...hoods.map((hood) => ListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              dense: true,
              title: Text(hood),
              trailing: IconButton(
                icon: Icon(Icons.remove_circle_outline,
                    size: 18, color: Colors.red.shade400),
                tooltip: 'Remove neighborhood',
                onPressed: () => _deleteNeighborhood(city, hood),
              ),
            )),
      ],
    );
  }
}
