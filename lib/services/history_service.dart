import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:collection/collection.dart';

import '../core/utils/logger.dart';
import '../data/models/file_record.dart';
import '../data/repositories/history_repository.dart';

/// Business logic for the file history / recents system.
///
/// Sits between [HistoryRepository] (raw persistence) and
/// [HistoryNotifier] (Riverpod state).
class HistoryService {
  final HistoryRepository _repository;

  const HistoryService(this._repository);

  // ── Queries ───────────────────────────────────────────────────────────────

  Future<List<FileRecord>> getAll() => _repository.loadAll();

  Future<List<FileRecord>> getRecent({int limit = 20}) async {
    final all = await _repository.loadAll();
    // We intentionally do NOT filter by _fileExists here.
    // Files opened via "Open With" are stored in a temp cache that is still
    // accessible during the session that wrote the record, but the path may
    // not survive between sessions on some devices.  Removing the existence
    // check keeps PDF / XLSX intent entries visible in history; a "File not
    // found" error is shown when the user taps a stale entry.
    return all.take(limit).toList();
  }

  Future<List<FileRecord>> getFavorites() async {
    final all = await _repository.loadAll();
    return all.where((r) => r.isFavorite).toList();
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  /// Records that the document at [path] was opened, returning the record.
  Future<FileRecord> recordOpen(String path) async {
    final all = await _repository.loadAll();
    final existing = all.where((r) => r.path == path).firstOrNull;

    late FileRecord record;
    if (existing != null) {
      record = existing.copyWith(lastOpenedAt: DateTime.now());
    } else {
      final size = _sizeOf(path);
      record = FileRecord(
        id: _generateId(path),
        path: path,
        name: p.basename(path),
        lastOpenedAt: DateTime.now(),
        fileSizeBytes: size,
      );
    }

    await _repository.upsert(record);
    AppLogger.debug('Recorded open: ${record.name}', tag: 'HistoryService');
    return record;
  }

  /// Saves the reading scroll [position] for a document.
  Future<void> saveScrollPosition(String fileId, double position) async {
    final all = await _repository.loadAll();
    final idx = all.indexWhere((r) => r.id == fileId);
    if (idx == -1) return;
    final updated = all[idx].copyWith(lastScrollPosition: position);
    await _repository.upsert(updated);
  }

  /// Toggles the favorite status for the file with [fileId].
  Future<FileRecord?> toggleFavorite(String fileId) async {
    final all = await _repository.loadAll();
    final idx = all.indexWhere((r) => r.id == fileId);
    if (idx == -1) return null;
    final toggled = all[idx].copyWith(isFavorite: !all[idx].isFavorite);
    await _repository.upsert(toggled);
    return toggled;
  }

  /// Removes a document from history.
  Future<void> remove(String fileId) => _repository.remove(fileId);

  /// Clears all history.
  Future<void> clearAll() => _repository.clearAll();

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _fileExists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  int? _sizeOf(String path) {
    try {
      return File(path).lengthSync();
    } catch (_) {
      return null;
    }
  }

  /// Generates a stable ID for a file.
  ///
  /// Android content URIs (`content://…`) are session-scoped and change
  /// between app launches, so using `path.hashCode` as the key creates
  /// duplicate history entries for the same physical file.
  ///
  /// Strategy:
  ///   • Regular file paths (`/storage/…`) → hash the path directly.
  ///   • Content URIs (`content://…`) → hash the last path segment (file
  ///     name) combined with file size, which stays stable across sessions.
  /// Save the last-viewed PDF page number for a file.
  Future<void> savePdfPage(String fileId, int page) async {
    final all = await _repository.loadAll();
    final idx = all.indexWhere((r) => r.id == fileId);
    if (idx < 0) return;
    final updated = all[idx].copyWith(lastPdfPage: page);
    all[idx] = updated;
    await _repository.saveAll(all);
  }

  /// Toggle a bookmark at [blockIndex] for file [fileId].
  Future<List<int>> toggleBookmark(String fileId, int blockIndex) async {
    final all = await _repository.loadAll();
    final idx = all.indexWhere((r) => r.id == fileId);
    if (idx < 0) return const [];
    final marks = List<int>.from(all[idx].bookmarks);
    if (marks.contains(blockIndex)) {
      marks.remove(blockIndex);
    } else {
      marks.add(blockIndex);
      marks.sort();
    }
    all[idx] = all[idx].copyWith(bookmarks: marks);
    await _repository.saveAll(all);
    return marks;
  }

  /// Add file to a collection by name (creates collection if not exists).
  Future<void> addToCollection(String fileId, String collection) async {
    final all = await _repository.loadAll();
    final idx = all.indexWhere((r) => r.id == fileId);
    if (idx < 0) return;
    final cols = List<String>.from(all[idx].collections);
    if (!cols.contains(collection)) cols.add(collection);
    all[idx] = all[idx].copyWith(collections: cols);
    await _repository.saveAll(all);
  }

  /// Remove file from a collection.
  Future<void> removeFromCollection(String fileId, String collection) async {
    final all = await _repository.loadAll();
    final idx = all.indexWhere((r) => r.id == fileId);
    if (idx < 0) return;
    final cols = List<String>.from(all[idx].collections)..remove(collection);
    all[idx] = all[idx].copyWith(collections: cols);
    await _repository.saveAll(all);
  }

  /// Get all unique collection names across all files.
  Future<List<String>> getAllCollections() async {
    final all = await _repository.loadAll();
    return all.expand((r) => r.collections).toSet().toList()..sort();
  }

  String _generateId(String path) {
    if (path.startsWith('content://')) {
      final name = path.split('/').last.split('%2F').last;
      final size = _sizeOf(path) ?? 0;
      return 'rec_${(name + size.toString()).hashCode.abs()}';
    }
    return 'rec_${path.hashCode.abs()}';
  }
}
