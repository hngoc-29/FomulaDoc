import 'dart:collection';
import 'dart:io';

import '../data/models/document_model.dart';
import '../core/utils/logger.dart';

// ─── Cache entry ──────────────────────────────────────────────────────────────

class _CacheEntry {
  final DocumentModel model;
  final int?          fileModifiedMs;
  final DateTime      cachedAt;

  _CacheEntry({required this.model, this.fileModifiedMs})
      : cachedAt = DateTime.now();
}

// ═══════════════════════════════════════════════════════════════════════════════
// DOCUMENT CACHE SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// In-memory LRU cache for [DocumentModel] objects.
///
/// Avoids re-parsing a DOCX file every time the user revisits a document.
/// The cache is automatically invalidated when the source file's modification
/// timestamp changes.
///
/// Capacity: [maxEntries] documents (default 5).
/// On eviction the least-recently-used entry is removed.
///
/// This is a singleton-style service (one instance per app lifetime).
class DocumentCacheService {
  DocumentCacheService({this.maxEntries = 5});

  final int maxEntries;

  // LinkedHashMap preserves insertion order → first key = LRU.
  final _cache = LinkedHashMap<String, _CacheEntry>();

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Returns the cached [DocumentModel] for [filePath], or `null` on miss.
  ///
  /// If the file on disk is newer than the cached version (based on last-
  /// modified time), the entry is evicted and `null` is returned.
  DocumentModel? get(String filePath) {
    final entry = _cache[filePath];
    if (entry == null) {
      AppLogger.debug('Cache miss: $filePath', tag: 'DocumentCacheService');
      return null;
    }

    // Staleness check
    final diskMs = _modifiedMs(filePath);
    if (diskMs != null &&
        entry.fileModifiedMs != null &&
        diskMs != entry.fileModifiedMs) {
      _cache.remove(filePath);
      AppLogger.info(
        'Cache evicted (stale): $filePath',
        tag: 'DocumentCacheService',
      );
      return null;
    }

    // Touch → promote to MRU position
    _cache.remove(filePath);
    _cache[filePath] = entry;

    AppLogger.debug('Cache hit: $filePath', tag: 'DocumentCacheService');
    return entry.model;
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Stores [model] for [filePath], evicting LRU if at capacity.
  void put(String filePath, DocumentModel model) {
    final diskMs = _modifiedMs(filePath);

    if (_cache.length >= maxEntries && !_cache.containsKey(filePath)) {
      final lru = _cache.keys.first;
      _cache.remove(lru);
      AppLogger.debug('Cache evicted LRU: $lru', tag: 'DocumentCacheService');
    }

    _cache[filePath] = _CacheEntry(model: model, fileModifiedMs: diskMs);
    AppLogger.info(
      'Cached document: $filePath (${_cache.length}/$maxEntries entries)',
      tag: 'DocumentCacheService',
    );
  }

  /// Removes the entry for [filePath] (e.g. after user deletes a file).
  void evict(String filePath) {
    _cache.remove(filePath);
    AppLogger.debug('Cache evict: $filePath', tag: 'DocumentCacheService');
  }

  /// Clears all cached documents.
  void clear() {
    _cache.clear();
    AppLogger.info('Cache cleared', tag: 'DocumentCacheService');
  }

  // ── Diagnostics ───────────────────────────────────────────────────────────

  int  get size        => _cache.length;
  bool get isEmpty     => _cache.isEmpty;
  bool contains(String p) => _cache.containsKey(p);

  List<String> get cachedPaths => List.unmodifiable(_cache.keys);

  /// Approximate memory usage — rough heuristic based on block count.
  int estimatedSizeKb() {
    int total = 0;
    for (final entry in _cache.values) {
      // ~2 KB per block + 1 KB per image (very rough)
      total += entry.model.blockCount * 2 +
               entry.model.images.values.fold(0, (s, b) => s + b.length ~/ 1024);
    }
    return total;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  int? _modifiedMs(String path) {
    try {
      return File(path).lastModifiedSync().millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }
}
