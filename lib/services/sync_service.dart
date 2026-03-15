import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/database_helper.dart';
import '../repositories/net_repository.dart';

class RemoteNet {
  const RemoteNet({
    required this.slug,
    required this.name,
    required this.updatedAt,
  });
  final String slug;
  final String name;
  final String updatedAt;
}

class SyncService {
  // ── Config keys ──────────────────────────────────────────────────────────

  static const String _kUserAgent = 'HamNetManager/1.0';
  static const String _kWorkerUrl = 'sync_worker_url';
  static const String _kApiToken = 'sync_api_token';
  static const String _kLastPush = 'sync_last_push';
  static const String _kLastPull = 'sync_last_pull';
  static const String _kPendingSync = 'sync_pending';

  // ── Settings ─────────────────────────────────────────────────────────────

  static Future<({String workerUrl, String apiToken})> getConfig() async {
    final String workerUrl =
        await DatabaseHelper.getSetting(_kWorkerUrl) ?? '';
    final String apiToken = await DatabaseHelper.getSetting(_kApiToken) ?? '';
    return (workerUrl: workerUrl, apiToken: apiToken);
  }

  static Future<void> saveConfig(String workerUrl, String apiToken) async {
    await DatabaseHelper.setSetting(_kWorkerUrl, workerUrl.trim());
    await DatabaseHelper.setSetting(_kApiToken, apiToken.trim());
  }

  static Future<String?> getLastPush() => DatabaseHelper.getSetting(_kLastPush);
  static Future<String?> getLastPull() => DatabaseHelper.getSetting(_kLastPull);

  static Future<void> setPendingSync() =>
      DatabaseHelper.setSetting(_kPendingSync, 'true');

  static Future<void> clearPendingSync() =>
      DatabaseHelper.setSetting(_kPendingSync, 'false');

  static Future<bool> hasPendingSync() async {
    final String? v = await DatabaseHelper.getSetting(_kPendingSync);
    return v == 'true';
  }

  // ── Conflict detection ────────────────────────────────────────────────────

  /// Returns true if the cloud snapshot was updated more recently than the
  /// last time this client synced (push or pull), indicating that someone
  /// else may have pushed changes in the meantime.
  ///
  /// Returns false if the net doesn't exist on the server yet (first push),
  /// or if the timestamps cannot be compared.
  static Future<bool> cloudHasNewerData({
    required String workerUrl,
    required String token,
  }) async {
    final String? lastPull = await getLastPull();
    final String? lastPush = await getLastPush();

    // Never synced at all — this will be a first push, no conflict possible.
    if (lastPull == null && lastPush == null) return false;

    // Use whichever sync event was most recent.
    DateTime? lastSync;
    if (lastPull != null) lastSync = DateTime.tryParse(lastPull);
    if (lastPush != null) {
      final DateTime? t = DateTime.tryParse(lastPush);
      if (t != null && (lastSync == null || t.isAfter(lastSync))) lastSync = t;
    }
    if (lastSync == null) return false;

    final List<RemoteNet> nets =
        await fetchNets(workerUrl: workerUrl, token: token);
    final String slug = _currentSlug();
    RemoteNet? remote;
    for (final n in nets) {
      if (n.slug == slug) {
        remote = n;
        break;
      }
    }

    // Net not on server yet — first push, no conflict.
    if (remote == null) return false;

    final DateTime? cloudUpdated = DateTime.tryParse(remote.updatedAt);
    if (cloudUpdated == null) return false;

    // Allow a 10-second buffer for clock skew between client and server.
    return cloudUpdated.isAfter(lastSync.add(const Duration(seconds: 10)));
  }

  // ── Net discovery ─────────────────────────────────────────────────────────

  /// Returns all nets stored on the worker.
  static Future<List<RemoteNet>> fetchNets({
    required String workerUrl,
    required String token,
  }) async {
    final Uri uri = Uri.parse('${_baseUrl(workerUrl)}/nets');
    final http.Response response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token', 'User-Agent': _kUserAgent},
    );

    if (response.statusCode == 401) throw Exception('Invalid token.');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Server error (${response.statusCode}).');
    }

    final map = jsonDecode(response.body) as Map<String, dynamic>;
    final nets = map['nets'] as List<dynamic>;
    return nets.map((dynamic n) {
      final entry = n as Map<String, dynamic>;
      return RemoteNet(
        slug: entry['net_slug'] as String,
        name: entry['net_name'] as String,
        updatedAt: entry['updated_at'] as String,
      );
    }).toList();
  }

  // ── Push ─────────────────────────────────────────────────────────────────

  /// Serializes local data and uploads it to the Worker under the current
  /// city's slug.
  static Future<void> push({
    required String workerUrl,
    required String token,
  }) async {
    final Map<String, dynamic> data = await NetRepository.exportAllData();
    final Uri uri = Uri.parse('${_baseUrl(workerUrl)}/sync/${_currentSlug()}');

    final http.Response response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'User-Agent': _kUserAgent,
      },
      body: jsonEncode(data),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Push failed (${response.statusCode}): ${response.body}');
    }

    await DatabaseHelper.setSetting(
        _kLastPush, DateTime.now().toIso8601String());
  }

  // ── Pull ─────────────────────────────────────────────────────────────────

  /// Downloads the snapshot for [slug] and upserts it locally.
  static Future<void> pull({
    required String workerUrl,
    required String token,
    String? slug,
  }) async {
    final String netSlug = slug ?? _currentSlug();
    final Uri uri = Uri.parse('${_baseUrl(workerUrl)}/sync/$netSlug');

    final http.Response response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token', 'User-Agent': _kUserAgent},
    );

    if (response.statusCode == 404) {
      throw Exception('No snapshot found on server. Push first.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Pull failed (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    await NetRepository.importAllData(data);

    await DatabaseHelper.setSetting(
        _kLastPull, DateTime.now().toIso8601String());
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _baseUrl(String workerUrl) {
    final String trimmed = workerUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return 'https://$trimmed';
    }
    return trimmed;
  }

  static String _currentSlug() => Uri.encodeComponent(
        DatabaseHelper.currentCity
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'^-+|-+$'), ''),
      );
}
