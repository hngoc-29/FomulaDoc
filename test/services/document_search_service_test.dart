import 'package:flutter_test/flutter_test.dart';

import 'package:formuladoc/data/models/document_block.dart';
import 'package:formuladoc/data/models/document_model.dart';
import 'package:formuladoc/data/models/search_result.dart';
import 'package:formuladoc/services/document_search_service.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

ParagraphBlock _para(String text, {String id = 'p1'}) => ParagraphBlock(
      id:   id,
      runs: [TextRun(text: text, style: TextRunStyle.empty)],
    );

HeadingBlock _heading(String text, {String id = 'h1'}) => HeadingBlock(
      id:    id,
      runs:  [TextRun(text: text, style: TextRunStyle.empty)],
      level: HeadingLevel.h1,
    );

DocumentModel _model(List<DocumentBlock> blocks) =>
    DocumentModel(blocks: blocks);

// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  late DocumentSearchService svc;

  setUp(() => svc = const DocumentSearchService());

  // ── Empty / null cases ─────────────────────────────────────────────────────

  group('Empty / edge cases', () {
    test('empty query returns no results', () {
      final results = svc.search(
        _model([_para('hello world')]),
        const SearchQuery(term: ''),
      );
      expect(results, isEmpty);
    });

    test('empty document returns no results', () {
      final results = svc.search(
        const DocumentModel(blocks: []),
        const SearchQuery(term: 'hello'),
      );
      expect(results, isEmpty);
    });

    test('query not present returns no results', () {
      final results = svc.search(
        _model([_para('hello world')]),
        const SearchQuery(term: 'xyz'),
      );
      expect(results, isEmpty);
    });
  });

  // ── Basic matching ─────────────────────────────────────────────────────────

  group('Basic text matching', () {
    test('single match in one paragraph', () {
      final results = svc.search(
        _model([_para('hello world')]),
        const SearchQuery(term: 'world'),
      );
      expect(results, hasLength(1));
      expect(results.first.matchText, 'world');
    });

    test('multiple matches in same paragraph', () {
      final results = svc.search(
        _model([_para('a b a b a')]),
        const SearchQuery(term: 'a'),
      );
      expect(results, hasLength(3));
    });

    test('matches across multiple blocks', () {
      final results = svc.search(
        _model([
          _para('The cat sat', id: 'p1'),
          _para('on the mat',  id: 'p2'),
          _para('and the cat', id: 'p3'),
        ]),
        const SearchQuery(term: 'cat'),
      );
      expect(results, hasLength(2));
      expect(results[0].blockId, 'p1');
      expect(results[1].blockId, 'p3');
    });

    test('match char offsets are correct', () {
      final results = svc.search(
        _model([_para('hello world')]),
        const SearchQuery(term: 'world'),
      );
      expect(results.first.charStart, 6);
      expect(results.first.charEnd,   11);
    });

    test('full-block text matched correctly', () {
      final results = svc.search(
        _model([_para('alpha beta gamma')]),
        const SearchQuery(term: 'beta'),
      );
      expect(results, hasLength(1));
      expect(results.first.charStart, 6);
    });
  });

  // ── Case sensitivity ───────────────────────────────────────────────────────

  group('Case sensitivity', () {
    test('case-insensitive by default', () {
      final results = svc.search(
        _model([_para('Hello World HELLO')]),
        const SearchQuery(term: 'hello'),
      );
      expect(results, hasLength(2));
    });

    test('case-sensitive finds only exact', () {
      final results = svc.search(
        _model([_para('Hello World HELLO')]),
        const SearchQuery(term: 'Hello', caseSensitive: true),
      );
      expect(results, hasLength(1));
      expect(results.first.matchText, 'Hello');
    });

    test('case-sensitive misses lowercase', () {
      final results = svc.search(
        _model([_para('hello world')]),
        const SearchQuery(term: 'HELLO', caseSensitive: true),
      );
      expect(results, isEmpty);
    });
  });

  // ── Heading search ─────────────────────────────────────────────────────────

  group('Heading blocks', () {
    test('search finds matches in headings', () {
      final results = svc.search(
        _model([_heading('Introduction to Calculus', id: 'h1')]),
        const SearchQuery(term: 'calculus'),
      );
      expect(results, hasLength(1));
      expect(results.first.blockId, 'h1');
    });
  });

  // ── List search ────────────────────────────────────────────────────────────

  group('List blocks', () {
    test('search finds matches inside list items', () {
      final list = ListBlock(
        id:       'list1',
        isOrdered: false,
        items: [
          ParagraphBlock(
            id:   'li1',
            runs: [TextRun(text: 'Apples and oranges', style: TextRunStyle.empty)],
          ),
          ParagraphBlock(
            id:   'li2',
            runs: [TextRun(text: 'Bananas and grapes', style: TextRunStyle.empty)],
          ),
        ],
      );
      final results = svc.search(
        _model([list]),
        const SearchQuery(term: 'and'),
      );
      expect(results, hasLength(2));
    });
  });

  // ── Table search ───────────────────────────────────────────────────────────

  group('Table blocks', () {
    test('search finds matches inside table cells', () {
      final table = TableBlock(
        id: 'tbl1',
        rows: [
          TableRow(cells: [
            TableCell(content: [
              ParagraphBlock(
                id:   'tc1',
                runs: [TextRun(text: 'Mathematics', style: TextRunStyle.empty)],
              ),
            ]),
            TableCell(content: [
              ParagraphBlock(
                id:   'tc2',
                runs: [TextRun(text: 'Physics',     style: TextRunStyle.empty)],
              ),
            ]),
          ]),
        ],
      );
      final results = svc.search(
        _model([table]),
        const SearchQuery(term: 'math'),
      );
      expect(results, hasLength(1));
      expect(results.first.matchText.toLowerCase(), 'math');
    });
  });

  // ── SearchState highlights ─────────────────────────────────────────────────

  group('SearchState.highlightsForBlock', () {
    test('returns empty list when no search active', () {
      const state = SearchState();
      expect(state.highlightsForBlock('p1'), isEmpty);
    });

    test('returns correct highlights for matching block', () {
      final results = [
        const SearchResult(blockId: 'p1', charStart: 0,  charEnd: 5,  matchText: 'hello'),
        const SearchResult(blockId: 'p1', charStart: 12, charEnd: 17, matchText: 'hello'),
        const SearchResult(blockId: 'p2', charStart: 0,  charEnd: 5,  matchText: 'hello'),
      ];
      final state = SearchState(
        isOpen:       true,
        query:        'hello',
        results:      results,
        currentIndex: 1,
      );

      final hl = state.highlightsForBlock('p1');
      expect(hl, hasLength(2));
      expect(hl[0].isCurrent, isFalse);   // index 0 is not current
      expect(hl[1].isCurrent, isTrue);    // index 1 IS current
    });

    test('non-matching block returns empty', () {
      final state = SearchState(
        isOpen:  true,
        query:   'hello',
        results: [
          const SearchResult(blockId: 'p1', charStart: 0, charEnd: 5, matchText: 'hello'),
        ],
      );
      expect(state.highlightsForBlock('p99'), isEmpty);
    });
  });

  // ── Status text ───────────────────────────────────────────────────────────

  group('SearchState.statusText', () {
    test('empty when not open', () {
      expect(const SearchState().statusText, isEmpty);
    });

    test('"No results" when query has no matches', () {
      final state = SearchState(
        isOpen:  true,
        query:   'xyz',
        results: const [],
      );
      expect(state.statusText, 'No results');
    });

    test('"1 / 3" when at first of three matches', () {
      final results = List.generate(
        3,
        (i) => SearchResult(
          blockId:   'p$i',
          charStart: 0,
          charEnd:   3,
          matchText: 'foo',
        ),
      );
      final state = SearchState(
        isOpen:       true,
        query:        'foo',
        results:      results,
        currentIndex: 0,
      );
      expect(state.statusText, '1 / 3');
    });
  });

  // ── DocumentCacheService (quick smoke test) ────────────────────────────────

  group('SearchResult model', () {
    test('length is charEnd - charStart', () {
      const r = SearchResult(
          blockId: 'b', charStart: 5, charEnd: 10, matchText: 'hello');
      expect(r.length, 5);
    });

    test('toString includes block id and match text', () {
      const r = SearchResult(
          blockId: 'blk_3', charStart: 0, charEnd: 3, matchText: 'abc');
      expect(r.toString(), contains('blk_3'));
      expect(r.toString(), contains('abc'));
    });
  });
}
