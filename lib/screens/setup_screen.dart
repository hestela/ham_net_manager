import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../database/database_helper.dart';
import '../utils/file_io.dart';
import 'weekly_checkin_screen.dart';

class SetupScreen extends StatefulWidget {

  const SetupScreen({super.key, this.existingPaths = const []});
  /// If non-empty, existing database paths (or names on web) are shown.
  final List<String> existingPaths;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _cityController = TextEditingController();
  bool _loading = false;
  String? _error;
  late List<String> _paths;

  @override
  void initState() {
    super.initState();
    _paths = List.of(widget.existingPaths);
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _removeDatabase(String path) async {
    final String displayName =
        kIsWeb ? path : p.basenameWithoutExtension(path);

    if (kIsWeb) {
      // On web: only remove from list, no file to delete.
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remove net'),
          content: Text('Remove "$displayName" from the list?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await DatabaseHelper.removeDatabase(path);
      setState(() => _paths.remove(path));
      return;
    }

    // Desktop: offer hide or delete.
    final _RemoveAction? result = await showDialog<_RemoveAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove database'),
        content: Text('What would you like to do with "$displayName"?'),
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

    if (result == null || result == _RemoveAction.cancel) return;

    await DatabaseHelper.removeDatabase(
      path,
      deleteFile: result == _RemoveAction.deleteFile,
    );
    setState(() => _paths.remove(path));
  }

  Future<void> _pickAndLoad() async {
    final String? path = await pickDatabaseFile();
    if (path == null) return;
    await _openExisting(path);
  }

  Future<void> _createNew() async {
    final String city = _cityController.text.trim();
    if (city.isEmpty) {
      setState(() => _error = 'Please enter a city or net name.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    await DatabaseHelper.initialize(city);
    _goHome();
  }

  Future<void> _openExisting(String path) async {
    setState(() => _loading = true);
    await DatabaseHelper.openExisting(path);
    _goHome();
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const WeeklyCheckinScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: _loading
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Net Manager',
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      if (_paths.isNotEmpty) ...[
                        Text(
                          'Open existing net',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        ..._paths.map(
                          (path) {
                            final String title = kIsWeb
                                ? path
                                : p.basenameWithoutExtension(path);
                            return ListTile(
                              leading: const Icon(Icons.storage),
                              title: Text(
                                title,
                                style:
                                    const TextStyle(fontFamily: 'monospace'),
                              ),
                              subtitle: kIsWeb
                                  ? null
                                  : Text(
                                      path,
                                      style: const TextStyle(fontSize: 11),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              onTap: () => _openExisting(path),
                              trailing: IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                tooltip: 'Remove',
                                onPressed: () => _removeDatabase(path),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 32),
                      ],
                      Text(
                        'Create new net database',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _cityController,
                        decoration: InputDecoration(
                          labelText: 'City / net name',
                          hintText: 'e.g. Palo Alto',
                          errorText: _error,
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _createNew(),
                        autofocus: _paths.isEmpty,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _createNew,
                        child: const Text('Create'),
                      ),
                      if (!kIsWeb) ...[
                        const Divider(height: 32),
                        Text(
                          'Load existing database',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _pickAndLoad,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Open database file...'),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

enum _RemoveAction { cancel, hideOnly, deleteFile }
