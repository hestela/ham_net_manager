// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:convert';

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
