import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _hiddenPrefKey = 'hidden_databases';
const _recentDatabasesPrefKey = 'recent_databases';

Future<String> platformGetAppDirectoryPath() async {
  final docsDir = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docsDir.path, 'ham_net_manager'));
  await dir.create(recursive: true);
  return dir.path;
}

Future<List<String>> platformFindExistingDatabases() async {
  final dirPath = await platformGetAppDirectoryPath();
  final dir = Directory(dirPath);
  final prefs = await SharedPreferences.getInstance();
  final hidden = (prefs.getStringList(_hiddenPrefKey) ?? []).toSet();

  final appDatabases = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sqlite') && !hidden.contains(f.path))
      .map((f) => f.path)
      .toList();

  final recentPaths =
      (prefs.getStringList(_recentDatabasesPrefKey) ?? []).toSet();
  final existingRecentPaths = <String>[];
  for (final path in recentPaths) {
    if (await File(path).exists()) {
      existingRecentPaths.add(path);
    }
  }

  final allPaths = {...appDatabases, ...existingRecentPaths}.toList();
  allPaths.sort();
  return allPaths;
}

Future<void> platformRemoveDatabase(String path,
    {bool deleteFile = false}) async {
  if (deleteFile) {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } else {
    final prefs = await SharedPreferences.getInstance();
    final hidden = (prefs.getStringList(_hiddenPrefKey) ?? []).toSet()
      ..add(path);
    await prefs.setStringList(_hiddenPrefKey, hidden.toList());
  }
}

Future<void> platformAddRecentDatabase(String path) async {
  final prefs = await SharedPreferences.getInstance();
  final recent = (prefs.getStringList(_recentDatabasesPrefKey) ?? []).toSet()
    ..add(path);
  await prefs.setStringList(_recentDatabasesPrefKey, recent.toList());
}
