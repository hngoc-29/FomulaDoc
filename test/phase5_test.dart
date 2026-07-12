import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:formuladoc/core/errors/app_exception.dart';
import 'package:formuladoc/data/models/document_block.dart';
import 'package:formuladoc/data/models/document_edit.dart';
import 'package:formuladoc/data/models/document_model.dart';
import 'package:formuladoc/data/models/edit_history.dart';
import 'package:formuladoc/data/parsers/docx/docx_parser.dart';
import 'package:formuladoc/data/parsers/parser_registry.dart';
import 'package:formuladoc/data/serializers/docx_serializer.dart';
import 'package:formuladoc/domain/abstractions/document_format.dart';
import 'package:formuladoc/domain/abstractions/document_source.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

ParagraphBlock _para(String text, {String id = 'p1'}) => ParagraphBlock(
      id:   id,
      runs: [TextRun(text: text, style: TextRunStyle.empty)],
    );

HeadingBlock _h1(String text, {String id = 'h1'}) => HeadingBlock(
      id:    id,
      runs:  [TextRun(text: text, style: TextRunStyle.empty)],
      level: HeadingLevel.h1,
    );

DocumentModel _model(List<DocumentBlock> blocks) =>
    DocumentModel(blocks: blocks);

// ═══════════════════════════════════════════════════════════════════════════════

void main() {

  // ── Parser Registry ────────────────────────────────────────────────────────

  group('DocumentParserRegistry', () {
    late DocumentParserRegistry registry;

    setUp(() {
      // DocumentParserRegistry is a singleton (no public constructor) —
      // reuse the shared instance and re-register defaults idempotently.
      registry = DocumentParserRegistry.instance;
      registry.registerDefaults();
    });

    test('registerDefaults registers 4 formats', () {
      expect(registry.registeredCount, 4);
    });

    test('DOCX is the only currently supported format', () {
      expect(registry.supportedFormats, [DocumentFormat.docx]);
    });

    test('planned formats contains pdf, pptx, xlsx', () {
      final planned = registry.plannedFormats;
      expect(planned, containsAll([
        DocumentFormat.pdf,
        DocumentFormat.pptx,
        DocumentFormat.xlsx,
      ]));
    });

    test('forFormat returns DocxParser for docx', () {
      final parser = registry.forFormat(DocumentFormat.docx);
      expect(parser, isA<DocxParser>());
    });

    test('forSource detects format from .docx extension', () {
      final source = BytesDocumentSource(
        bytes: Uint8List(0),
        name:  'test.docx',
      );
      final parser = registry.forSource(source);
      expect(parser, isNotNull);
      expect(parser!.format, DocumentFormat.docx);
    });

    test('forSource returns null for unknown extension', () {
      final source = BytesDocumentSource(
        bytes: Uint8List(0),
        name:  'test.unknown',
      );
      expect(registry.forSource(source), isNull);
    });

    test('parse throws UnsupportedFormatException for .xyz', () {
      final source = BytesDocumentSource(
        bytes: Uint8List(0),
        name:  'test.xyz',
      );
      expect(
        () => registry.parse(source),
        throwsA(isA<UnsupportedFormatException>()),
      );
    });

    test('parsing PDF throws ParseException (not-yet-supported)', () async {
      final source = BytesDocumentSource(
        bytes: Uint8List(0),
        name:  'test.pdf',
      );
      expect(
        () => registry.parse(source),
        throwsA(isA<ParseException>()),
      );
    });

    test('custom parser can be registered', () {
      final before = registry.registeredCount;
      registry.register(const DocxParser()); // re-register same
      expect(registry.registeredCount, before); // count unchanged
    });

    test('supportedExtensions contains docx', () {
      expect(registry.supportedExtensions, contains('docx'));
    });
  });

  // ── DocumentFormat enum ────────────────────────────────────────────────────

  group('DocumentFormat', () {
    test('fromExtension docx', () {
      expect(DocumentFormatX.fromExtension('docx'), DocumentFormat.docx);
    });

    test('fromExtension pdf', () {
      expect(DocumentFormatX.fromExtension('pdf'), DocumentFormat.pdf);
    });

    test('fromExtension case-insensitive', () {
      expect(DocumentFormatX.fromExtension('DOCX'), DocumentFormat.docx);
    });

    test('fromExtension unknown returns null', () {
      expect(DocumentFormatX.fromExtension('abc'), isNull);
    });

    test('only docx isSupported', () {
      expect(DocumentFormat.docx.isSupported, isTrue);
      expect(DocumentFormat.pdf.isSupported, isFalse);
      expect(DocumentFormat.pptx.isSupported, isFalse);
      expect(DocumentFormat.xlsx.isSupported, isFalse);
    });
  });

  // ── Edit History ───────────────────────────────────────────────────────────

  group('EditHistory', () {
    late EditHistory history;

    setUp(() => history = EditHistory(maxDepth: 5));

    test('starts empty', () {
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
      expect(history.undoCount, 0);
    });

    test('record increments undo count', () {
      history.record(DeleteBlockEdit(
        blockId:       'b1',
        deletedBlock:  _para('x'),
        originalIndex: 0,
      ));
      expect(history.undoCount, 1);
      expect(history.canUndo, isTrue);
    });

    test('undo moves edit from undo→redo', () {
      final edit = DeleteBlockEdit(
          blockId: 'b1', deletedBlock: _para('x'), originalIndex: 0);
      history.record(edit);
      final undone = history.undo();
      expect(undone, same(edit));
      expect(history.undoCount, 0);
      expect(history.redoCount, 1);
      expect(history.canRedo, isTrue);
    });

    test('redo moves edit from redo→undo', () {
      history.record(DeleteBlockEdit(
          blockId: 'b1', deletedBlock: _para('x'), originalIndex: 0));
      history.undo();
      final redone = history.redo();
      expect(redone, isNotNull);
      expect(history.undoCount, 1);
      expect(history.redoCount, 0);
    });

    test('new edit clears redo stack', () {
      history.record(DeleteBlockEdit(
          blockId: 'b1', deletedBlock: _para('x'), originalIndex: 0));
      history.undo();
      expect(history.canRedo, isTrue);

      history.record(InsertBlockEdit(afterIndex: 0, block: _para('new')));
      expect(history.canRedo, isFalse);
    });

    test('respects maxDepth — evicts oldest', () {
      for (int i = 0; i < 7; i++) {
        history.record(InsertBlockEdit(afterIndex: i, block: _para('p$i')));
      }
      expect(history.undoCount, 5); // maxDepth = 5
    });

    test('clear empties both stacks', () {
      history.record(InsertBlockEdit(afterIndex: 0, block: _para('x')));
      history.clear();
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
    });

    test('undoDescription non-empty after record', () {
      history.record(InsertBlockEdit(afterIndex: 0, block: _para('x')));
      expect(history.undoDescription, isNotEmpty);
      expect(history.undoDescription, contains('Undo'));
    });

    test('undo returns null on empty stack', () {
      expect(history.undo(), isNull);
    });

    test('redo returns null on empty redo stack', () {
      expect(history.redo(), isNull);
    });
  });

  // ── DocumentEdit sealed hierarchy ─────────────────────────────────────────

  group('DocumentEdit descriptions', () {
    test('InsertTextEdit description contains text', () {
      const edit = InsertTextEdit(
        blockId: 'p1', runIndex: 0, charOffset: 0, text: 'hello');
      expect(edit.description, contains('hello'));
    });

    test('DeleteBlockEdit description includes block type', () {
      final edit = DeleteBlockEdit(
        blockId:       'h1',
        deletedBlock:  _h1('Title'),
        originalIndex: 0,
      );
      expect(edit.description.toLowerCase(), contains('heading'));
    });

    test('ApplyRunStyleEdit bold description', () {
      const edit = ApplyRunStyleEdit(
        blockId:      'p1',
        charStart:    0,
        charEnd:      5,
        newStyle:     TextRunStyle(bold: true),
        previousRuns: [],
      );
      expect(edit.description, 'Bold');
    });

    test('CompositeEdit uses provided description', () {
      const edit = CompositeEdit(
        edits:       [],
        description: 'Paste',
      );
      expect(edit.description, 'Paste');
    });
  });

  // ── DocxSerializer ─────────────────────────────────────────────────────────

  group('DocxSerializer', () {
    late DocxSerializer serializer;

    setUp(() => serializer = const DocxSerializer());

    Future<Map<String, String>> _serialize(DocumentModel model) async {
      final bytes   = await serializer.serialize(model);
      final archive = ZipDecoder().decodeBytes(bytes);
      final files   = <String, String>{};
      for (final f in archive.files) {
        if (f.isFile) {
          final content = f.content;
          if (content is List<int>) {
            files[f.name] = utf8.decode(content, allowMalformed: true);
          }
        }
      }
      return files;
    }

    test('produces valid ZIP (non-empty bytes)', () async {
      final bytes = await serializer.serialize(_model([_para('Hello')]));
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(100));
    });

    test('ZIP contains required DOCX entries', () async {
      final files = await _serialize(_model([_para('Hello')]));
      expect(files.keys, contains('[Content_Types].xml'));
      expect(files.keys, contains('_rels/.rels'));
      expect(files.keys, contains('word/document.xml'));
      expect(files.keys, contains('word/styles.xml'));
      expect(files.keys, contains('docProps/core.xml'));
    });

    test('document.xml contains paragraph text', () async {
      final files = await _serialize(_model([_para('Hello World')]));
      expect(files['word/document.xml'], contains('Hello World'));
    });

    test('bold run produces <w:b/> in XML', () async {
      final model = _model([
        ParagraphBlock(
          id:   'p1',
          runs: [TextRun(
            text:  'Bold text',
            style: const TextRunStyle(bold: true),
          )],
        ),
      ]);
      final files = await _serialize(model);
      expect(files['word/document.xml'], contains('<w:b/>'));
    });

    test('heading produces correct styleId', () async {
      final model = _model([_h1('Introduction')]);
      final files = await _serialize(model);
      final docXml = files['word/document.xml']!;
      expect(docXml, contains('Heading1'));
      expect(docXml, contains('Introduction'));
    });

    test('page break produces <w:br w:type="page"/>', () async {
      final model = _model([
        _para('Before'),
        const PageBreakBlock(id: 'pb1'),
        _para('After'),
      ]);
      final files = await _serialize(model);
      expect(files['word/document.xml'],
          contains('w:type="page"'));
    });

    test('table produces <w:tbl>', () async {
      final model = _model([
        TableBlock(
          id: 'tbl1',
          rows: [
            TableRow(cells: [
              TableCell(content: [_para('Cell A', id: 'ca')]),
              TableCell(content: [_para('Cell B', id: 'cb')]),
            ]),
          ],
        ),
      ]);
      final files = await _serialize(model);
      expect(files['word/document.xml'], contains('<w:tbl>'));
      expect(files['word/document.xml'], contains('Cell A'));
      expect(files['word/document.xml'], contains('Cell B'));
    });

    test('metadata written to core.xml', () async {
      const meta = DocumentMetadata(title: 'My Doc', author: 'Alice');
      final model = DocumentModel(blocks: [_para('text')], metadata: meta);
      final files = await _serialize(model);
      expect(files['docProps/core.xml'], contains('My Doc'));
      expect(files['docProps/core.xml'], contains('Alice'));
    });

    test('font size serialized as half-points', () async {
      final model = _model([
        ParagraphBlock(
          id:   'p1',
          runs: [TextRun(
            text:  'Big',
            style: const TextRunStyle(fontSizePt: 24),
          )],
        ),
      ]);
      final files = await _serialize(model);
      // 24pt × 2 = 48 half-points
      expect(files['word/document.xml'], contains('w:val="48"'));
    });

    test('colour serialized as uppercase 6-char hex', () async {
      final model = _model([
        ParagraphBlock(
          id:   'p1',
          runs: [TextRun(
            text:  'Red',
            style: const TextRunStyle(colorArgb: 0xFFFF0000),
          )],
        ),
      ]);
      final files = await _serialize(model);
      expect(files['word/document.xml'], contains('FF0000'));
    });

    test('round-trip: serialize then re-parse restores paragraphs', () async {
      final original = _model([
        _para('First paragraph',  id: 'p1'),
        _para('Second paragraph', id: 'p2'),
        _h1('My Heading',         id: 'h1'),
      ]);

      // Serialize to DOCX bytes
      final bytes = await serializer.serialize(original);

      // Re-parse with DocxParser
      final source   = BytesDocumentSource(bytes: bytes, name: 'test.docx');
      final reparsed = await const DocxParser().parse(source);

      // Should have at least the same number of non-empty blocks
      final nonEmpty = reparsed.blocks
          .whereType<ParagraphBlock>()
          .where((p) => !p.isEmpty)
          .length;
      expect(nonEmpty, greaterThanOrEqualTo(2));

      // Heading should survive the round-trip
      expect(reparsed.blocks.whereType<HeadingBlock>(), isNotEmpty);
    });
  });
}
