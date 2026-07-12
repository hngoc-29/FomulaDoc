import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/logger.dart';
import '../models/file_record.dart';

/// Persists the document open history using [SharedPreferences].
///
/// Data is stored as a JSON array keyed by [AppConstants.historyPrefsKey].
/// Responsible for serialization only — business logic lives in [HistoryService].
class HistoryRepository {
  const HistoryRepository();

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Loads all [FileRecord] entries, sorted newest-first.
  Future<List<FileRecord>> loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(AppConstants.historyPrefsKey);
      if (json == null) return [];

      final list = jsonDecode(json) as List<dynamic>;
      final records = list
          .whereType<Map<String, dynamic>>()
          .map((m) {
            try {
              return FileRecord.fromJson(m);
            } catch (e) {
              AppLogger.warning(
                'Skipping corrupt history entry: $e',
                tag: 'HistoryRepository',
              );
              return null;
            }
          })
          .whereType<FileRecord>()
          .toList();

      // Sort newest-first
      records.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
      return records;
    } catch (e) {
      AppLogger.error(
        'Failed to load history',
        tag: 'HistoryRepository',
        error: e,
      );
      return [];
    }
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Persists the full list of [records].
  ///
  /// Trims to [AppConstants.maxHistoryItems] before saving.
  Future<void> saveAll(List<FileRecord> records) async {
    try {
      final trimmed = records.length > AppConstants.maxHistoryItems
          ? records.sublist(0, AppConstants.maxHistoryItems)
          : records;

      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(trimmed.map((r) => r.toJson()).toList());
      await prefs.setString(AppConstants.historyPrefsKey, json);
    } catch (e) {
      throw StorageException(
        'Failed to save file history',
        cause: e,
      );
    }
  }

  /// Adds or updates a single [record] and persists.
  Future<void> upsert(FileRecord record) async {
    final all = await loadAll();
    final idx = all.indexWhere((r) => r.id == record.id);
    if (idx == -1) {
      all.insert(0, record);
    } else {
      all[idx] = record;
    }
    await saveAll(all);
  }

  /// Removes the [FileRecord] with [id] and persists.
  Future<void> remove(String id) async {
    final all = await loadAll();
    all.removeWhere((r) => r.id == id);
    await saveAll(all);
  }

  /// Clears the entire history.
  Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.historyPrefsKey);
    } catch (e) {
      throw StorageException('Failed to clear history', cause: e);
    }
  }
}
