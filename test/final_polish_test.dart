import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:formuladoc/data/models/document_block.dart';
import 'package:formuladoc/data/models/document_model.dart';
import 'package:formuladoc/data/serializers/docx_serializer.dart';
import 'package:formuladoc/presentation/renderers/table_grid_normalizer.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

TableCell _cell(String text, {int colSpan = 1, int rowSpan = 1}) => TableCell(
      content: [
        ParagraphBlock(
          id:   'p_${text}_${colSpan}_$rowSpan',
          runs: [TextRun(text: text, style: TextRunStyle.empty)],
        ),
      ],
      properties: TableCellProperties(colSpan: colSpan, rowSpan: rowSpan),
    );

ParagraphBlock _para(String text, {String id = 'p1', String? url}) =>
    ParagraphBlock(
      id:   id,
      runs: [TextRun(text: text, style: TextRunStyle.empty, url: url)],
    );

DocumentModel _model(List<DocumentBlock> blocks) => DocumentModel(blocks: blocks);

Future<Map<String, String>> _unzipText(Uint8List bytes) async {
  final archive = ZipDecoder().decodeBytes(bytes);
  final files   = <String, String>{};
  for (final f in archive.files) {
    if (!f.isFile) continue;
    final content = f.content;
    if (content is List<int>) {
      files[f.name] = utf8.decode(content, allowMalformed: true);
    }
  }
  return files;
}

// ═══════════════════════════════════════════════════════════════════════════════
// TABLE GRID NORMALIZER  — prevents Flutter Table assertion crash
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  group('TableGridNormalizer', () {
    test('uniform rows are detected as already-uniform', () {
      final rows = [
        TableRow(cells: [_cell('A'), _cell('B')]),
        TableRow(cells: [_cell('C'), _cell('D')]),
      ];
      expect(TableGridNormalizer.isAlreadyUniform(rows), isTrue);
    });

    test('mismatched row lengths are detected as non-uniform', () {
      final rows = [
        TableRow(cells: [_cell('A'), _cell('B'), _cell('C')]),
        TableRow(cells: [_cell('Merged', colSpan: 2), _cell('D')]),
      ];
      expect(TableGridNormalizer.isAlreadyUniform(rows), isFalse);
    });

    test('computeColumnCount accounts for colSpan', () {
      final rows = [
        TableRow(cells: [_cell('A'), _cell('B'), _cell('C')]), // 3 cols
        TableRow(cells: [_cell('Merged', colSpan: 2), _cell('D')]), // 2+1=3
      ];
      expect(TableGridNormalizer.computeColumnCount(rows), 3);
    });

    test('normalize pads short rows to match column count', () {
      final rows = [
        TableRow(cells: [_cell('A'), _cell('B'), _cell('C')]), // 3 real cells
        TableRow(cells: [_cell('Merged', colSpan: 2)]),        // 1 real cell, spans 2
      ];
      final result = TableGridNormalizer.normalize(rows);

      // Every row must have the SAME cell count after normalization —
      // this is the exact invariant Flutter's Table widget requires.
      final counts = result.map((r) => r.cells.length).toSet();
      expect(counts.length, 1,
          reason: 'All rows must have equal cell counts after normalize()');
    });

    test('normalize is a no-op when already uniform', () {
      final rows = [
        TableRow(cells: [_cell('A'), _cell('B')]),
        TableRow(cells: [_cell('C'), _cell('D')]),
      ];
      final result = TableGridNormalizer.normalize(rows);
      expect(result[0].cells.length, 2);
      expect(result[1].cells.length, 2);
    });

    test('empty rows list returns empty', () {
      expect(TableGridNormalizer.normalize([]), isEmpty);
    });

    test('3-column table with one fully-merged header row stays consistent', () {
      // Common real-world case: header row has ONE cell spanning all 3 columns.
      final rows = [
        TableRow(cells: [_cell('Title', colSpan: 3)]),
        TableRow(cells: [_cell('A'), _cell('B'), _cell('C')]),
      ];
      final result = TableGridNormalizer.normalize(rows);
      expect(result[0].cells.length, result[1].cells.length);
      expect(result[0].cells.length, 3);
    });

    test('filler cells have empty content (invisible)', () {
      final rows = [
        TableRow(cells: [_cell('A'), _cell('B')]),
        TableRow(cells: [_cell('Merged', colSpan: 2)]),
      ];
      final result = TableGridNormalizer.normalize(rows);
      final fillerRow = result[1];
      expect(fillerRow.cells.last.content, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // DOCX SERIALIZER  — hyperlink relationship correctness
  // ═══════════════════════════════════════════════════════════════════════════

  group('DocxSerializer — hyperlinks', () {
    late DocxSerializer serializer;
    setUp(() => serializer = const DocxSerializer());

    test('inline TextRun.url produces a real relationship entry', () async {
      final model = _model([
        _para('Visit our site', id: 'p1', url: 'https://example.com'),
      ]);
      final bytes = await serializer.serialize(model);
      final files = await _unzipText(bytes);

      final docXml  = files['word/document.xml']!;
      final relsXml = files['word/_rels/document.xml.rels']!;

      // document.xml must reference a hyperlink rId
      expect(docXml, contains('<w:hyperlink r:id="rIdHlink0"'));
      // .rels must define that SAME rId pointing at the URL
      expect(relsXml, contains('Id="rIdHlink0"'));
      expect(relsXml, contains('Target="https://example.com"'));
    });

    test('standalone HyperlinkBlock also produces a relationship entry', () async {
      final model = _model([
        HyperlinkBlock(
          id:   'h1',
          url:  'https://flutter.dev',
          runs: [TextRun(text: 'Flutter', style: TextRunStyle.empty)],
        ),
      ]);
      final bytes  = await serializer.serialize(model);
      final files  = await _unzipText(bytes);
      final relsXml = files['word/_rels/document.xml.rels']!;

      expect(relsXml, contains('Target="https://flutter.dev"'));
    });

    test('two different hyperlinks get two distinct rIds', () async {
      final model = _model([
        _para('Link A', id: 'p1', url: 'https://a.com'),
        _para('Link B', id: 'p2', url: 'https://b.com'),
      ]);
      final bytes = await serializer.serialize(model);
      final files = await _unzipText(bytes);
      final relsXml = files['word/_rels/document.xml.rels']!;

      expect(relsXml, contains('rIdHlink0'));
      expect(relsXml, contains('rIdHlink1'));
      expect(relsXml, contains('https://a.com'));
      expect(relsXml, contains('https://b.com'));
    });

    test('plain text run without url produces no hyperlink wrapper', () async {
      final model = _model([_para('Just text', id: 'p1')]);
      final bytes = await serializer.serialize(model);
      final files = await _unzipText(bytes);
      expect(files['word/document.xml'], isNot(contains('<w:hyperlink')));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // DOCX SERIALIZER  — image relationship filename consistency
  // ═══════════════════════════════════════════════════════════════════════════

  group('DocxSerializer — images', () {
    late DocxSerializer serializer;
    setUp(() => serializer = const DocxSerializer());

    test('relationship Target matches the actual archived media file name', () async {
      // 8-byte minimal PNG-magic header so _guessExt resolves to png.
      final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]);
      final model = DocumentModel(
        blocks: [
          ImageBlock(id: 'img1', relationshipId: 'rId7'),
        ],
        images: {'rId7': pngBytes},
      );

      final bytes   = await serializer.serialize(model);
      final archive = ZipDecoder().decodeBytes(bytes);
      final relsXml = utf8.decode(
        (archive.files
                .firstWhere((f) => f.name == 'word/_rels/document.xml.rels')
                .content as List<int>),
        allowMalformed: true,
      );

      // Extract the Target="..." value referenced for rId7
      final match = RegExp(r'Id="rId7"[^>]*Target="([^"]+)"').firstMatch(relsXml);
      expect(match, isNotNull,
          reason: 'rId7 relationship must exist in document.xml.rels');
      final target   = match!.group(1)!;
      final fileName = target.replaceFirst('media/', '');

      // The exact same file name MUST exist in the archive under word/media/.
      final archivedNames =
          archive.files.where((f) => f.isFile).map((f) => f.name).toList();
      expect(archivedNames, contains('word/media/$fileName'),
          reason: 'Relationship Target "$target" must match an archived file '
              '— mismatch causes broken images on reopen');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // DOCX SERIALIZER  — equation round-trip fidelity
  // ═══════════════════════════════════════════════════════════════════════════

  group('DocxSerializer — equations', () {
    late DocxSerializer serializer;
    setUp(() => serializer = const DocxSerializer());

    test('original OMML is preserved verbatim, not flattened to text', () async {
      const omml = '<m:oMath xmlns:m="http://schemas.openxmlformats.org/'
          'officeDocument/2006/math"><m:r><m:t>x</m:t></m:r></m:oMath>';
      final model = _model([
        const EquationBlock(id: 'eq1', rawOmml: omml, latex: 'x'),
      ]);

      final bytes  = await serializer.serialize(model);
      final files  = await _unzipText(bytes);
      final docXml = files['word/document.xml']!;

      // The exact original OMML markup must appear, wrapped for round-trip.
      expect(docXml, contains('<m:oMathPara>'));
      expect(docXml, contains(omml));
    });

    test('equation with no OMML falls back to a labelled placeholder, not silence', () async {
      final model = _model([
        const EquationBlock(id: 'eq1', rawOmml: '', latex: null),
      ]);
      final bytes  = await serializer.serialize(model);
      final files  = await _unzipText(bytes);
      expect(files['word/document.xml'], contains('Equation'));
    });

    test('document.xml declares the math namespace at the root', () async {
      const omml = '<m:oMath><m:r><m:t>y</m:t></m:r></m:oMath>';
      final model = _model([const EquationBlock(id: 'eq1', rawOmml: omml)]);
      final bytes  = await serializer.serialize(model);
      final files  = await _unzipText(bytes);
      expect(
        files['word/document.xml'],
        contains('xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"'),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // DOCX SERIALIZER  — numbering.xml presence and references resolve
  // ═══════════════════════════════════════════════════════════════════════════

  group('DocxSerializer — numbering', () {
    late DocxSerializer serializer;
    setUp(() => serializer = const DocxSerializer());

    test('numbering.xml part is written to the archive', () async {
      final bytes  = await serializer.serialize(_model([_para('x')]));
      final files  = await _unzipText(bytes);
      expect(files.keys, contains('word/numbering.xml'));
    });

    test('numbering.xml defines numId 1 (bullet) and numId 2 (decimal)', () async {
      final bytes = await serializer.serialize(_model([_para('x')]));
      final files = await _unzipText(bytes);
      final xml   = files['word/numbering.xml']!;
      expect(xml, contains('w:numId="1"'));
      expect(xml, contains('w:numId="2"'));
      expect(xml, contains('bullet'));
      expect(xml, contains('decimal'));
    });

    test('bulleted ListBlock references numId 1', () async {
      final model = _model([
        ListBlock(
          id:        'list1',
          isOrdered: false,
          items: [
            ParagraphBlock(
              id:   'li1',
              runs: [TextRun(text: 'Item', style: TextRunStyle.empty)],
            ),
          ],
        ),
      ]);
      final bytes = await serializer.serialize(model);
      final files = await _unzipText(bytes);
      expect(files['word/document.xml'], contains('w:numId="1"'));
    });

    test('numbered ListBlock references numId 2', () async {
      final model = _model([
        ListBlock(
          id:        'list1',
          isOrdered: true,
          items: [
            ParagraphBlock(
              id:   'li1',
              runs: [TextRun(text: 'Step', style: TextRunStyle.empty)],
            ),
          ],
        ),
      ]);
      final bytes = await serializer.serialize(model);
      final files = await _unzipText(bytes);
      expect(files['word/document.xml'], contains('w:numId="2"'));
    });

    test('document.xml.rels references numbering.xml', () async {
      final bytes  = await serializer.serialize(_model([_para('x')]));
      final files  = await _unzipText(bytes);
      expect(files['word/_rels/document.xml.rels'], contains('numbering.xml'));
    });

    test('[Content_Types].xml declares numbering.xml override', () async {
      final bytes = await serializer.serialize(_model([_para('x')]));
      final files = await _unzipText(bytes);
      expect(files['[Content_Types].xml'], contains('/word/numbering.xml'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // DOCX SERIALIZER  — table cell schema validity
  // ═══════════════════════════════════════════════════════════════════════════

  group('DocxSerializer — tables', () {
    late DocxSerializer serializer;
    setUp(() => serializer = const DocxSerializer());

    test('empty table cell still emits a <w:p/> (schema requires it)', () async {
      final model = _model([
        TableBlock(
          id:   'tbl1',
          rows: [
            TableRow(cells: [const TableCell(content: [])]),
          ],
        ),
      ]);
      final bytes = await serializer.serialize(model);
      final files = await _unzipText(bytes);
      expect(files['word/document.xml'], contains('<w:tc>\n<w:p/>'));
    });

    test('vMerge continuation cell emits <w:vMerge/>', () async {
      final model = _model([
        TableBlock(
          id:   'tbl1',
          rows: [
            TableRow(cells: [_cell('Top', rowSpan: 1)]),
            TableRow(cells: [
              const TableCell(
                content:    [],
                properties: TableCellProperties(rowSpan: 0),
              ),
            ]),
          ],
        ),
      ]);
      final bytes = await serializer.serialize(model);
      final files = await _unzipText(bytes);
      expect(files['word/document.xml'], contains('<w:vMerge/>'));
    });
  });
}
