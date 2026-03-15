import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../database/database_helper.dart';
import '../models/person.dart';

/// Valid check-in methods in display order.
const kCheckInMethods = ['repeater', 'simplex', 'dmr', 'gmrs', 'packet', 'hf'];

/// Methods that count toward the ham-radio-only (non-GMRS) unique total.
const kHamOnlyMethods = ['repeater', 'simplex', 'dmr', 'packet', 'hf'];

const kMethodLabels = {
  'repeater': 'Repeater\nCheck-In',
  'simplex': 'Simplex\nCheck-In',
  'dmr': 'Active on\nDMR',
  'gmrs': 'GMRS Net\nCheck-in',
  'packet': 'Packet\nCheck-In',
  'hf': 'Active\non HF',
};

const kNetRoleDay = 'today';
const kNetRoles = ['net_control', 'scribe'];
const kNetRoleLabels = {'net_control': 'Net Control:', 'scribe': 'Scribe:'};

class WeekSummary {
  const WeekSummary({
    required this.weekEnding,
    required this.hamOnlyMembers,
    required this.allMembers,
    required this.hamOnlyGuests,
    required this.allGuests,
  });
  final DateTime weekEnding;
  final int hamOnlyMembers;
  final int allMembers;
  final int hamOnlyGuests;
  final int allGuests;
}

class NetRepository {
  static AppDatabase get _db => DatabaseHelper.db;

  // ── Variable helper ────────────────────────────────────────────────────────

  static List<Variable<Object>> _vars(List<dynamic>? args) {
    if (args == null) return const [];
    return args.map<Variable<Object>>((a) {
      if (a == null) return const Variable(null);
      if (a is int) return Variable<int>(a);
      if (a is double) return Variable<double>(a);
      if (a is bool) return Variable<bool>(a);
      return Variable<String>(a.toString());
    }).toList();
  }

  // ── Persons ────────────────────────────────────────────────────────────────

  /// Loads persons ordered by name. Pass [activeOnly: false] to include
  /// inactive persons (used by the manage-members screen).
  static Future<List<Person>> loadPersons({bool activeOnly = true}) async {
    final sql = 'SELECT * FROM persons'
        '${activeOnly ? ' WHERE is_active = 1' : ''}'
        ' ORDER BY last_name COLLATE NOCASE, first_name COLLATE NOCASE';
    final List<QueryRow> rows = await _db.customSelect(sql).get();
    return rows.map((r) => Person.fromMap(r.data)).toList();
  }

  /// Inserts a new person and returns the assigned id.
  static Future<int> insertPerson(Person person) async {
    final Map<String, dynamic> map = person.toMap();
    final String keys = map.keys.join(', ');
    final String placeholders = map.keys.map((_) => '?').join(', ');
    return _db.customInsert(
      'INSERT INTO persons ($keys) VALUES ($placeholders)',
      variables: _vars(map.values.toList()),
    );
  }

  /// Updates all fields of an existing person (matched by id).
  static Future<void> updatePerson(Person person) async {
    final Map<String, dynamic> map = person.toMap();
    final String setClause = map.keys.map((k) => '$k = ?').join(', ');
    await _db.customUpdate(
      'UPDATE persons SET $setClause WHERE id = ?',
      variables: _vars([...map.values, person.id]),
    );
  }

  /// Toggles the is_active flag without touching any other fields.
  static Future<void> setPersonActive(int personId, bool active) async {
    await _db.customUpdate(
      'UPDATE persons SET is_active = ? WHERE id = ?',
      variables: _vars([if (active) 1 else 0, personId]),
    );
  }

  /// Permanently deletes a person and all their check-in records.
  static Future<void> deletePerson(int personId) async {
    final List<QueryRow> checkinRows = await _db
        .customSelect(
          'SELECT id FROM checkins WHERE person_id = ?',
          variables: _vars([personId]),
        )
        .get();
    for (final row in checkinRows) {
      await _db.customUpdate(
        'DELETE FROM checkin_methods WHERE checkin_id = ?',
        variables: _vars([row.data['id']]),
      );
    }
    await _db.customUpdate(
      'DELETE FROM checkins WHERE person_id = ?',
      variables: _vars([personId]),
    );
    await _db.customUpdate(
      'UPDATE net_roles SET person_id = NULL WHERE person_id = ?',
      variables: _vars([personId]),
    );
    await _db.customUpdate(
      'DELETE FROM persons WHERE id = ?',
      variables: _vars([personId]),
    );
  }

  /// Bulk-import persons. Skips rows whose FCC callsign already exists.
  /// Also auto-creates any cities and neighborhoods not yet in the database.
  /// Returns the number of newly inserted rows.
  static Future<int> importPersons(List<Person> persons) async {
    // Auto-create cities
    final Set<String> existingCities = (await loadCities()).toSet();
    for (final person in persons) {
      if (person.city != null && !existingCities.contains(person.city)) {
        await insertCity(person.city!);
        existingCities.add(person.city!);
      }
    }
    // Auto-create neighborhoods
    for (final person in persons) {
      if (person.city != null && person.neighborhood != null) {
        await insertNeighborhood(person.city!, person.neighborhood!);
      }
    }
    // Insert persons, skipping FCC-callsign duplicates
    var imported = 0;
    for (final person in persons) {
      if (person.fccCallsign != null && person.fccCallsign!.isNotEmpty) {
        final List<QueryRow> existing = await _db
            .customSelect(
              'SELECT id FROM persons WHERE fcc_callsign = ?',
              variables: _vars([person.fccCallsign]),
            )
            .get();
        if (existing.isNotEmpty) continue;
      }
      await insertPerson(person);
      imported++;
    }
    return imported;
  }

  // ── Cities ─────────────────────────────────────────────────────────────────

  static Future<List<String>> loadCities() async {
    final List<QueryRow> rows = await _db
        .customSelect('SELECT name FROM cities ORDER BY name COLLATE NOCASE')
        .get();
    return rows.map((r) => r.data['name'] as String).toList();
  }

  /// Inserts a city. Silently does nothing if the name already exists.
  static Future<void> insertCity(String name) async {
    await _db.customInsert(
      'INSERT OR IGNORE INTO cities (name) VALUES (?)',
      variables: _vars([name.trim()]),
    );
  }

  static Future<void> deleteCity(String name) async {
    await _db.customUpdate(
      'DELETE FROM neighborhoods WHERE city = ?',
      variables: _vars([name]),
    );
    await _db.customUpdate(
      'DELETE FROM cities WHERE name = ?',
      variables: _vars([name]),
    );
  }

  // ── Neighborhoods ──────────────────────────────────────────────────────────

  /// Returns neighborhoods for a given city, sorted by name.
  static Future<List<String>> loadNeighborhoods(String city) async {
    final List<QueryRow> rows = await _db
        .customSelect(
          'SELECT name FROM neighborhoods WHERE city = ? ORDER BY name COLLATE NOCASE',
          variables: _vars([city]),
        )
        .get();
    return rows.map((r) => r.data['name'] as String).toList();
  }

  static Future<void> insertNeighborhood(String city, String name) async {
    await _db.customInsert(
      'INSERT OR IGNORE INTO neighborhoods (city, name) VALUES (?, ?)',
      variables: _vars([city, name.trim()]),
    );
  }

  static Future<void> deleteNeighborhood(String city, String name) async {
    await _db.customUpdate(
      'DELETE FROM neighborhoods WHERE city = ? AND name = ?',
      variables: _vars([city, name]),
    );
  }

  // ── Weeks ──────────────────────────────────────────────────────────────────

  static Future<int> findOrCreateWeek(DateTime weekEnding) async {
    final String dateStr = _dateStr(weekEnding);
    final List<QueryRow> existing = await _db
        .customSelect(
          'SELECT id FROM weeks WHERE week_ending = ?',
          variables: _vars([dateStr]),
        )
        .get();
    if (existing.isNotEmpty) return existing.first.data['id'] as int;
    return _db.customInsert(
      'INSERT INTO weeks (week_ending) VALUES (?)',
      variables: _vars([dateStr]),
    );
  }

  /// Returns the set of dates (normalized to midnight) that have at least
  /// one check-in recorded.
  static Future<Set<DateTime>> loadDatesWithCheckins() async {
    final List<QueryRow> rows = await _db.customSelect('''
      SELECT DISTINCT w.week_ending
      FROM weeks w
      WHERE EXISTS (SELECT 1 FROM checkins c WHERE c.week_id = w.id)
    ''').get();
    return {
      for (final row in rows)
        DateTime.parse(row.data['week_ending'] as String),
    };
  }

  // ── Check-ins ──────────────────────────────────────────────────────────────

  /// Returns methods for the given week.
  /// methods: personId → set of checked method names
  static Future<Map<int, Set<String>>> loadCheckins(int weekId) async {
    final List<QueryRow> rows = await _db.customSelect('''
      SELECT c.person_id, cm.method
      FROM checkins c
      JOIN checkin_methods cm ON cm.checkin_id = c.id
      WHERE c.week_id = ?
    ''', variables: _vars([weekId])).get();

    final methods = <int, Set<String>>{};
    for (final row in rows) {
      final pid = row.data['person_id'] as int;
      final method = row.data['method'] as String;
      methods.putIfAbsent(pid, () => {}).add(method);
    }
    return methods;
  }

  /// Adds or removes [method] for [personId] in [weekId].
  /// Also creates/deletes the parent checkins row as needed.
  static Future<void> setMethod(
      int weekId, int personId, String method, bool checked) async {
    if (checked) {
      final int checkinId = await _ensureCheckin(weekId, personId);
      final List<QueryRow> existing = await _db
          .customSelect(
            'SELECT id FROM checkin_methods WHERE checkin_id = ? AND method = ?',
            variables: _vars([checkinId, method]),
          )
          .get();
      if (existing.isEmpty) {
        await _db.customInsert(
          'INSERT INTO checkin_methods (checkin_id, method) VALUES (?, ?)',
          variables: _vars([checkinId, method]),
        );
      }
    } else {
      final List<QueryRow> checkinRows = await _db
          .customSelect(
            'SELECT id FROM checkins WHERE person_id = ? AND week_id = ?',
            variables: _vars([personId, weekId]),
          )
          .get();
      if (checkinRows.isEmpty) return;
      final checkinId = checkinRows.first.data['id'] as int;
      await _db.customUpdate(
        'DELETE FROM checkin_methods WHERE checkin_id = ? AND method = ?',
        variables: _vars([checkinId, method]),
      );
      // Remove checkin row if no methods remain.
      final List<QueryRow> remaining = await _db
          .customSelect(
            'SELECT id FROM checkin_methods WHERE checkin_id = ?',
            variables: _vars([checkinId]),
          )
          .get();
      if (remaining.isEmpty) {
        await _db.customUpdate(
          'DELETE FROM checkins WHERE id = ?',
          variables: _vars([checkinId]),
        );
      }
    }
  }

  // ── Net roles ──────────────────────────────────────────────────────────────

  /// For each day+role combination, returns the most recent assignment
  /// from any week before [currentWeekId] where a person was actually set.
  static Future<Map<String, Map<String, dynamic>>> loadPreviousNetRoles(
      int currentWeekId) async {
    final result = <String, Map<String, dynamic>>{};
    for (final String role in kNetRoles) {
      final List<QueryRow> rows = await _db.customSelect('''
        SELECT nr.day_of_week, nr.role, nr.person_id, nr.display_name,
               p.first_name, p.last_name, p.fcc_callsign
        FROM net_roles nr
        LEFT JOIN persons p ON p.id = nr.person_id
        WHERE nr.week_id < ?
          AND nr.day_of_week = ?
          AND nr.role = ?
          AND (nr.person_id IS NOT NULL
               OR (nr.display_name IS NOT NULL AND nr.display_name != ''))
        ORDER BY nr.week_id DESC
        LIMIT 1
      ''', variables: _vars([currentWeekId, kNetRoleDay, role])).get();
      if (rows.isNotEmpty) {
        result['$kNetRoleDay|$role'] =
            Map<String, dynamic>.from(rows.first.data);
      }
    }
    return result;
  }

  /// Returns Map keyed by '$dayOfWeek|$role'.
  /// Each value is the raw DB row (includes person fields via JOIN).
  static Future<Map<String, Map<String, dynamic>>> loadNetRoles(
      int weekId) async {
    final List<QueryRow> rows = await _db.customSelect('''
      SELECT nr.day_of_week, nr.role, nr.person_id, nr.display_name,
             p.first_name, p.last_name, p.fcc_callsign
      FROM net_roles nr
      LEFT JOIN persons p ON p.id = nr.person_id
      WHERE nr.week_id = ?
    ''', variables: _vars([weekId])).get();

    return {
      for (final row in rows)
        '${row.data['day_of_week']}|${row.data['role']}':
            Map<String, dynamic>.from(row.data),
    };
  }

  static Future<void> setNetRole(
    int weekId,
    String dayOfWeek,
    String role, {
    int? personId,
    String? displayName,
  }) async {
    final List<QueryRow> existing = await _db
        .customSelect(
          'SELECT id FROM net_roles WHERE week_id = ? AND day_of_week = ? AND role = ?',
          variables: _vars([weekId, dayOfWeek, role]),
        )
        .get();

    if (existing.isEmpty) {
      if (personId == null && (displayName == null || displayName.isEmpty)) {
        return;
      }
      await _db.customInsert(
        'INSERT INTO net_roles (week_id, day_of_week, role, person_id, display_name) VALUES (?, ?, ?, ?, ?)',
        variables: _vars([weekId, dayOfWeek, role, personId, displayName]),
      );
    } else {
      final id = existing.first.data['id'] as int;
      if (personId == null && (displayName == null || displayName.isEmpty)) {
        await _db.customUpdate(
          'DELETE FROM net_roles WHERE id = ?',
          variables: _vars([id]),
        );
      } else {
        await _db.customUpdate(
          'UPDATE net_roles SET person_id = ?, display_name = ? WHERE id = ?',
          variables: _vars([personId, displayName, id]),
        );
      }
    }
  }

  // ── Reports ────────────────────────────────────────────────────────────────

  /// Returns one [WeekSummary] per week in [start]..[end] that has checkins.
  static Future<List<WeekSummary>> loadWeekSummaries(
      DateTime start, DateTime end) async {
    final List<QueryRow> rows = await _db.customSelect('''
      SELECT w.week_ending, p.is_member, c.id AS checkin_id, cm.method
      FROM weeks w
      JOIN checkins c ON c.week_id = w.id
      JOIN checkin_methods cm ON cm.checkin_id = c.id
      JOIN persons p ON p.id = c.person_id
      WHERE w.week_ending >= ? AND w.week_ending <= ?
      ORDER BY w.week_ending ASC
    ''', variables: _vars([_dateStr(start), _dateStr(end)])).get();

    // Group: weekEnding → checkinId → {isMember, methods}
    final Map<String, Map<int, ({bool isMember, Set<String> methods})>> byWeek =
        {};
    for (final row in rows) {
      final weekEnding = row.data['week_ending'] as String;
      final checkinId = row.data['checkin_id'] as int;
      final isMember = (row.data['is_member'] as int) == 1;
      final method = row.data['method'] as String;
      byWeek.putIfAbsent(weekEnding, () => {});
      byWeek[weekEnding]!.putIfAbsent(
          checkinId, () => (isMember: isMember, methods: {}));
      byWeek[weekEnding]![checkinId]!.methods.add(method);
    }

    final summaries = <WeekSummary>[];
    for (final MapEntry<String, Map<int, ({bool isMember, Set<String> methods})>> entry
        in byWeek.entries) {
      var hamOnlyMembers = 0;
      var allMembers = 0;
      var hamOnlyGuests = 0;
      var allGuests = 0;
      for (final ({bool isMember, Set<String> methods}) ci
          in entry.value.values) {
        final bool hasAny = ci.methods.isNotEmpty;
        final bool hasHamOnly =
            ci.methods.any((m) => kHamOnlyMethods.contains(m));
        if (ci.isMember) {
          if (hasAny) allMembers++;
          if (hasHamOnly) hamOnlyMembers++;
        } else {
          if (hasAny) allGuests++;
          if (hasHamOnly) hamOnlyGuests++;
        }
      }
      summaries.add(WeekSummary(
        weekEnding: DateTime.parse(entry.key),
        hamOnlyMembers: hamOnlyMembers,
        allMembers: allMembers,
        hamOnlyGuests: hamOnlyGuests,
        allGuests: allGuests,
      ));
    }
    return summaries;
  }

  /// Returns one row per (person, week) in [start]..[end].
  /// Each map has a 'methods' key with comma-separated method names.
  static Future<List<Map<String, dynamic>>> loadCheckinsForRange(
      DateTime start, DateTime end) async {
    final List<QueryRow> rows = await _db.customSelect('''
      SELECT w.week_ending,
             p.first_name, p.last_name, p.fcc_callsign, p.gmrs_callsign,
             p.is_member, p.city, p.neighborhood,
             GROUP_CONCAT(cm.method) AS methods
      FROM weeks w
      JOIN checkins c ON c.week_id = w.id
      JOIN checkin_methods cm ON cm.checkin_id = c.id
      JOIN persons p ON p.id = c.person_id
      WHERE w.week_ending >= ? AND w.week_ending <= ?
      GROUP BY w.week_ending, p.id
      ORDER BY w.week_ending ASC,
               p.last_name COLLATE NOCASE ASC,
               p.first_name COLLATE NOCASE ASC
    ''', variables: _vars([_dateStr(start), _dateStr(end)])).get();
    return rows.map((r) => Map<String, dynamic>.from(r.data)).toList();
  }

  // ── Sync export / import ───────────────────────────────────────────────────

  /// Serializes all user data to a JSON-compatible map.
  /// The `settings` table is intentionally excluded (local config only).
  static Future<Map<String, dynamic>> exportAllData() async {
    Future<List<Map<String, dynamic>>> query(String sql) async {
      final List<QueryRow> rows = await _db.customSelect(sql).get();
      return rows.map((r) => Map<String, dynamic>.from(r.data)).toList();
    }

    return {
      'net_name': DatabaseHelper.currentCity,
      'cities': await query('SELECT * FROM cities'),
      'neighborhoods': await query('SELECT * FROM neighborhoods'),
      'persons': await query('SELECT * FROM persons'),
      'weeks': await query('SELECT * FROM weeks'),
      'checkins': await query('SELECT * FROM checkins'),
      'checkin_methods': await query('SELECT * FROM checkin_methods'),
      'net_roles': await query('SELECT * FROM net_roles'),
    };
  }

  /// Upserts all records from a previously exported snapshot.
  /// Processes tables in FK-safe order.
  static Future<void> importAllData(Map<String, dynamic> data) async {
    Future<void> upsertAll(String table, List<dynamic> rows) async {
      for (final dynamic row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final String keys = map.keys.join(', ');
        final String placeholders = map.keys.map((_) => '?').join(', ');
        await _db.customInsert(
          'INSERT OR REPLACE INTO $table ($keys) VALUES ($placeholders)',
          variables: _vars(map.values.toList()),
        );
      }
    }

    final List<dynamic> cities = (data['cities'] as List?) ?? [];
    final List<dynamic> neighborhoods = (data['neighborhoods'] as List?) ?? [];
    final List<dynamic> persons = (data['persons'] as List?) ?? [];
    final List<dynamic> weeks = (data['weeks'] as List?) ?? [];
    final List<dynamic> checkins = (data['checkins'] as List?) ?? [];
    final List<dynamic> checkinMethods =
        (data['checkin_methods'] as List?) ?? [];
    final List<dynamic> netRoles = (data['net_roles'] as List?) ?? [];

    await upsertAll('cities', cities);
    await upsertAll('neighborhoods', neighborhoods);
    await upsertAll('persons', persons);
    await upsertAll('weeks', weeks);
    await upsertAll('checkins', checkins);
    await upsertAll('checkin_methods', checkinMethods);
    await upsertAll('net_roles', netRoles);

    final netName = data['net_name'] as String?;
    if (netName != null && netName.isNotEmpty) {
      await DatabaseHelper.setNetName(netName);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Future<int> _ensureCheckin(int weekId, int personId) async {
    final List<QueryRow> existing = await _db
        .customSelect(
          'SELECT id FROM checkins WHERE person_id = ? AND week_id = ?',
          variables: _vars([personId, weekId]),
        )
        .get();
    if (existing.isNotEmpty) return existing.first.data['id'] as int;
    return _db.customInsert(
      'INSERT INTO checkins (person_id, week_id) VALUES (?, ?)',
      variables: _vars([personId, weekId]),
    );
  }

  static String _dateStr(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
