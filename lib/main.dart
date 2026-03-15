import 'dart:io' show File;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'database/database_helper.dart';
import 'database/database_helper_io.dart'
    if (dart.library.html) 'database/database_helper_web.dart';
import 'screens/setup_screen.dart';
import 'screens/weekly_checkin_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Close the database cleanly when the app exits so SQLite checkpoints the WAL.
  // Kept as a top-level variable so it isn't garbage collected.
  AppLifecycleListener(
    onExitRequested: () async {
      await DatabaseHelper.close();
      return AppExitResponse.exit;
    },
  );

  runApp(const HamNetManagerApp());
}

class HamNetManagerApp extends StatelessWidget {
  const HamNetManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
