import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../database/database_helper.dart';
import '../services/sync_service.dart' show RemoteNet, SyncService;
import '../utils/file_io.dart';
import 'weekly_checkin_screen.dart';

class SetupScreen extends StatefulWidget {

  const SetupScreen({super.key, this.existingPaths = const [], this.lastOpenedPath});
  /// If non-empty, existing database paths (or names on web) are shown.
  final List<String> existingPaths;
  /// If set, this path is highlighted as the most recently used database.
  final String? lastOpenedPath;

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

  Future<void> _importFromCloud() async {
    final urlCtrl = TextEditingController();
    final tokenCtrl = TextEditingController();
    String? dialogError;

    // Step 1: collect Worker URL + token
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Import from Cloud'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter the sync details from the machine that manages this net.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Worker URL',
                    hintText: 'https://ham-net-sync.yourname.workers.dev',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tokenCtrl,
                  decoration: const InputDecoration(
                    labelText: 'API Token',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 12),
                  Text(dialogError!,
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                          fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (urlCtrl.text.trim().isEmpty ||
                    tokenCtrl.text.trim().isEmpty) {
                  setDialogState(
                      () => dialogError = 'All fields are required.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Next'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final String workerUrl = urlCtrl.text.trim();
    final String token = tokenCtrl.text.trim();
    urlCtrl.dispose();
    tokenCtrl.dispose();

    setState(() => _loading = true);

    // Step 2: fetch available nets
    List<RemoteNet> nets;
    try {
      nets = await SyncService.fetchNets(workerUrl: workerUrl, token: token);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not connect: $e')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _loading = false);

    if (nets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No nets found on server. Push from the main machine first.')),
      );
      return;
    }

    // Step 3: if multiple nets, let user pick; if only one, use it directly
    RemoteNet chosen;
    if (nets.length == 1) {
      chosen = nets.first;
    } else {
      final RemoteNet? picked = await showDialog<RemoteNet>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Select Net'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: nets
                  .map((net) => ListTile(
                        title: Text(net.name),
                        subtitle: Text('Last updated: ${net.updatedAt}',
                            style: const TextStyle(fontSize: 11)),
                        onTap: () => Navigator.pop(ctx, net),
                      ))
                  .toList(),
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
      if (picked == null || !mounted) return;
      chosen = picked;
    }

    // Step 4: initialize DB with the chosen net's name, then pull
    setState(() => _loading = true);
    try {
      await DatabaseHelper.initialize(chosen.name);
      await SyncService.saveConfig(workerUrl, token);
      await SyncService.pull(
          workerUrl: workerUrl, token: token, slug: chosen.slug);
      _goHome();
    } catch (e) {
      await DatabaseHelper.close();
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    }
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const WeeklyCheckinScreen()),
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
                : SingleChildScrollView(
                    child: Column(
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
                            final isLastOpened =
                                path == widget.lastOpenedPath;
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
                                      isLastOpened
                                          ? 'Last opened'
                                          : path,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isLastOpened
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                            : null,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              tileColor: isLastOpened
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withValues(alpha: 0.3)
                                  : null,
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
                      const Divider(height: 32),
                      Text(
                        'Import from cloud',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _importFromCloud,
                        icon: const Icon(Icons.cloud_download),
                        label: const Text('Import from cloud...'),
                      ),
                    ],
                  ),
                ),
          ),
        ),
      ),
    );
  }
}

enum _RemoveAction { cancel, hideOnly, deleteFile }
