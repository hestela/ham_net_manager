import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// Saves [content] to a user-chosen CSV file. Returns the chosen path, or
/// null if cancelled.
Future<String?> saveCsvFile(String defaultFilename, String content) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save CSV',
    fileName: defaultFilename,
    type: FileType.custom,
    allowedExtensions: ['csv'],
  );
  if (path == null) return null;
  await File(path).writeAsString(content);
  return path;
}

/// Opens a file picker for CSV files and returns the file content as a string.
/// Returns null if cancelled.
Future<String?> pickCsvContent() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['csv'],
  );
  if (result == null || result.files.isEmpty) return null;
  final path = result.files.single.path;
  if (path == null) return null;
  return File(path).readAsString();
}

/// Copies [sourcePath] to a user-chosen destination.
/// Returns true if the copy succeeded, false if cancelled.
Future<bool> saveDatabaseCopy(String sourcePath) async {
  final destPath = await FilePicker.platform.saveFile(
    dialogTitle: 'Save Database As',
    fileName: sourcePath.split('/').last,
    type: FileType.any,
  );
  if (destPath == null) return false;
  await File(sourcePath).copy(destPath);
  return true;
}

/// Opens a file picker to choose a database file. Returns the path, or null
/// if cancelled.
Future<String?> pickDatabaseFile() async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: 'Open Database File',
    type: FileType.any,
    allowMultiple: false,
  );
  if (result == null || result.files.isEmpty) return null;
  return result.files.single.path;
}
