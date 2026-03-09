import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

class NetRepository {
  static Database get _db => DatabaseHelper.db;

  // ── Persons ──────────────────────────────────────────────────────────────

  /// Loads persons ordered by name. Pass [activeOnly: false] to include
  /// inactive persons (used by the manage-members screen).
  static Future<List<Person>> loadPersons({bool activeOnly = true}) async {
    final rows = await _db.query(
      'persons',
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'last_name COLLATE NOCASE, first_name COLLATE NOCASE',
    );
    return rows.map(Person.fromMap).toList();
  }

  /// Inserts a new person and returns the assigned id.
  static Future<int> insertPerson(Person person) =>
      _db.insert('persons', person.toMap());

  /// Updates all fields of an existing person (matched by id).
  static Future<void> updatePerson(Person person) => _db.update(
        'persons',
        person.toMap(),
        where: 'id = ?',
        whereArgs: [person.id],
      );

  /// Toggles the is_active flag without touching any other fields.
  static Future<void> setPersonActive(int personId, bool active) =>
      _db.update(
        'persons',
        {'is_active': active ? 1 : 0},
        where: 'id = ?',
        whereArgs: [personId],
      );

  /// Permanently deletes a person and all their check-in records.
  static Future<void> deletePerson(int personId) async {
    // Fetch checkin IDs first — sqflite doesn't support subqueries in DELETE.
    final checkinRows = await _db.query('checkins',
        columns: ['id'], where: 'person_id = ?', whereArgs: [personId]);
    for (final row in checkinRows) {
      await _db.delete('checkin_methods',
          where: 'checkin_id = ?', whereArgs: [row['id']]);
    }
    await _db.delete('checkins', where: 'person_id = ?', whereArgs: [personId]);
    // Clear net_roles that reference this person (nullable FK).
    await _db.update('net_roles', {'person_id': null},
        where: 'person_id = ?', whereArgs: [personId]);
    await _db.delete('persons', where: 'id = ?', whereArgs: [personId]);
  }

  /// Bulk-import persons. Skips rows whose FCC callsign already exists.
  /// Also auto-creates any cities and neighborhoods not yet in the database.
  /// Returns the number of newly inserted rows.
  static Future<int> importPersons(List<Person> persons) async {
    // Auto-create cities
    final existingCities = (await loadCities()).toSet();
    for (final p in persons) {
      if (p.city != null && !existingCities.contains(p.city)) {
        await insertCity(p.city!);
        existingCities.add(p.city!);
      }
    }
    // Auto-create neighborhoods (insertNeighborhood ignores duplicates)
    for (final p in persons) {
      if (p.city != null && p.neighborhood != null) {
        await insertNeighborhood(p.city!, p.neighborhood!);
      }
    }
    // Insert persons, skipping FCC-callsign duplicates
    int imported = 0;
    for (final person in persons) {
      if (person.fccCallsign != null && person.fccCallsign!.isNotEmpty) {
        final existing = await _db.query('persons',
            columns: ['id'],
            where: 'fcc_callsign = ?',
            whereArgs: [person.fccCallsign]);
        if (existing.isNotEmpty) continue;
      }
      await _db.insert('persons', person.toMap());
      imported++;
    }
    return imported;
  }

  // ── Cities ────────────────────────────────────────────────────────────────

  static Future<List<String>> loadCities() async {
    final rows = await _db.query('cities',
        orderBy: 'name COLLATE NOCASE');
    return rows.map((r) => r['name'] as String).toList();
  }

  /// Inserts a city. Silently does nothing if the name already exists.
  static Future<void> insertCity(String name) async {
    await _db.insert('cities', {'name': name.trim()},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> deleteCity(String name) async {
    await _db.delete('neighborhoods', where: 'city = ?', whereArgs: [name]);
    await _db.delete('cities', where: 'name = ?', whereArgs: [name]);
  }

  // ── Neighborhoods ────────────────────────────────────────────────────────

  /// Returns neighborhoods for a given city, sorted by name.
  static Future<List<String>> loadNeighborhoods(String city) async {
    final rows = await _db.query('neighborhoods',
        where: 'city = ?',
        whereArgs: [city],
        orderBy: 'name COLLATE NOCASE');
    return rows.map((r) => r['name'] as String).toList();
  }

  static Future<void> insertNeighborhood(String city, String name) async {
    await _db.insert('neighborhoods', {'city': city, 'name': name.trim()},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> deleteNeighborhood(String city, String name) =>
      _db.delete('neighborhoods',
          where: 'city = ? AND name = ?', whereArgs: [city, name]);

  // ── Weeks ─────────────────────────────────────────────────────────────────

  static Future<int> findOrCreateWeek(DateTime weekEnding) async {
    final dateStr = _dateStr(weekEnding);
    final existing = await _db.query('weeks',
        where: 'week_ending = ?', whereArgs: [dateStr]);
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return _db.insert('weeks', {'week_ending': dateStr});
  }

  // ── Check-ins ─────────────────────────────────────────────────────────────

  /// Returns methods for the given week.
  /// methods  : personId → set of checked method names
  static Future<Map<int, Set<String>>> loadCheckins(int weekId) async {
    final methods = <int, Set<String>>{};

    final rows = await _db.rawQuery('''
      SELECT c.person_id, cm.method
      FROM checkins c
      JOIN checkin_methods cm ON cm.checkin_id = c.id
      WHERE c.week_id = ?
    ''', [weekId]);

    for (final row in rows) {
      final pid = row['person_id'] as int;
      final method = row['method'] as String;
      methods.putIfAbsent(pid, () => {}).add(method);
    }

    return methods;
  }

  /// Adds or removes [method] for [personId] in [weekId].
  /// Also creates/deletes the parent checkins row as needed.
  static Future<void> setMethod(
      int weekId, int personId, String method, bool checked) async {
    if (checked) {
      final checkinId = await _ensureCheckin(weekId, personId);
      final existing = await _db.query('checkin_methods',
          where: 'checkin_id = ? AND method = ?',
          whereArgs: [checkinId, method]);
      if (existing.isEmpty) {
        await _db
            .insert('checkin_methods', {'checkin_id': checkinId, 'method': method});
      }
    } else {
      final checkinRows = await _db.query('checkins',
          where: 'person_id = ? AND week_id = ?',
          whereArgs: [personId, weekId]);
      if (checkinRows.isEmpty) return;
      final checkinId = checkinRows.first['id'] as int;
      await _db.delete('checkin_methods',
          where: 'checkin_id = ? AND method = ?',
          whereArgs: [checkinId, method]);
      // Remove checkin row if no methods remain
      final remaining = await _db.query('checkin_methods',
          where: 'checkin_id = ?', whereArgs: [checkinId]);
      if (remaining.isEmpty) {
        await _db
            .delete('checkins', where: 'id = ?', whereArgs: [checkinId]);
      }
    }
  }

  // ── Net roles ─────────────────────────────────────────────────────────────

  /// For each day+role combination, returns the most recent assignment
  /// from any week before [currentWeekId] where a person was actually set.
  static Future<Map<String, Map<String, dynamic>>> loadPreviousNetRoles(
      int currentWeekId) async {
    final result = <String, Map<String, dynamic>>{};
    for (final role in kNetRoles) {
      final rows = await _db.rawQuery('''
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
      ''', [currentWeekId, kNetRoleDay, role]);
      if (rows.isNotEmpty) {
        result['$kNetRoleDay|$role'] = Map<String, dynamic>.from(rows.first);
      }
    }
    return result;
  }

  /// Returns Map keyed by '$dayOfWeek|$role'.
  /// Each value is the raw DB row (includes person fields via JOIN).
  static Future<Map<String, Map<String, dynamic>>> loadNetRoles(
      int weekId) async {
    final rows = await _db.rawQuery('''
      SELECT nr.day_of_week, nr.role, nr.person_id, nr.display_name,
             p.first_name, p.last_name, p.fcc_callsign
      FROM net_roles nr
      LEFT JOIN persons p ON p.id = nr.person_id
      WHERE nr.week_id = ?
    ''', [weekId]);

    return {
      for (final row in rows)
        '${row['day_of_week']}|${row['role']}':
            Map<String, dynamic>.from(row),
    };
  }

  static Future<void> setNetRole(
    int weekId,
    String dayOfWeek,
    String role, {
    int? personId,
    String? displayName,
  }) async {
    final existing = await _db.query('net_roles',
        where: 'week_id = ? AND day_of_week = ? AND role = ?',
        whereArgs: [weekId, dayOfWeek, role]);

    if (existing.isEmpty) {
      if (personId == null && (displayName == null || displayName.isEmpty)) {
        return;
      }
      await _db.insert('net_roles', {
        'week_id': weekId,
        'day_of_week': dayOfWeek,
        'role': role,
        'person_id': personId,
        'display_name': displayName,
      });
    } else {
      final id = existing.first['id'] as int;
      if (personId == null && (displayName == null || displayName.isEmpty)) {
        await _db.delete('net_roles', where: 'id = ?', whereArgs: [id]);
      } else {
        await _db.update(
          'net_roles',
          {'person_id': personId, 'display_name': displayName},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Future<int> _ensureCheckin(int weekId, int personId) async {
    final existing = await _db.query('checkins',
        where: 'person_id = ? AND week_id = ?',
        whereArgs: [personId, weekId]);
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return _db.insert('checkins', {'person_id': personId, 'week_id': weekId});
  }

  static String _dateStr(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
