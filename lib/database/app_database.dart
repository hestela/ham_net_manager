import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await _createSchema();
        },
        onUpgrade: (m, from, to) async {
          await _runMigrations(from, to);
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _createSchema() async {
    await customStatement('''
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

    await customStatement('''
      CREATE TABLE weeks (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        week_ending DATE NOT NULL UNIQUE
      )
    ''');

    await customStatement('''
      CREATE TABLE checkins (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        person_id     INTEGER NOT NULL REFERENCES persons(id),
        week_id       INTEGER NOT NULL REFERENCES weeks(id),
        checked_in_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        notes         TEXT,
        UNIQUE(person_id, week_id)
      )
    ''');

    await customStatement('''
      CREATE TABLE checkin_methods (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        checkin_id INTEGER NOT NULL REFERENCES checkins(id) ON DELETE CASCADE,
        method     TEXT NOT NULL,
        details    TEXT
      )
    ''');

    await customStatement('''
      CREATE TABLE net_roles (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        week_id      INTEGER NOT NULL REFERENCES weeks(id),
        day_of_week  TEXT NOT NULL,
        role         TEXT NOT NULL,
        person_id    INTEGER REFERENCES persons(id),
        display_name TEXT
      )
    ''');

    await customStatement('''
      CREATE TABLE cities (
        id   INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');

    await customStatement('''
      CREATE TABLE neighborhoods (
        id   INTEGER PRIMARY KEY AUTOINCREMENT,
        city TEXT NOT NULL,
        name TEXT NOT NULL,
        UNIQUE(city, name)
      )
    ''');

    await customStatement('''
      CREATE TABLE settings (
        key   TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  Future<void> _runMigrations(int from, int to) async {
    if (from < 2) {
      await customStatement(
          'ALTER TABLE net_roles ADD COLUMN display_name TEXT');
    }
    if (from < 3) {
      await customStatement(
          'ALTER TABLE persons ADD COLUMN is_active BOOLEAN DEFAULT 1');
    }
    if (from < 4) {
      await customStatement(
          'CREATE TABLE IF NOT EXISTS cities (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)');
    }
    if (from < 5) {
      await customStatement('''
        CREATE TABLE IF NOT EXISTS neighborhoods (
          id      INTEGER PRIMARY KEY AUTOINCREMENT,
          city    TEXT NOT NULL,
          name    TEXT NOT NULL,
          UNIQUE(city, name)
        )
      ''');
    }
    if (from < 6) {
      await customStatement('''
        CREATE TABLE IF NOT EXISTS settings (
          key   TEXT PRIMARY KEY,
          value TEXT
        )
      ''');
    }
  }
}

/// Opens (or creates) a drift database.
/// On desktop: [filePath] is the absolute path to the .sqlite file.
/// On web: [name] is used as the OPFS key; [filePath] is ignored.
AppDatabase openAppDatabase({required String name, String? filePath}) {
  return AppDatabase(driftDatabase(
    name: name,
    native: filePath != null
        ? DriftNativeOptions(databasePath: () async => filePath)
        : null,
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  ));
}
