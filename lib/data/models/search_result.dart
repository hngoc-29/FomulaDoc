// ═══════════════════════════════════════════════════════════════════════════════
// SEARCH QUERY
// ═══════════════════════════════════════════════════════════════════════════════

/// Parameters controlling a document text search.
class SearchQuery {
  /// The text to search for.
  final String term;

  /// When false (default) the comparison ignores case.
  final bool caseSensitive;

  /// When true only whole-word matches are returned.
  final bool wholeWord;

  const SearchQuery({
    required this.term,
    this.caseSensitive = false,
    this.wholeWord = false,
  });

  bool get isEmpty => term.isEmpty;

  String get compareTerm => caseSensitive ? term : term.toLowerCase();
}

// ═══════════════════════════════════════════════════════════════════════════════
// SEARCH RESULT
// ═══════════════════════════════════════════════════════════════════════════════

/// A single text match inside the document.
///
/// Character offsets refer to the block's **flat text** — the concatenated
/// content of all runs in that block (paragraph / heading).
class SearchResult {
  /// ID of the [DocumentBlock] that contains the match.
  final String blockId;

  /// Start character offset within the block's flat text (inclusive).
  final int charStart;

  /// End character offset within the block's flat text (exclusive).
  final int charEnd;

  /// The actual matched text (useful for display in a results list).
  final String matchText;

  const SearchResult({
    required this.blockId,
    required this.charStart,
    required this.charEnd,
    required this.matchText,
  });

  int get length => charEnd - charStart;

  @override
  String toString() =>
      'SearchResult(block=$blockId, [$charStart,$charEnd) "$matchText")';
}

// ═══════════════════════════════════════════════════════════════════════════════
// SEARCH HIGHLIGHT  (runtime rendering annotation)
// ═══════════════════════════════════════════════════════════════════════════════

/// Lightweight annotation passed to renderers to paint a highlight
/// over a character range inside a block's flat text.
class SearchHighlight {
  final int charStart;
  final int charEnd;

  /// True for the currently-active match (rendered in a different colour).
  final bool isCurrent;

  const SearchHighlight({
    required this.charStart,
    required this.charEnd,
    required this.isCurrent,
  });
}
