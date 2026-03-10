// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:js_interop';

import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;

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

/// Reads raw bytes of the current web database from OPFS.
/// [dbName] is the drift database name (slug).
/// Returns null if OPFS is unavailable or database not found.
Future<Uint8List?> exportWebDatabaseBytes(String dbName) async {
  try {
    final storage = web.window.navigator.storage;
    final root = await storage.getDirectory().toDart;
    final driftDir = await root
        .getDirectoryHandle('drift_db', web.FileSystemGetDirectoryOptions(create: false))
        .toDart;
    final dbDir = await driftDir
        .getDirectoryHandle(dbName, web.FileSystemGetDirectoryOptions(create: false))
        .toDart;
    final fileHandle = await dbDir
        .getFileHandle('database', web.FileSystemGetFileOptions(create: false))
        .toDart;
    final file = await fileHandle.getFile().toDart;
    final arrayBuffer = await file.arrayBuffer().toDart;
    return arrayBuffer.toDart.asUint8List();
  } catch (_) {
    return null;
  }
}

/// Deletes a web database from OPFS so it can be recreated with new data.
Future<void> deleteWebDatabase(String dbName) async {
  try {
    final storage = web.window.navigator.storage;
    final root = await storage.getDirectory().toDart;
    final driftDir = await root
        .getDirectoryHandle('drift_db', web.FileSystemGetDirectoryOptions(create: false))
        .toDart;
    await driftDir.removeEntry(dbName, web.FileSystemRemoveOptions(recursive: true)).toDart;
  } catch (_) {
    // Database may not exist yet — that's fine.
  }
}
