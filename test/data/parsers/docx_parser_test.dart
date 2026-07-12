import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:formuladoc/data/models/document_block.dart';
import 'package:formuladoc/data/models/document_model.dart';
import 'package:formuladoc/data/parsers/docx/docx_extractor.dart';
import 'package:formuladoc/data/parsers/docx/numbering_parser.dart';
import 'package:formuladoc/data/parsers/docx/style_resolver.dart';
import 'package:formuladoc/data/parsers/docx/xml_body_parser.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

Uint8List _buildDocx({
  required String documentXml,
  String? stylesXml,
  String? relsXml,
  String? numberingXml,
}) {
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  add('word/document.xml', documentXml);
  if (stylesXml    != null) add('word/styles.xml',                   stylesXml);
  if (relsXml      != null) add('word/_rels/document.xml.rels',      relsXml);
  if (numberingXml != null) add('word/numbering.xml',                 numberingXml);
  final zipBytes = ZipEncoder().encode(archive);
  return Uint8List.fromList(zipBytes!);
}

const _ns =
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"';

String _doc(String body) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<w:document $_ns><w:body>$body<w:sectPr/></w:body></w:document>';

DocumentModel _parse(String body,
    {String? stylesXml, String? relsXml, String? numberingXml}) {
  final bytes = _buildDocx(
    documentXml: _doc(body),
    stylesXml:   stylesXml,
    relsXml:     relsXml,
    numberingXml: numberingXml,
  );
  final extracted = DocxExtractor().extract(bytes);
  final numbering = NumberingParser(extracted.numberingXml);
  return XmlBodyParser(extracted, numberingParser: numbering).parse();
}

// ═══════════════════════════════════════════════════════════════════════════════
// PHASE 1 tests (regression)
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  group('DocxExtractor', () {
    test('extracts document.xml', () {
      final bytes = _buildDocx(documentXml: _doc('<w:p/>'));
      expect(DocxExtractor().extract(bytes).documentXml, contains('<w:document'));
    });

    test('throws on non-DOCX bytes', () {
      expect(
        () => DocxExtractor().extract(Uint8List.fromList(utf8.encode('not a zip'))),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Paragraph parsing', () {
    test('simple text paragraph', () {
      final m = _parse('<w:p><w:r><w:t>Hello</w:t></w:r></w:p>');
      expect((m.blocks.first as ParagraphBlock).plainText, 'Hello');
    });

    test('bold run', () {
      final m = _parse('<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Bold</w:t></w:r></w:p>');
      expect((m.blocks.first as ParagraphBlock).runs.first.style.bold, isTrue);
    });

    test('italic run', () {
      final m = _parse('<w:p><w:r><w:rPr><w:i/></w:rPr><w:t>Ital</w:t></w:r></w:p>');
      expect((m.blocks.first as ParagraphBlock).runs.first.style.italic, isTrue);
    });

    test('underline run', () {
      final m = _parse('<w:p><w:r><w:rPr><w:u w:val="single"/></w:rPr><w:t>U</w:t></w:r></w:p>');
      expect((m.blocks.first as ParagraphBlock).runs.first.style.underline, isTrue);
    });

    test('strikethrough run', () {
      final m = _parse('<w:p><w:r><w:rPr><w:strike/></w:rPr><w:t>S</w:t></w:r></w:p>');
      expect((m.blocks.first as ParagraphBlock).runs.first.style.strikethrough, isTrue);
    });

    test('font size half-points → pt', () {
      final m = _parse('<w:p><w:r><w:rPr><w:sz w:val="24"/></w:rPr><w:t>X</w:t></w:r></w:p>');
      expect((m.blocks.first as ParagraphBlock).runs.first.style.fontSizePt, closeTo(12.0, 0.01));
    });

    test('text color hex → ARGB', () {
      final m = _parse('<w:p><w:r><w:rPr><w:color w:val="FF0000"/></w:rPr><w:t>R</w:t></w:r></w:p>');
      expect((m.blocks.first as ParagraphBlock).runs.first.style.colorArgb, 0xFFFF0000);
    });

    test('paragraph order preserved', () {
      final m = _parse(
        '<w:p><w:r><w:t>A</w:t></w:r></w:p>'
        '<w:p><w:r><w:t>B</w:t></w:r></w:p>',
      );
      final texts = m.blocks.whereType<ParagraphBlock>().map((p) => p.plainText).toList();
      expect(texts, ['A', 'B']);
    });

    test('page break paragraph → PageBreakBlock', () {
      final m = _parse('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
      expect(m.blocks.first, isA<PageBreakBlock>());
    });

    test('unknown body element skipped gracefully', () {
      final m = _parse(
        '<w:unknownElement/>'
        '<w:p><w:r><w:t>OK</w:t></w:r></w:p>',
      );
      expect(m.blocks, hasLength(1));
    });
  });

  group('Heading parsing', () {
    const stylesXml = '<?xml version="1.0"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:style w:type="paragraph" w:styleId="Heading1">'
        '<w:name w:val="heading 1"/></w:style>'
        '<w:style w:type="paragraph" w:styleId="Heading2">'
        '<w:name w:val="heading 2"/></w:style>'
        '</w:styles>';

    test('Heading1 style → HeadingBlock h1', () {
      final m = _parse(
        '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
        '<w:r><w:t>Title</w:t></w:r></w:p>',
        stylesXml: stylesXml,
      );
      final h = m.blocks.first as HeadingBlock;
      expect(h.level, HeadingLevel.h1);
      expect(h.plainText, 'Title');
    });

    test('Heading2 style → HeadingBlock h2', () {
      final m = _parse(
        '<w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr>'
        '<w:r><w:t>Sub</w:t></w:r></w:p>',
        stylesXml: stylesXml,
      );
      expect((m.blocks.first as HeadingBlock).level, HeadingLevel.h2);
    });
  });

  group('Equation parsing', () {
    test('oMathPara → EquationBlock (block-level)', () {
      final m = _parse(
        '<w:p><m:oMathPara>'
        '<m:oMath><m:r><m:t>x</m:t></m:r></m:oMath>'
        '</m:oMathPara></w:p>',
      );
      final eq = m.blocks.first as EquationBlock;
      expect(eq.isInline, isFalse);
      expect(eq.rawOmml, isNotEmpty);
      expect(eq.hasLatex, isFalse); // Phase 1 — latex is null
    });
  });

  group('Table parsing', () {
    test('2×2 table → TableBlock', () {
      final m = _parse(
        '<w:tbl>'
        '<w:tr>'
        '<w:tc><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc>'
        '<w:tc><w:p><w:r><w:t>B</w:t></w:r></w:p></w:tc>'
        '</w:tr>'
        '<w:tr>'
        '<w:tc><w:p><w:r><w:t>C</w:t></w:r></w:p></w:tc>'
        '<w:tc><w:p><w:r><w:t>D</w:t></w:r></w:p></w:tc>'
        '</w:tr>'
        '</w:tbl>',
      );
      final tbl = m.blocks.first as TableBlock;
      expect(tbl.rowCount, 2);
      expect(tbl.columnCount, 2);
    });

    test('cell with colspan → colSpan property set', () {
      final m = _parse(
        '<w:tbl><w:tr>'
        '<w:tc><w:tcPr><w:gridSpan w:val="2"/></w:tcPr>'
        '<w:p><w:r><w:t>Merged</w:t></w:r></w:p></w:tc>'
        '</w:tr></w:tbl>',
      );
      final tbl = m.blocks.first as TableBlock;
      expect(tbl.rows.first.cells.first.properties.colSpan, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 2 tests
  // ═══════════════════════════════════════════════════════════════════════════

  group('Phase 2 — hyperlinks', () {
    test('hyperlink run carries url', () {
      const relsXml =
          '<?xml version="1.0"?><Relationships '
          'xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" '
          'Target="https://example.com" TargetMode="External"/>'
          '</Relationships>';

      final m = _parse(
        '<w:p>'
        '<w:hyperlink r:id="rId1">'
        '<w:r><w:rPr><w:rStyle w:val="Hyperlink"/></w:rPr>'
        '<w:t>Click here</w:t></w:r>'
        '</w:hyperlink>'
        '</w:p>',
        relsXml: relsXml,
      );
      final para = m.blocks.first as ParagraphBlock;
      expect(para.runs.first.url, 'https://example.com');
      expect(para.runs.first.isHyperlink, isTrue);
    });
  });

  group('Phase 2 — lists', () {
    const numberingXml = '<?xml version="1.0"?>'
        '<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:abstractNum w:abstractNumId="0">'
        '<w:lvl w:ilvl="0"><w:start w:val="1"/>'
        '<w:numFmt w:val="bullet"/><w:lvlText w:val="•"/></w:lvl>'
        '</w:abstractNum>'
        '<w:abstractNum w:abstractNumId="1">'
        '<w:lvl w:ilvl="0"><w:start w:val="1"/>'
        '<w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl>'
        '</w:abstractNum>'
        '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
        '<w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>'
        '</w:numbering>';

    test('bullet list → ListBlock (unordered)', () {
      final m = _parse(
        '<w:p><w:pPr><w:numPr>'
        '<w:ilvl w:val="0"/><w:numId w:val="1"/>'
        '</w:numPr></w:pPr><w:r><w:t>Item A</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:numPr>'
        '<w:ilvl w:val="0"/><w:numId w:val="1"/>'
        '</w:numPr></w:pPr><w:r><w:t>Item B</w:t></w:r></w:p>',
        numberingXml: numberingXml,
      );
      final list = m.blocks.whereType<ListBlock>().first;
      expect(list.isOrdered, isFalse);
      expect(list.items, hasLength(2));
    });

    test('numbered list → ListBlock (ordered)', () {
      final m = _parse(
        '<w:p><w:pPr><w:numPr>'
        '<w:ilvl w:val="0"/><w:numId w:val="2"/>'
        '</w:numPr></w:pPr><w:r><w:t>Step 1</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:numPr>'
        '<w:ilvl w:val="0"/><w:numId w:val="2"/>'
        '</w:numPr></w:pPr><w:r><w:t>Step 2</w:t></w:r></w:p>',
        numberingXml: numberingXml,
      );
      final list = m.blocks.whereType<ListBlock>().first;
      expect(list.isOrdered, isTrue);
      expect(list.items, hasLength(2));
    });

    test('separate numId groups → separate ListBlocks', () {
      final m = _parse(
        '<w:p><w:pPr><w:numPr>'
        '<w:ilvl w:val="0"/><w:numId w:val="1"/>'
        '</w:numPr></w:pPr><w:r><w:t>Bullet</w:t></w:r></w:p>'
        '<w:p><w:r><w:t>Normal</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:numPr>'
        '<w:ilvl w:val="0"/><w:numId w:val="2"/>'
        '</w:numPr></w:pPr><w:r><w:t>Number</w:t></w:r></w:p>',
        numberingXml: numberingXml,
      );
      expect(m.blocks.whereType<ListBlock>(), hasLength(2));
    });
  });

  group('Phase 2 — NumberingParser', () {
    const xml = '<?xml version="1.0"?>'
        '<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:abstractNum w:abstractNumId="0">'
        '<w:lvl w:ilvl="0"><w:numFmt w:val="decimal"/><w:start w:val="1"/></w:lvl>'
        '<w:lvl w:ilvl="1"><w:numFmt w:val="bullet"/></w:lvl>'
        '</w:abstractNum>'
        '<w:num w:numId="3"><w:abstractNumId w:val="0"/></w:num>'
        '</w:numbering>';

    test('decimal numFmt → isOrdered = true', () {
      expect(NumberingParser(xml).isOrdered(3, 0), isTrue);
    });

    test('bullet numFmt → isOrdered = false', () {
      expect(NumberingParser(xml).isOrdered(3, 1), isFalse);
    });

    test('unknown numId → isOrdered = false (safe default)', () {
      expect(NumberingParser(xml).isOrdered(99, 0), isFalse);
    });

    test('null xml → no crash', () {
      expect(() => NumberingParser(null), returnsNormally);
    });
  });

  group('DocumentModel', () {
    test('equationCount correct', () {
      final m = DocumentModel(blocks: [
        ParagraphBlock(id: 'p1', runs: const []),
        EquationBlock(id: 'e1', rawOmml: '<m:oMath/>'),
        EquationBlock(id: 'e2', rawOmml: '<m:oMath/>'),
      ]);
      expect(m.equationCount, 2);
    });

    test('isEmpty when no blocks', () {
      expect(const DocumentModel(blocks: []).isEmpty, isTrue);
    });
  });
}
