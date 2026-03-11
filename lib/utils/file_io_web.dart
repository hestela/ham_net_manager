// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/wasm.dart';
import 'package:file_picker/file_picker.dart';

/// Triggers a browser download of [content] as a CSV file named
/// [defaultFilename]. Returns [defaultFilename] to indicate success.
Future<String?> saveCsvFile(String defaultFilename, String content) async {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], 'text/csv');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', defaultFilename)
    ..click();
  html.Url.revokeObjectUrl(url);
  return defaultFilename;
}

/// Opens a file picker for CSV files and returns the file content as a string.
/// Returns null if cancelled.
Future<String?> pickCsvContent() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['csv'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final bytes = result.files.single.bytes;
  if (bytes == null) return null;
  return utf8.decode(bytes);
}

/// Not supported on web — always returns false.
Future<bool> saveDatabaseCopy(String sourcePath) async => false;

/// Not supported on web — always returns null.
Future<String?> pickDatabaseFile() async => null;

/// Triggers a browser download of [bytes] as a file named [filename].
void saveDatabaseFile(String filename, Uint8List bytes) {
  final blob = html.Blob([bytes], 'application/x-sqlite3');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

/// Reads raw bytes of the current web database from whatever storage backend
/// drift is using (OPFS or IndexedDB). [dbName] is the drift database name
/// (slug). Returns null if the database is not found.
///
/// Must be called after the database is closed so that writes are flushed.
Future<Uint8List?> exportWebDatabaseBytes(String dbName) async {
  try {
    final probe = await WasmDatabase.probe(
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
      databaseName: dbName,
    );
    for (final db in probe.existingDatabases) {
      if (db.$2 == dbName) {
        return await probe.exportDatabase(db);
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Deletes a web database from storage so it can be recreated with new data.
/// Works with both OPFS and IndexedDB backends.
///
/// Must be called after the database is closed.
Future<void> deleteWebDatabase(String dbName) async {
  try {
    final probe = await WasmDatabase.probe(
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
      databaseName: dbName,
    );
    for (final db in probe.existingDatabases) {
      if (db.$2 == dbName) {
        await probe.deleteDatabase(db);
        return;
      }
    }
  } catch (_) {
    // Database may not exist — that's fine.
  }
}
