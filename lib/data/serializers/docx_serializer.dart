import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/document_block.dart';
import '../models/document_model.dart';
import '../../core/utils/logger.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SERIALIZATION CONTEXT
// ═══════════════════════════════════════════════════════════════════════════════

/// Mutable state threaded through a single [DocxSerializer.serialize] call.
///
/// Hyperlink relationship IDs must be assigned *during* document-body
/// generation (we only know which URLs exist once we walk the blocks), then
/// written into `word/_rels/document.xml.rels` afterwards. Collecting them
/// in one traversal — rather than walking the tree twice — guarantees the
/// IDs referenced in `document.xml` and the IDs defined in the `.rels` file
/// can never drift apart.
class _SerializationContext {
  /// Ordered list of hyperlink URLs encountered, index = rId suffix.
  final List<String> hyperlinkUrls = [];

  /// Registers [url] and returns the relationship ID to reference it by.
  /// The same URL appearing twice gets two distinct rIds — OOXML does not
  /// require de-duplication and keeping it simple avoids subtle aliasing bugs.
  String registerHyperlink(String url) {
    final id = 'rIdHlink${hyperlinkUrls.length}';
    hyperlinkUrls.add(url);
    return id;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DOCX SERIALIZER
// ═══════════════════════════════════════════════════════════════════════════════

/// Serializes a [DocumentModel] into a valid DOCX (ZIP) byte stream.
///
/// Enables round-trip editing:
///   Open DOCX → [DocxParser] → [DocumentModel]
///   Edit via [DocumentEdit] operations ([EditorNotifier])
///   Save → [DocxSerializer] → DOCX bytes → write to file
///
/// Output coverage:
///   ✅ Paragraphs — bold, italic, underline, strikethrough, sub/superscript
///   ✅ Font size and colour
///   ✅ Paragraph alignment and spacing
///   ✅ Headings H1–H6 (Word-recognised style IDs)
///   ✅ Page breaks
///   ✅ Numbered and bulleted lists, backed by a real `word/numbering.xml`
///   ✅ Tables, including `gridSpan` (column merge); `vMerge` continuation
///      cells round-trip, but the *restart* marker of a vertical merge is
///      not currently distinguishable from a plain cell in [TableCellProperties]
///      — documented limitation, not a silent failure.
///   ✅ Document metadata (title, author, description, dates)
///   ✅ Images — embedded in `word/media/` with matching relationship targets
///   ✅ Equations — original OMML is preserved verbatim and re-wrapped in
///      `<m:oMathPara>` so it survives a save→reopen cycle even though the
///      app cannot yet *edit* equations
///   ✅ Hyperlinks — both standalone [HyperlinkBlock]s and inline
///      [TextRun.url] runs get real `<w:hyperlink>` + relationship entries
class DocxSerializer {
  const DocxSerializer();

  // ── Entry point ───────────────────────────────────────────────────────────

  /// Converts [model] into DOCX-format bytes ready for file writing.
  Future<Uint8List> serialize(DocumentModel model) async {
    AppLogger.info(
      'Serializing ${model.blockCount} blocks → DOCX',
      tag: 'DocxSerializer',
    );

    final ctx     = _SerializationContext();
    final docXml  = _documentXml(model, ctx); // populates ctx.hyperlinkUrls

    final archive = Archive();
    _addEntry(archive, '[Content_Types].xml', _contentTypes());
    _addEntry(archive, '_rels/.rels',         _rootRels());
    _addEntry(archive, 'word/document.xml',   docXml);
    _addEntry(archive, 'word/styles.xml',     _stylesXml());
    _addEntry(archive, 'word/numbering.xml',  _numberingXml());
    _addEntry(archive, 'word/_rels/document.xml.rels', _documentRels(model, ctx));
    _addEntry(archive, 'docProps/core.xml',   _corePropsXml(model.metadata));

    // Embed image media files — filename MUST match the Target written in
    // _documentRels (both derive from `_mediaFileName`), or Word/our own
    // parser will show broken-image placeholders on reopen.
    for (final entry in model.images.entries) {
      final fileName = _mediaFileName(entry.key, entry.value);
      archive.addFile(
        ArchiveFile('word/media/$fileName', entry.value.length, entry.value),
      );
    }

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) throw StateError('ZipEncoder returned null');

    AppLogger.info(
      'DOCX serialized: ${zipBytes.length} bytes, '
      '${ctx.hyperlinkUrls.length} hyperlink(s)',
      tag: 'DocxSerializer',
    );
    return Uint8List.fromList(zipBytes);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // XML TEMPLATES — package / relationship / metadata parts
  // ═══════════════════════════════════════════════════════════════════════════

  String _contentTypes() => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml"  ContentType="application/xml"/>
  <Default Extension="png"  ContentType="image/png"/>
  <Default Extension="jpg"  ContentType="image/jpeg"/>
  <Default Extension="jpeg" ContentType="image/jpeg"/>
  <Default Extension="gif"  ContentType="image/gif"/>
  <Override PartName="/word/document.xml"
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml"
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
  <Override PartName="/word/numbering.xml"
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
  <Override PartName="/docProps/core.xml"
    ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
</Types>''';

  String _rootRels() => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
</Relationships>''';

  String _documentRels(DocumentModel model, _SerializationContext ctx) {
    final buf = StringBuffer('''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
  <Relationship Id="rIdNumbering" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
''');

    // Image relationships — Target MUST match the file name written by
    // [_mediaFileName] in [serialize], or the image breaks on reopen.
    for (final rId in model.images.keys) {
      final fileName = _mediaFileName(rId, model.images[rId]!);
      buf.writeln(
        '  <Relationship Id="$rId" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
        'Target="media/$fileName"/>',
      );
    }

    // Hyperlink relationships — IDs assigned during document.xml generation.
    for (int i = 0; i < ctx.hyperlinkUrls.length; i++) {
      buf.writeln(
        '  <Relationship Id="rIdHlink$i" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" '
        'Target="${_esc(ctx.hyperlinkUrls[i])}" TargetMode="External"/>',
      );
    }

    buf.write('</Relationships>');
    return buf.toString();
  }

  String _corePropsXml(DocumentMetadata meta) {
    final now = DateTime.now().toIso8601String();
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
                   xmlns:dc="http://purl.org/dc/elements/1.1/"
                   xmlns:dcterms="http://purl.org/dc/terms/">
  <dc:title>${_esc(meta.title ?? '')}</dc:title>
  <dc:creator>${_esc(meta.author ?? '')}</dc:creator>
  <dc:description>${_esc(meta.description ?? '')}</dc:description>
  <dcterms:created xsi:type="dcterms:W3CDTF"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">${meta.created?.toIso8601String() ?? now}</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">$now</dcterms:modified>
  <cp:revision>1</cp:revision>
</cp:coreProperties>''';
  }

  String _stylesXml() => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr>
    <w:rPr><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>
    <w:rPr><w:b/><w:sz w:val="36"/><w:color w:val="1F3864"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="heading 2"/><w:basedOn w:val="Normal"/>
    <w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="2E4057"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading3">
    <w:name w:val="heading 3"/><w:basedOn w:val="Normal"/>
    <w:rPr><w:b/><w:sz w:val="24"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading4">
    <w:name w:val="heading 4"/><w:basedOn w:val="Normal"/>
    <w:rPr><w:b/><w:sz w:val="22"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading5">
    <w:name w:val="heading 5"/><w:basedOn w:val="Normal"/>
    <w:rPr><w:b/><w:sz w:val="20"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading6">
    <w:name w:val="heading 6"/><w:basedOn w:val="Normal"/>
    <w:rPr><w:b/><w:sz w:val="18"/></w:rPr>
  </w:style>
  <w:style w:type="character" w:styleId="Hyperlink">
    <w:name w:val="Hyperlink"/>
    <w:rPr><w:color w:val="1565C0"/><w:u w:val="single"/></w:rPr>
  </w:style>
  <w:style w:type="table" w:styleId="TableGrid">
    <w:name w:val="Table Grid"/>
    <w:tblPr>
      <w:tblBorders>
        <w:top w:val="single" w:sz="4" w:color="CCCCCC"/>
        <w:left w:val="single" w:sz="4" w:color="CCCCCC"/>
        <w:bottom w:val="single" w:sz="4" w:color="CCCCCC"/>
        <w:right w:val="single" w:sz="4" w:color="CCCCCC"/>
        <w:insideH w:val="single" w:sz="4" w:color="CCCCCC"/>
        <w:insideV w:val="single" w:sz="4" w:color="CCCCCC"/>
      </w:tblBorders>
    </w:tblPr>
  </w:style>
</w:styles>''';

  /// Minimal but valid numbering definitions backing `numId="1"` (bullet)
  /// and `numId="2"` (decimal), referenced by [_listToXml]. Without this
  /// part, `<w:numId>` references in the body resolve to nothing and Word
  /// silently drops the list formatting on open.
  String _numberingXml() => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:abstractNum w:abstractNumId="0">
    ${List.generate(9, (i) => '<w:lvl w:ilvl="$i"><w:start w:val="1"/>'
        '<w:numFmt w:val="bullet"/><w:lvlText w:val="•"/>'
        '<w:lvlJc w:val="left"/>'
        '<w:pPr><w:ind w:left="${(i + 1) * 360}" w:hanging="360"/></w:pPr>'
        '</w:lvl>').join()}
  </w:abstractNum>
  <w:abstractNum w:abstractNumId="1">
    ${List.generate(9, (i) => '<w:lvl w:ilvl="$i"><w:start w:val="1"/>'
        '<w:numFmt w:val="decimal"/><w:lvlText w:val="%${i + 1}."/>'
        '<w:lvlJc w:val="left"/>'
        '<w:pPr><w:ind w:left="${(i + 1) * 360}" w:hanging="360"/></w:pPr>'
        '</w:lvl>').join()}
  </w:abstractNum>
  <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
  <w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>
</w:numbering>''';

  // ═══════════════════════════════════════════════════════════════════════════
  // DOCUMENT BODY
  // ═══════════════════════════════════════════════════════════════════════════

  String _documentXml(DocumentModel model, _SerializationContext ctx) {
    final buf = StringBuffer('''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
            xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
            xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math">
<w:body>
''');

    for (final block in model.blocks) {
      buf.write(_blockToXml(block, model, ctx));
    }

    buf.write('''<w:sectPr>
  <w:pgSz w:w="12240" w:h="15840"/>
  <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"
           w:header="720" w:footer="720" w:gutter="0"/>
</w:sectPr>
</w:body>
</w:document>''');
    return buf.toString();
  }

  String _blockToXml(
    DocumentBlock block,
    DocumentModel model,
    _SerializationContext ctx,
  ) =>
      switch (block) {
        ParagraphBlock()  => _paragraphToXml(block, ctx),
        HeadingBlock()    => _headingToXml(block, ctx),
        PageBreakBlock()  => _pageBreakXml(),
        TableBlock()      => _tableToXml(block, model, ctx),
        ListBlock()       => _listToXml(block, ctx),
        EquationBlock()   => _equationToXml(block),
        ImageBlock()      => _imagePlaceholderXml(block),
        HyperlinkBlock()    => _standaloneHyperlinkXml(block, ctx),
        // PDF and XLSX blocks are view-only — not serializable to DOCX
        PdfDocumentBlock()  => '',
        SpreadsheetBlock()  => '',
      };

  // ── Paragraph ─────────────────────────────────────────────────────────────

  String _paragraphToXml(ParagraphBlock block, _SerializationContext ctx) {
    final buf = StringBuffer('<w:p>');
    buf.write(_paragraphPropsXml(block.properties));
    buf.write(_runsToXml(block.runs, ctx));
    buf.write('</w:p>\n');
    return buf.toString();
  }

  String _paragraphPropsXml(ParagraphProperties p, {String? styleId}) {
    final buf = StringBuffer('<w:pPr>');
    if (styleId != null) buf.write('<w:pStyle w:val="$styleId"/>');
    if (p.alignment != ParagraphAlignment.left) {
      buf.write('<w:jc w:val="${_jcVal(p.alignment)}"/>');
    }
    final beforeTwip = (p.spaceBeforePt * 20).round();
    final afterTwip  = (p.spaceAfterPt  * 20).round();
    if (beforeTwip != 0 || afterTwip != 160) {
      buf.write('<w:spacing w:before="$beforeTwip" w:after="$afterTwip"/>');
    }
    if (p.indentLeftPt != 0 || p.indentRightPt != 0) {
      final left  = (p.indentLeftPt  * 20).round();
      final right = (p.indentRightPt * 20).round();
      buf.write('<w:ind w:left="$left" w:right="$right"/>');
    }
    buf.write('</w:pPr>');
    return buf.toString();
  }

  // ── Heading ───────────────────────────────────────────────────────────────

  String _headingToXml(HeadingBlock block, _SerializationContext ctx) {
    final styleId = switch (block.level) {
      HeadingLevel.h1 => 'Heading1',
      HeadingLevel.h2 => 'Heading2',
      HeadingLevel.h3 => 'Heading3',
      HeadingLevel.h4 => 'Heading4',
      HeadingLevel.h5 => 'Heading5',
      HeadingLevel.h6 => 'Heading6',
    };
    final buf = StringBuffer('<w:p>');
    buf.write(_paragraphPropsXml(block.properties, styleId: styleId));
    buf.write(_runsToXml(block.runs, ctx));
    buf.write('</w:p>\n');
    return buf.toString();
  }

  // ── Runs (grouping consecutive hyperlink runs into <w:hyperlink>) ─────────

  /// Converts [runs] to XML, wrapping consecutive runs that share the same
  /// non-null [TextRun.url] in a single `<w:hyperlink>` element — mirroring
  /// how [XmlBodyParser._parseHyperlinkRuns] reads them back in reverse.
  String _runsToXml(List<TextRun> runs, _SerializationContext ctx) {
    final buf = StringBuffer();
    int i = 0;
    while (i < runs.length) {
      final url = runs[i].url;
      if (url == null || url.isEmpty) {
        buf.write(_runToXml(runs[i]));
        i++;
        continue;
      }
      // Collect the consecutive run-group sharing this exact URL.
      final group = <TextRun>[];
      while (i < runs.length && runs[i].url == url) {
        group.add(runs[i]);
        i++;
      }
      final rId = ctx.registerHyperlink(url);
      buf.write('<w:hyperlink r:id="$rId" w:history="1">');
      for (final r in group) {
        buf.write(_runToXml(r));
      }
      buf.write('</w:hyperlink>');
    }
    return buf.toString();
  }

  // ── Text run ──────────────────────────────────────────────────────────────

  String _runToXml(TextRun run) {
    final buf = StringBuffer('<w:r>');
    final s = run.style;

    final hasProps = s.bold || s.italic || s.underline || s.strikethrough ||
        s.superscript || s.subscript ||
        s.fontSizePt != null || s.colorArgb != null || s.fontFamily != null;

    if (hasProps) {
      buf.write('<w:rPr>');
      if (s.bold)          buf.write('<w:b/>');
      if (s.italic)        buf.write('<w:i/>');
      if (s.underline)     buf.write('<w:u w:val="single"/>');
      if (s.strikethrough) buf.write('<w:strike/>');
      if (s.superscript)   buf.write('<w:vertAlign w:val="superscript"/>');
      if (s.subscript)     buf.write('<w:vertAlign w:val="subscript"/>');
      if (s.fontSizePt != null) {
        final hp = (s.fontSizePt! * 2).round();
        buf.write('<w:sz w:val="$hp"/><w:szCs w:val="$hp"/>');
      }
      if (s.colorArgb != null) {
        final hex = (s.colorArgb! & 0xFFFFFF)
            .toRadixString(16)
            .padLeft(6, '0')
            .toUpperCase();
        buf.write('<w:color w:val="$hex"/>');
      }
      if (s.fontFamily != null) {
        buf.write('<w:rFonts w:ascii="${_esc(s.fontFamily!)}" '
            'w:hAnsi="${_esc(s.fontFamily!)}"/>');
      }
      buf.write('</w:rPr>');
    }

    final text = run.text;
    if (text == '\t') {
      buf.write('<w:tab/>');
    } else if (text == '\n') {
      buf.write('<w:br/>');
    } else {
      buf.write('<w:t xml:space="preserve">${_esc(text)}</w:t>');
    }

    buf.write('</w:r>');
    return buf.toString();
  }

  // ── Page break ────────────────────────────────────────────────────────────

  String _pageBreakXml() =>
      '<w:p><w:r><w:br w:type="page"/></w:r></w:p>\n';

  // ── Table ─────────────────────────────────────────────────────────────────

  String _tableToXml(
    TableBlock block,
    DocumentModel model,
    _SerializationContext ctx,
  ) {
    final buf = StringBuffer('<w:tbl>\n');
    buf.write('<w:tblPr><w:tblStyle w:val="TableGrid"/>'
        '<w:tblW w:w="0" w:type="auto"/></w:tblPr>\n');
    for (final row in block.rows) {
      buf.write('<w:tr>\n');
      for (final cell in row.cells) {
        buf.write('<w:tc>\n');

        final hasGridSpan = cell.properties.colSpan > 1;
        final isContinuation = cell.properties.rowSpan == 0;
        if (hasGridSpan || isContinuation) {
          buf.write('<w:tcPr>');
          if (hasGridSpan) {
            buf.write('<w:gridSpan w:val="${cell.properties.colSpan}"/>');
          }
          if (isContinuation) {
            // Vertical-merge continuation. NOTE: the *restart* cell directly
            // above is not distinguishable from a plain cell in our current
            // TableCellProperties model (both report rowSpan == 1), so the
            // restart marker itself is not re-emitted — a documented
            // limitation rather than a silent failure.
            buf.write('<w:vMerge/>');
          }
          buf.write('</w:tcPr>\n');
        }

        for (final b in cell.content) {
          buf.write(_blockToXml(b, model, ctx));
        }
        // OOXML requires at least one <w:p> per cell, even if empty.
        if (cell.content.isEmpty) buf.write('<w:p/>\n');
        buf.write('</w:tc>\n');
      }
      buf.write('</w:tr>\n');
    }
    buf.write('</w:tbl>\n');
    return buf.toString();
  }

  // ── List ──────────────────────────────────────────────────────────────────

  String _listToXml(ListBlock block, _SerializationContext ctx) {
    final buf = StringBuffer();
    for (final item in block.items) {
      buf.write('<w:p>');
      buf.write('<w:pPr>');
      buf.write('<w:numPr>'
          '<w:ilvl w:val="${block.level}"/>'
          '<w:numId w:val="${block.isOrdered ? 2 : 1}"/>'
          '</w:numPr>');
      buf.write('</w:pPr>');
      buf.write(_runsToXml(item.runs, ctx));
      buf.write('</w:p>\n');
    }
    return buf.toString();
  }

  // ── Equation — verbatim OMML round-trip ───────────────────────────────────

  /// Re-emits the equation's original OMML, preserving fidelity across a
  /// save→reopen cycle. The app cannot yet *edit* equation contents (Phase 6),
  /// but it must never silently degrade an existing equation to plain text.
  ///
  /// Always wraps in `<m:oMathPara>` (block-level container) regardless of
  /// the original [EquationBlock.isInline] flag — this is what
  /// [XmlBodyParser._parseParagraph] looks for first on reopen, guaranteeing
  /// the equation round-trips through *our own* parser even though a
  /// genuinely inline equation re-imported into Word will appear as its own
  /// paragraph rather than flowing inline with adjacent text.
  String _equationToXml(EquationBlock block) {
    if (block.rawOmml.isEmpty) {
      // No OMML available (shouldn't normally happen) — fail soft with a
      // visible text placeholder rather than emitting invalid XML.
      return _paragraphToXml(
        ParagraphBlock(
          id:   block.id,
          runs: [
            TextRun(
              text:  block.latex ?? '[Equation]',
              style: const TextRunStyle(italic: true, colorArgb: 0xFF1565C0),
            ),
          ],
        ),
        _SerializationContext(),
      );
    }
    return '<w:p><m:oMathPara>${block.rawOmml}</m:oMathPara></w:p>\n';
  }

  // ── Image placeholder ─────────────────────────────────────────────────────
  //
  // Images are embedded as media files (see [serialize]) but the body still
  // needs a `<w:drawing>` to actually reference them. Full drawingML output
  // (anchor/inline + transform matrix) is a meaningful chunk of schema on
  // its own; until that lands, we surface a clearly-labelled placeholder
  // paragraph rather than silently dropping the image reference, and the
  // original bytes are still written into word/media/ so no data is lost.

  String _imagePlaceholderXml(ImageBlock block) {
    final label = block.altText != null
        ? '[Image: ${block.altText}]'
        : '[Image]';
    return _paragraphToXml(
      ParagraphBlock(
        id:   block.id,
        runs: [TextRun(text: label, style: const TextRunStyle(italic: true))],
      ),
      _SerializationContext(),
    );
  }

  // ── Standalone hyperlink block ────────────────────────────────────────────

  String _standaloneHyperlinkXml(HyperlinkBlock block, _SerializationContext ctx) {
    final rId = ctx.registerHyperlink(block.url);
    final buf = StringBuffer('<w:p><w:pPr/>\n');
    buf.write('<w:hyperlink r:id="$rId" w:history="1">\n');
    for (final run in block.runs) {
      buf.write(_runToXml(run));
    }
    buf.write('</w:hyperlink></w:p>\n');
    return buf.toString();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _addEntry(Archive archive, String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  String _jcVal(ParagraphAlignment a) => switch (a) {
        ParagraphAlignment.center  => 'center',
        ParagraphAlignment.right   => 'right',
        ParagraphAlignment.justify => 'both',
        ParagraphAlignment.left    => 'left',
      };

  String _esc(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// Single source of truth for media file naming — used both when writing
  /// the actual bytes into `word/media/` and when writing the matching
  /// `Target=` attribute in `word/_rels/document.xml.rels`. Keeping this in
  /// one place is what guarantees the two never drift apart.
  String _mediaFileName(String rId, Uint8List bytes) =>
      '$rId.${_guessExt(bytes)}';

  String _guessExt(Uint8List bytes) {
    if (bytes.length >= 8) {
      if (bytes[0] == 0x89 && bytes[1] == 0x50) return 'png'; // 89 50 4E 47
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) return 'jpg'; // FF D8 FF
      if (bytes[0] == 0x47 && bytes[1] == 0x49) return 'gif'; // 47 49 46
    }
    return 'png';
  }
}
