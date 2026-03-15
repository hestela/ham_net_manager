import 'dart:io' show File;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'database/database_helper.dart';
import 'database/database_helper_io.dart'
    if (dart.library.html) 'database/database_helper_web.dart';
import 'screens/setup_screen.dart';
import 'screens/weekly_checkin_screen.dart';
import 'services/sync_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Close the database cleanly when the app exits so SQLite checkpoints the WAL.
  // Kept as a top-level variable so it isn't garbage collected.
  AppLifecycleListener(
    onExitRequested: () async {
      final bool hasPending = await SyncService.hasPendingSync();
      if (hasPending) {
        final ({String workerUrl, String apiToken}) config =
            await SyncService.getConfig();
        if (config.workerUrl.isNotEmpty && config.apiToken.isNotEmpty) {
          final BuildContext? ctx = navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            final bool? shouldExit =
                await _showExitSyncDialog(ctx, config);
            if (shouldExit == null) return AppExitResponse.cancel;
          }
        }
      }
      await DatabaseHelper.close();
      return AppExitResponse.exit;
    },
  );

  runApp(const HamNetManagerApp());
}

/// Shows the sync-before-exit dialog.
/// Returns true to exit, null to cancel.
Future<bool?> _showExitSyncDialog(
  BuildContext context,
  ({String workerUrl, String apiToken}) config,
) {
  return showDialog<bool?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ExitSyncDialog(config: config),
  );
}

class _ExitSyncDialog extends StatefulWidget {
  const _ExitSyncDialog({required this.config});
  final ({String workerUrl, String apiToken}) config;

  @override
  State<_ExitSyncDialog> createState() => _ExitSyncDialogState();
}

class _ExitSyncDialogState extends State<_ExitSyncDialog> {
  bool _syncing = false;
  String? _error;

  Future<void> _syncAndExit() async {
    setState(() {
      _syncing = true;
      _error = null;
    });
    try {
      await SyncService.push(
        workerUrl: widget.config.workerUrl,
        token: widget.config.apiToken,
      );
      await SyncService.clearPendingSync();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _syncing = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Unsynced Changes'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('You have unsynced changes. Sync before exiting?'),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              'Sync failed: $_error',
              style: TextStyle(
                  color: Colors.red.shade700, fontSize: 13),
            ),
          ],
        ],
      ),
      actions: _syncing
          ? [
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Exit Without Syncing'),
              ),
              FilledButton(
                onPressed: _syncAndExit,
                child: const Text('Sync & Exit'),
              ),
            ],
    );
  }
}

class HamNetManagerApp extends StatelessWidget {
  const HamNetManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Net Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const _StartupScreen(),
    );
  }
}

class _StartupScreen extends StatefulWidget {
  const _StartupScreen();

  @override
  State<_StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<_StartupScreen> {
  @override
  void initState() {
    super.initState();
    _startup();
  }

  Future<void> _startup() async {
    final List<String> existing = await DatabaseHelper.findExistingDatabases();

    // Ensure the last-opened database is in the list even if listSync missed it.
    String? lastOpened;
    if (!kIsWeb) {
      lastOpened = await platformGetLastOpened();
      if (lastOpened != null &&
          File(lastOpened).existsSync() &&
          !existing.contains(lastOpened)) {
        existing.add(lastOpened);
      }
    }

    if (!mounted) return;

    if (existing.length == 1) {
      // Single database — open automatically.
      await DatabaseHelper.openExisting(existing.first);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const WeeklyCheckinScreen()),
      );
    } else {
      // No databases, or multiple to choose from — show setup.
      // Pass the last-opened path so the setup screen can highlight it.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SetupScreen(
            existingPaths: existing,
            lastOpenedPath: lastOpened,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
