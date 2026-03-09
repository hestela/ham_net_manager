import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database/database_helper.dart';
import 'screens/weekly_checkin_screen.dart';
import 'screens/setup_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

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
    final existing = await DatabaseHelper.findExistingDatabases();

    if (!mounted) return;

    if (existing.length == 1) {
      // Single database found — open it automatically.
      await DatabaseHelper.openExisting(existing.first);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WeeklyCheckinScreen()),
      );
    } else {
      // No databases, or multiple to choose from — show setup.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => SetupScreen(existingPaths: existing)),
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
