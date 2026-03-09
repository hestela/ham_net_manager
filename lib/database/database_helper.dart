import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  static Database? _db;
  static String? _dbPath;
  static String? _currentCity;

  static Database get db {
    if (_db == null) throw StateError('Database not initialized. Call initialize() first.');
    return _db!;
  }

  /// Absolute path to the open database file, suitable for copying/sharing.
  static String get dbPath => _dbPath ?? '';

  /// The name of the current city being managed.
  static String get currentCity => _currentCity ?? '';

  /// The directory where all ham_net_manager databases are stored.
  static Future<Directory> getAppDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, 'ham_net_manager'));
    await dir.create(recursive: true);
    return dir;
  }

  static const _hiddenPrefKey = 'hidden_databases';
  static const _recentDatabasesPrefKey = 'recent_databases';

  /// Returns paths of all .sqlite files in the app directory, excluding hidden ones,
  /// plus any recent databases opened from elsewhere (if they still exist).
  static Future<List<String>> findExistingDatabases() async {
    final dir = await getAppDirectory();
    final hidden = await getHiddenDatabases();

    // Get databases from the app directory
    final appDatabases = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sqlite') && !hidden.contains(f.path))
        .map((f) => f.path)
        .toList();

    // Get recently opened databases from prefs, but filter out ones that no longer exist
    final recentPaths = await _getRecentDatabases();
    final existingRecentPaths = <String>[];
    for (final path in recentPaths) {
      if (await File(path).exists()) {
        existingRecentPaths.add(path);
      }
    }

    // Combine and deduplicate
    final allPaths = {...appDatabases, ...existingRecentPaths}.toList();
    allPaths.sort();

    return allPaths;
  }

  /// Returns the set of database paths hidden from the list.
  static Future<Set<String>> getHiddenDatabases() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_hiddenPrefKey) ?? []).toSet();
  }

  /// Returns the set of recent database paths (opened from outside the app directory).
  static Future<Set<String>> _getRecentDatabases() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_recentDatabasesPrefKey) ?? []).toSet();
  }

  /// Adds [path] to the recent databases list (for files opened from outside app directory).
  static Future<void> _addRecentDatabase(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final recent = (prefs.getStringList(_recentDatabasesPrefKey) ?? []).toSet()..add(path);
    await prefs.setStringList(_recentDatabasesPrefKey, recent.toList());
  }

  /// Hides [path] from the database list. If [deleteFile] is true, also
  /// deletes the file from disk.
  static Future<void> removeDatabase(String path, {bool deleteFile = false}) async {
    if (deleteFile) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } else {
      final prefs = await SharedPreferences.getInstance();
      final hidden = (prefs.getStringList(_hiddenPrefKey) ?? []).toSet()..add(path);
      await prefs.setStringList(_hiddenPrefKey, hidden.toList());
    }
  }

  /// Creates (or opens) a database named after [netName].
  /// e.g. "Palo Alto" → "palo-alto-weekly-net.sqlite"
  static Future<Database> initialize(String netName) async {
    if (_db != null) return _db!;

    final dir = await getAppDirectory();
    final slug = _toSlug(netName);
    _dbPath = p.join(dir.path, '$slug-weekly-net.sqlite');

    _db = await databaseFactory.openDatabase(
      _dbPath!,
      options: OpenDatabaseOptions(
        version: 6,
        onConfigure: _onConfigure,
        onCreate: _createSchema,
        onUpgrade: _onUpgrade,
      ),
    );

    // Store the net name in settings on first creation.
    await _db!.insert(
      'settings',
      {'key': 'net_name', 'value': netName},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    _currentCity = netName;

    return _db!;
  }

  /// Opens an existing database file at [path] without re-running onCreate.
  static Future<Database> openExisting(String path) async {
    if (_db != null) return _db!;

    _dbPath = path;
    _db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onConfigure: _onConfigure,
        onUpgrade: _onUpgrade,
      ),
    );

    await _loadCurrentCity();

    // If this file is outside the app directory, save it to recent databases
    final dir = await getAppDirectory();
    if (!path.startsWith(dir.path)) {
      await _addRecentDatabase(path);
    }

    return _db!;
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
    _dbPath = null;
    _currentCity = null;
  }

  /// Loads the net name from the settings table.
  /// Falls back to extracting from the filename for pre-v6 databases.
  static Future<void> _loadCurrentCity() async {
    if (_db == null) return;

    try {
      final rows = await _db!.query('settings',
          where: 'key = ?', whereArgs: ['net_name'], limit: 1);
      if (rows.isNotEmpty) {
        _currentCity = rows.first['value'] as String?;
        return;
      }
    } catch (e) {
      // settings table might not exist yet (very old database)
    }

    // Fallback: extract from filename and persist it for next time.
    if (_dbPath != null) {
      final filename = p.basename(_dbPath!);
      if (filename.endsWith('-weekly-net.sqlite')) {
        final slug = filename.replaceAll('-weekly-net.sqlite', '');
        _currentCity = slug
            .split('-')
            .map((word) => word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
            .join(' ');
        // Persist so future opens don't need to fall back.
        try {
          await _db!.insert(
            'settings',
            {'key': 'net_name', 'value': _currentCity},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        } catch (_) {}
      }
    }
  }

  /// Updates the net name stored in settings.
  static Future<void> setNetName(String name) async {
    _currentCity = name;
    await _db!.insert(
      'settings',
      {'key': 'net_name', 'value': name},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Reads a value from the settings table. Returns null if not found.
  static Future<String?> getSetting(String key) async {
    final rows = await _db!.query('settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// Writes a value to the settings table (upsert).
  static Future<void> setSetting(String key, String value) async {
    await _db!.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------------------------------------------------------------------

  static Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE net_roles ADD COLUMN display_name TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE persons ADD COLUMN is_active BOOLEAN DEFAULT 1');
    }
    if (oldVersion < 4) {
      await db.execute(
          'CREATE TABLE IF NOT EXISTS cities (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS neighborhoods (
          id      INTEGER PRIMARY KEY AUTOINCREMENT,
          city    TEXT NOT NULL,
          name    TEXT NOT NULL,
          UNIQUE(city, name)
        )
      ''');
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS settings (
          key   TEXT PRIMARY KEY,
          value TEXT
        )
      ''');
      // Migrate: seed net_name from the filename slug (cities table is for
      // member cities, not the net name).
    }
  }

  static Future<void> _createSchema(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE persons (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        first_name    TEXT NOT NULL,
        last_name     TEXT,
        fcc_callsign  TEXT UNIQUE,
        gmrs_callsign TEXT,
        is_member     BOOLEAN DEFAULT FALSE,
        is_active     BOOLEAN DEFAULT 1,
        city          TEXT,
        neighborhood  TEXT,
        notes         TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE weeks (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        week_ending DATE NOT NULL UNIQUE
      )
    ''');

    batch.execute('''
      CREATE TABLE checkins (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        person_id     INTEGER NOT NULL REFERENCES persons(id),
        week_id       INTEGER NOT NULL REFERENCES weeks(id),
        checked_in_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        notes         TEXT,
        UNIQUE(person_id, week_id)
      )
    ''');

    // method is constrained in app code to:
    // 'repeater' | 'simplex' | 'dmr' | 'gmrs' | 'packet' | 'hf'
    batch.execute('''
      CREATE TABLE checkin_methods (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        checkin_id INTEGER NOT NULL REFERENCES checkins(id) ON DELETE CASCADE,
        method     TEXT NOT NULL,
        details    TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE net_roles (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        week_id      INTEGER NOT NULL REFERENCES weeks(id),
        day_of_week  TEXT NOT NULL,
        role         TEXT NOT NULL,
        person_id    INTEGER REFERENCES persons(id),
        display_name TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE cities (
        id   INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');

    batch.execute('''
      CREATE TABLE neighborhoods (
        id   INTEGER PRIMARY KEY AUTOINCREMENT,
        city TEXT NOT NULL,
        name TEXT NOT NULL,
        UNIQUE(city, name)
      )
    ''');

    batch.execute('''
      CREATE TABLE settings (
        key   TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await batch.commit(noResult: true);
  }

  static String _toSlug(String cityName) {
    return cityName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }
}
