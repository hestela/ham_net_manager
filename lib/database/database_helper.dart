import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_database.dart';
import 'database_helper_io.dart'
    if (dart.library.html) 'database_helper_web.dart';

class DatabaseHelper {
  static AppDatabase? _db;
  static String? _dbPath;
  static String? _currentCity;

  static AppDatabase get db {
    if (_db == null) {
      throw StateError('Database not initialized. Call initialize() first.');
    }
    return _db!;
  }

  /// Absolute path to the open database file (empty on web).
  static String get dbPath => _dbPath ?? '';

  /// The name of the current net being managed.
  static String get currentCity => _currentCity ?? '';

  static const _webDatabasesPrefKey = 'web_databases';

  /// Returns available databases.
  /// On desktop: .sqlite file paths from the app directory.
  /// On web: net names stored in SharedPreferences.
  static Future<List<String>> findExistingDatabases() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_webDatabasesPrefKey) ?? [];
    }
    return platformFindExistingDatabases();
  }

  /// Removes a database from the available list.
  /// On desktop: hides or deletes the .sqlite file.
  /// On web: removes the name from SharedPreferences (no file deletion).
  static Future<void> removeDatabase(String nameOrPath,
      {bool deleteFile = false}) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final list = (prefs.getStringList(_webDatabasesPrefKey) ?? []).toSet()
        ..remove(nameOrPath);
      await prefs.setStringList(_webDatabasesPrefKey, list.toList());
      return;
    }
    return platformRemoveDatabase(nameOrPath, deleteFile: deleteFile);
  }

  /// Creates (or opens) a database for [netName].
  /// On desktop: creates a .sqlite file named after the slug.
  /// On web: uses the slug as the OPFS key and saves [netName] in prefs.
  static Future<AppDatabase> initialize(String netName) async {
    if (_db != null) return _db!;

    final slug = _toSlug(netName);
    String? filePath;

    final dirPath = await platformGetAppDirectoryPath();
    if (dirPath.isNotEmpty) {
      filePath = p.join(dirPath, '$slug-weekly-net.sqlite');
      _dbPath = filePath;
    }

    _db = openAppDatabase(name: slug, filePath: filePath);

    // Store the net name in settings on first creation.
    await _db!.customInsert(
      "INSERT OR IGNORE INTO settings (key, value) VALUES ('net_name', ?)",
      variables: [Variable<String>(netName)],
    );
    _currentCity = netName;

    // On web, track the net name in SharedPreferences so it shows up next time.
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final list =
          (prefs.getStringList(_webDatabasesPrefKey) ?? []).toSet()..add(netName);
      await prefs.setStringList(_webDatabasesPrefKey, list.toList());
    }

    return _db!;
  }

  /// Opens an existing database.
  /// On desktop: [path] is an absolute file path.
  /// On web: [path] is the net name (as stored in SharedPreferences).
  static Future<AppDatabase> openExisting(String path) async {
    if (_db != null) return _db!;

    final dirPath = await platformGetAppDirectoryPath();

    if (!kIsWeb && dirPath.isNotEmpty) {
      // Desktop: use the file path.
      _dbPath = path;
      final slug = p.basenameWithoutExtension(path);
      _db = openAppDatabase(name: slug, filePath: path);

      // If outside app directory, save to recent databases list.
      if (!path.startsWith(dirPath)) {
        await platformAddRecentDatabase(path);
      }
    } else {
      // Web: path is the net name; slugify for the OPFS key.
      _db = openAppDatabase(name: _toSlug(path));
    }

    await _loadCurrentCity();
    return _db!;
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
    _dbPath = null;
    _currentCity = null;
  }

  /// Updates the net name stored in settings.
  static Future<void> setNetName(String name) async {
    _currentCity = name;
    await _db!.customInsert(
      "INSERT OR REPLACE INTO settings (key, value) VALUES ('net_name', ?)",
      variables: [Variable<String>(name)],
    );
  }

  /// Reads a value from the settings table. Returns null if not found.
  static Future<String?> getSetting(String key) async {
    final rows = await _db!
        .customSelect(
          'SELECT value FROM settings WHERE key = ? LIMIT 1',
          variables: [Variable<String>(key)],
        )
        .get();
    if (rows.isEmpty) return null;
    return rows.first.data['value'] as String?;
  }

  /// Writes a value to the settings table (upsert).
  static Future<void> setSetting(String key, String value) async {
    await _db!.customInsert(
      'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
      variables: [Variable<String>(key), Variable<String>(value)],
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static Future<void> _loadCurrentCity() async {
    if (_db == null) return;

    try {
      final rows = await _db!
          .customSelect(
            "SELECT value FROM settings WHERE key = 'net_name' LIMIT 1",
          )
          .get();
      if (rows.isNotEmpty) {
        _currentCity = rows.first.data['value'] as String?;
        return;
      }
    } catch (_) {
      // settings table might not exist yet (very old database)
    }

    // Fallback: extract from filename and persist.
    if (_dbPath != null) {
      final filename = p.basename(_dbPath!);
      if (filename.endsWith('-weekly-net.sqlite')) {
        final slug = filename.replaceAll('-weekly-net.sqlite', '');
        _currentCity = slug
            .split('-')
            .map((word) => word.isEmpty
                ? ''
                : '${word[0].toUpperCase()}${word.substring(1)}')
            .join(' ');
        try {
          await _db!.customInsert(
            "INSERT OR IGNORE INTO settings (key, value) VALUES ('net_name', ?)",
            variables: [Variable<String>(_currentCity!)],
          );
        } catch (_) {}
      }
    }
  }

  static String _toSlug(String cityName) {
    return cityName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }
}
