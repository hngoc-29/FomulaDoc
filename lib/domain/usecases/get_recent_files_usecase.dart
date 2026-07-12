import '../../data/models/file_record.dart';
import '../../services/history_service.dart';

/// Returns recent and favorite files for the home screen.
class GetRecentFilesUseCase {
  final HistoryService _history;

  const GetRecentFilesUseCase({required HistoryService history})
      : _history = history;

  Future<List<FileRecord>> recentFiles({int limit = 20}) =>
      _history.getRecent(limit: limit);

  Future<List<FileRecord>> favorites() => _history.getFavorites();
}
