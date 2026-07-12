import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/logger.dart';
import '../../data/models/file_record.dart';
import 'service_providers.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════════════════════════

enum HistoryStatus { initial, loading, loaded, error }

class HistoryState {
  final HistoryStatus status;
  final List<FileRecord> recentFiles;
  final List<FileRecord> favorites;
  final String? errorMessage;

  const HistoryState({
    this.status = HistoryStatus.initial,
    this.recentFiles = const [],
    this.favorites = const [],
    this.errorMessage,
  });

  HistoryState copyWith({
    HistoryStatus? status,
    List<FileRecord>? recentFiles,
    List<FileRecord>? favorites,
    String? errorMessage,
  }) {
    return HistoryState(
      status: status ?? this.status,
      recentFiles: recentFiles ?? this.recentFiles,
      favorites: favorites ?? this.favorites,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  bool get isLoading => status == HistoryStatus.loading;
  bool get hasFiles => recentFiles.isNotEmpty || favorites.isNotEmpty;
}

// ═══════════════════════════════════════════════════════════════════════════════
// NOTIFIER
// ═══════════════════════════════════════════════════════════════════════════════

class HistoryNotifier extends StateNotifier<HistoryState> {
  final Ref _ref;

  HistoryNotifier(this._ref) : super(const HistoryState());

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> load() async {
    if (state.isLoading) return;
    state = state.copyWith(status: HistoryStatus.loading);

    try {
      final svc = _ref.read(historyServiceProvider);
      final recent = await svc.getRecent(limit: 20);
      final favs = await svc.getFavorites();

      state = HistoryState(
        status: HistoryStatus.loaded,
        recentFiles: recent,
        favorites: favs,
      );
    } catch (e) {
      AppLogger.error('Failed to load history', tag: 'HistoryNotifier', error: e);
      state = state.copyWith(
        status: HistoryStatus.error,
        errorMessage: 'Could not load recent files.',
      );
    }
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  Future<void> recordOpen(String path) async {
    try {
      final svc = _ref.read(historyServiceProvider);
      await svc.recordOpen(path);
      await load(); // refresh list
    } catch (e) {
      AppLogger.warning('Failed to record open: $e', tag: 'HistoryNotifier');
    }
  }

  Future<void> toggleFavorite(String fileId) async {
    try {
      final svc = _ref.read(historyServiceProvider);
      await svc.toggleFavorite(fileId);
      await load();
    } catch (e) {
      AppLogger.warning('Failed to toggle favorite: $e', tag: 'HistoryNotifier');
    }
  }

  Future<void> removeRecord(String fileId) async {
    try {
      final svc = _ref.read(historyServiceProvider);
      await svc.remove(fileId);
      await load();
    } catch (e) {
      AppLogger.warning('Failed to remove record: $e', tag: 'HistoryNotifier');
    }
  }

  Future<void> clearAll() async {
    try {
      final svc = _ref.read(historyServiceProvider);
      await svc.clearAll();
      state = const HistoryState(status: HistoryStatus.loaded);
    } catch (e) {
      AppLogger.warning('Failed to clear history: $e', tag: 'HistoryNotifier');
    }
  }

  Future<void> saveScrollPosition(String fileId, double position) async {
    try {
      final svc = _ref.read(historyServiceProvider);
      await svc.saveScrollPosition(fileId, position);
    } catch (e) {
      AppLogger.warning('Failed to save scroll position: $e', tag: 'HistoryNotifier');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

final historyNotifierProvider =
    StateNotifierProvider<HistoryNotifier, HistoryState>(
  (ref) => HistoryNotifier(ref),
  name: 'historyNotifierProvider',
);
