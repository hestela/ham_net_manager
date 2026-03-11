import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Saves [content] to a CSV file. On desktop, prompts the user with a save
/// dialog. On Android, auto-saves to the app's documents directory.
/// Returns the saved path, or null if cancelled.
Future<String?> saveCsvFile(String defaultFilename, String content) async {
  if (Platform.isAndroid) {
    final Directory dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$defaultFilename';
    await File(path).writeAsString(content);
    return path;
  }

  final String? path = await FilePicker.platform.saveFile(
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
  if (Platform.isAndroid) {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final Uint8List? bytes = result.files.single.bytes;
    if (bytes == null) return null;
    return utf8.decode(bytes);
  }

  final FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['csv'],
  );
  if (result == null || result.files.isEmpty) return null;
  final String? path = result.files.single.path;
  if (path == null) return null;
  return File(path).readAsString();
}

/// Copies [sourcePath] to a user-chosen destination. On Android, copies to
/// the app's documents directory. Returns true if successful, false if cancelled.
Future<bool> saveDatabaseCopy(String sourcePath) async {
  if (Platform.isAndroid) {
    final Directory dir = await getApplicationDocumentsDirectory();
    final String filename = sourcePath.split('/').last;
    final destPath = '${dir.path}/$filename';
    await File(sourcePath).copy(destPath);
    return true;
  }

  final String? destPath = await FilePicker.platform.saveFile(
    dialogTitle: 'Save Database As',
    fileName: sourcePath.split('/').last,
  );
  if (destPath == null) return false;
  await File(sourcePath).copy(destPath);
  return true;
}

/// Opens a file picker to choose a database file. On Android, copies the
/// selected file to the app's data directory and returns that local path.
/// Returns null if cancelled.
Future<String?> pickDatabaseFile() async {
  if (Platform.isAndroid) {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open Database File',
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final Uint8List? bytes = result.files.single.bytes;
    if (bytes == null) return null;
    final String filename = result.files.single.name;
    final Directory dir = await getApplicationDocumentsDirectory();
    final destPath = '${dir.path}/$filename';
    await File(destPath).writeAsBytes(bytes);
    return destPath;
  }

  final FilePickerResult? result = await FilePicker.platform.pickFiles(
    dialogTitle: 'Open Database File',
  );
  if (result == null || result.files.isEmpty) return null;
  return result.files.single.path;
}

/// No-op on desktop/Android — web only.
void saveDatabaseFile(String filename, Uint8List bytes) {}

/// No-op on desktop/Android — web only.
Future<Uint8List?> exportWebDatabaseBytes(String dbName) async => null;

/// No-op on desktop/Android — web only.
Future<void> deleteWebDatabase(String dbName) async {}
