import '../data/models/document_block.dart';
import '../data/models/document_model.dart';
import '../data/models/search_result.dart';
import '../core/utils/logger.dart';

/// Searches the flat text content of a [DocumentModel] for a [SearchQuery].
///
/// Returns an ordered list of [SearchResult] objects, one per match,
/// in document order (block order, then character order within each block).
///
/// Runs synchronously — fast enough for typical documents on the main thread.
/// For very large documents (1000+ blocks) consider moving to an isolate.
class DocumentSearchService {
  const DocumentSearchService();

  List<SearchResult> search(DocumentModel model, SearchQuery query) {
    if (query.isEmpty) return const [];

    final results = <SearchResult>[];

    for (final block in model.blocks) {
      try {
        results.addAll(_searchBlock(block, query));
      } catch (e) {
        AppLogger.warning(
          'Search error in block ${block.id}: $e',
          tag: 'DocumentSearchService',
        );
      }
    }

    AppLogger.debug(
      'Search "${query.term}": ${results.length} match(es)',
      tag: 'DocumentSearchService',
    );

    return results;
  }

  // ── Block dispatch ─────────────────────────────────────────────────────────

  List<SearchResult> _searchBlock(DocumentBlock block, SearchQuery query) =>
      switch (block) {
        ParagraphBlock()  => _searchFlatText(block.id, block.plainText, query),
        HeadingBlock()    => _searchFlatText(block.id, block.plainText, query),
        ListBlock()       => _searchList(block, query),
        TableBlock()      => _searchTable(block, query),
        HyperlinkBlock()  => _searchFlatText(block.id, block.displayText, query),
        // Equations, images, page-breaks have no searchable text
        _                 => const [],
      };

  // ── Plain-text search ──────────────────────────────────────────────────────

  List<SearchResult> _searchFlatText(
    String blockId,
    String text,
    SearchQuery query,
  ) {
    if (text.isEmpty) return const [];

    final haystack = query.caseSensitive ? text : text.toLowerCase();
    final needle   = query.compareTerm;

    if (!haystack.contains(needle)) return const [];

    final results = <SearchResult>[];
    int start = 0;

    while (start < haystack.length) {
      final idx = haystack.indexOf(needle, start);
      if (idx == -1) break;

      // Whole-word check
      if (query.wholeWord && !_isWholeWord(haystack, idx, needle.length)) {
        start = idx + 1;
        continue;
      }

      results.add(SearchResult(
        blockId:   blockId,
        charStart: idx,
        charEnd:   idx + needle.length,
        matchText: text.substring(idx, idx + needle.length),
      ));

      start = idx + 1; // allow overlapping matches
    }

    return results;
  }

  bool _isWholeWord(String text, int start, int length) {
    final before = start > 0 ? text[start - 1] : ' ';
    final after  = (start + length) < text.length ? text[start + length] : ' ';
    return !_isWordChar(before) && !_isWordChar(after);
  }

  bool _isWordChar(String ch) =>
      RegExp(r'[a-zA-Z0-9_\u00C0-\u024F]').hasMatch(ch);

  // ── List search ────────────────────────────────────────────────────────────

  List<SearchResult> _searchList(ListBlock block, SearchQuery query) {
    final results = <SearchResult>[];
    for (final item in block.items) {
      results.addAll(_searchFlatText(item.id, item.plainText, query));
    }
    return results;
  }

  // ── Table search ───────────────────────────────────────────────────────────

  List<SearchResult> _searchTable(TableBlock block, SearchQuery query) {
    final results = <SearchResult>[];
    for (final row in block.rows) {
      for (final cell in row.cells) {
        for (final cellBlock in cell.content) {
          results.addAll(_searchBlock(cellBlock, query));
        }
      }
    }
    return results;
  }
}
