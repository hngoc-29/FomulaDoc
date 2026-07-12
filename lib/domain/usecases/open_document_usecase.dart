import '../../core/errors/app_exception.dart';
import '../../data/models/document_model.dart';
import '../../data/parsers/parser_registry.dart';
import '../../domain/abstractions/document_source.dart';
import '../../services/document_cache_service.dart';
import '../../services/history_service.dart';

/// Encapsulates the entire "open a document" flow:
///   1. Check in-memory LRU cache — return immediately on hit.
///   2. Resolve the correct parser from [DocumentParserRegistry].
///   3. Parse the source into a [DocumentModel].
///   4. Store the result in cache.
///   5. Record the open in file history.
///
/// Used by [DocumentNotifier]; can be unit-tested without Flutter.
class OpenDocumentUseCase {
  final DocumentParserRegistry _registry;
  final DocumentCacheService   _cache;
  final HistoryService         _history;

  const OpenDocumentUseCase({
    required DocumentParserRegistry registry,
    required DocumentCacheService   cache,
    required HistoryService         history,
  })  : _registry = registry,
        _cache    = cache,
        _history  = history;

  /// Executes the use case.
  ///
  /// Throws [UnsupportedFormatException] if no parser handles the format.
  /// Throws [ParseException] for planned-but-not-implemented formats.
  /// Throws [FileNotFoundException] if the source file does not exist.
  Future<DocumentModel> execute(DocumentSource source) async {
    // 1. Cache hit
    if (source.path != null) {
      final cached = _cache.get(source.path!);
      if (cached != null) return cached;
    }

    // 2. Resolve parser (throws if unsupported / not yet implemented)
    final parser = _registry.forSource(source);
    if (parser == null) {
      throw UnsupportedFormatException(
        source.name.contains('.') ? source.name.split('.').last : 'unknown',
      );
    }
    if (!parser.format.isSupported) {
      throw ParseException(
        '${parser.format.displayName} support is coming soon!\n'
        'FormulaDoc currently supports DOCX files.',
      );
    }

    // 3. Parse
    final model = await parser.parse(source);

    // 4. Cache
    if (source.path != null) {
      _cache.put(source.path!, model);
    }

    // 5. History
    if (source.path != null) {
      await _history.recordOpen(source.path!);
    }

    return model;
  }
}
