import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../../../core/utils/logger.dart';
import '../../models/document_block.dart';
import '../../models/document_model.dart';
import 'docx_extractor.dart';
import 'drawing_parser.dart';
import 'numbering_parser.dart';
import '../omml/omml_parser.dart';
import 'style_resolver.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// XML BODY PARSER  — Phase 2
// ═══════════════════════════════════════════════════════════════════════════════

/// Converts `word/document.xml` → [DocumentModel].
///
/// Phase 2 additions vs Phase 1:
///   • [DrawingParser] extracts inline/floating images from `<w:drawing>`
///   • [NumberingParser] resolves ordered vs unordered list levels
///   • Consecutive list paragraphs are post-processed into [ListBlock]
///   • Hyperlinks store their URL in [TextRun.url] for tappable rendering
///   • Table mergedCell / gridSpan fully parsed
///   • Returns `List<DocumentBlock>` per body child (supports paragraphs
///     that yield both a text block AND an image block)
///
/// Error-recovery: any element that fails is logged and skipped.
class XmlBodyParser {
  final ExtractedDocx _extracted;
  final StyleResolver _styles;
  final NumberingParser _numbering;

  int _idCounter = 0;
  final List<String> _warnings = [];
  final OmmlParser _omml = const OmmlParser();

  XmlBodyParser(
    this._extracted, {
    NumberingParser? numberingParser,
  })  : _styles = StyleResolver(_extracted.stylesXml),
        _numbering = numberingParser ?? NumberingParser(_extracted.numberingXml);

  // ── Entry point ───────────────────────────────────────────────────────────

  DocumentModel parse() {
    late final XmlDocument doc;
    try {
      doc = XmlDocument.parse(_extracted.documentXml);
    } catch (e) {
      throw FormatException('Cannot parse word/document.xml: $e');
    }

    final body = _findBody(doc);
    if (body == null) {
      throw const FormatException('No <w:body> element found');
    }

    final relationships = _parseRelationships(_extracted.relationshipsXml);
    final rawBlocks = <DocumentBlock>[];

    for (final child in body.childElements) {
      try {
        final blocks = _parseBodyChild(child, relationships);
        rawBlocks.addAll(blocks);
      } catch (e, stack) {
        final msg = 'Parse error in <${child.localName}>: $e';
        _warnings.add(msg);
        AppLogger.warning(msg, tag: 'XmlBodyParser', error: e);
        AppLogger.debug('$stack', tag: 'XmlBodyParser');
      }
    }

    // Post-process: group consecutive list paragraphs → ListBlock
    final blocks = _groupListBlocks(rawBlocks);

    final images = _resolveImages(relationships, _extracted.mediaFiles);
    final metadata = _parseMetadata(_extracted.corePropsXml);

    AppLogger.info(
      'Parsed: ${blocks.length} blocks, ${images.length} images, '
      '${_warnings.length} warnings',
      tag: 'XmlBodyParser',
    );

    return DocumentModel(
      blocks: blocks,
      metadata: metadata,
      images: images,
      parseWarnings: List.unmodifiable(_warnings),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // BODY CHILDREN — returns List<DocumentBlock> (one child can yield many blocks)
  // ═════════════════════════════════════════════════════════════════════════════

  List<DocumentBlock> _parseBodyChild(
    XmlElement el,
    Map<String, String> rels,
  ) {
    return switch (el.localName) {
      'p'      => _parseParagraph(el, rels),
      'tbl'    => [_parseTable(el, rels)].whereType<DocumentBlock>().toList(),
      'sectPr' => const [],
      'bookmarkStart' => const [],
      'bookmarkEnd'   => const [],

      // <w:sdt> = structured document tag / content control.
      // Content lives in <w:sdtContent> which can contain <w:p> and <w:tbl>.
      // Silently returning [] here was causing whole sections to disappear.
      'sdt' => _parseSdt(el, rels),

      // <mc:AlternateContent> wraps fallback content for compatibility.
      // Use the <mc:Fallback> child which contains plain <w:p>/<w:tbl>.
      'AlternateContent' => _parseAlternateContent(el, rels),

      _ => const [],
    };
  }

  /// Unwrap <w:sdt> → <w:sdtContent> → recurse into children.
  List<DocumentBlock> _parseSdt(XmlElement sdt, Map<String, String> rels) {
    final sdtContent = sdt.childElements
        .where((e) => e.localName == 'sdtContent')
        .firstOrNull;
    if (sdtContent == null) return const [];

    final blocks = <DocumentBlock>[];
    for (final child in sdtContent.childElements) {
      try {
        blocks.addAll(_parseBodyChild(child, rels));
      } catch (e) {
        _warnings.add('sdt child parse error: $e');
      }
    }
    return blocks;
  }

  /// Use <mc:Fallback> content from <mc:AlternateContent>.
  List<DocumentBlock> _parseAlternateContent(
      XmlElement ac, Map<String, String> rels) {
    final fallback = ac.childElements
        .where((e) => e.localName == 'Fallback')
        .firstOrNull;
    if (fallback == null) return const [];

    final blocks = <DocumentBlock>[];
    for (final child in fallback.childElements) {
      try {
        blocks.addAll(_parseBodyChild(child, rels));
      } catch (e) {
        _warnings.add('AlternateContent fallback parse error: $e');
      }
    }
    return blocks;
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // PARAGRAPH  <w:p>
  // ═════════════════════════════════════════════════════════════════════════════

  List<DocumentBlock> _parseParagraph(XmlElement p, Map<String, String> rels) {
    final pPr = _firstNamed(p, 'pPr');
    final styleId = _wAttr(_firstNamed(pPr, 'pStyle'), 'val');
    final result = <DocumentBlock>[];

    // ── 1. Pure page break ────────────────────────────────────────────────────
    if (_hasPageBreak(p)) {
      final nonBreakRuns = _extractTextRuns(p, pPr, rels)
          .where((r) => r.text.trim().isNotEmpty)
          .toList();
      if (nonBreakRuns.isEmpty) {
        return [PageBreakBlock(id: _nextId())];
      }
    }

    // ── 2. Block-level math  <m:oMathPara> ───────────────────────────────────
    final oMathPara = _firstChildWithPrefix(p, 'm', 'oMathPara');
    if (oMathPara != null) {
      final oMath = _firstChildWithPrefix(oMathPara, 'm', 'oMath');
      if (oMath != null) {
        final rawOmml1 = oMath.toXmlString();
        return [
          EquationBlock(
            id: _nextId(),
            rawOmml: rawOmml1,
            latex: _omml.toLatex(rawOmml1),
            isInline: false,
          )
        ];
      }
    }

    // ── 3. Inline math <m:oMath> inside paragraph ─────────────────────────────
    final inlineMath = _firstChildWithPrefix(p, 'm', 'oMath');
    if (inlineMath != null) {
      // Collect text runs before and after the inline equation
      final preMathRuns  = <TextRun>[];
      final postMathRuns = <TextRun>[];
      bool seenMath = false;
      final baseStyle = _styles.runStyle(styleId);

      for (final child in p.childElements) {
        if (child.localName == 'oMath' || child.localName == 'oMathPara') {
          seenMath = true;
          continue;
        }
        if (child.localName == 'r') {
          final run = _parseRun(child, baseStyle);
          if (run != null) {
            if (seenMath) postMathRuns.add(run);
            else preMathRuns.add(run);
          }
        }
        if (child.localName == 'hyperlink') {
          final hRuns = _parseHyperlinkRuns(child, baseStyle, rels);
          if (seenMath) postMathRuns.addAll(hRuns);
          else preMathRuns.addAll(hRuns);
        }
      }

      final hasPreText  = preMathRuns.any((r) => r.text.trim().isNotEmpty);
      final hasPostText = postMathRuns.any((r) => r.text.trim().isNotEmpty);
      final properties  = _parseParaProperties(pPr, styleId);
      final rawOmml2    = inlineMath.toXmlString();
      final eqBlock     = EquationBlock(
        id:       _nextId(),
        rawOmml:  rawOmml2,
        latex:    _omml.toLatex(rawOmml2),
        isInline: hasPreText || hasPostText,
      );

      if (!hasPreText && !hasPostText) {
        return [eqBlock];
      }

      final blocks = <DocumentBlock>[];
      if (hasPreText) {
        blocks.add(ParagraphBlock(
          id: _nextId(), runs: preMathRuns, properties: properties));
      }
      blocks.add(eqBlock);
      if (hasPostText) {
        blocks.add(ParagraphBlock(
          id: _nextId(), runs: postMathRuns, properties: properties));
      }
      return blocks;
    }

    // ── 4. Extract drawings (images) from runs ────────────────────────────────
    final imageBlocks = _extractImages(p, rels);

    // ── 5. Extract text runs ──────────────────────────────────────────────────
    final runs = _extractTextRuns(p, pPr, rels);
    final hasText = runs.any((r) => r.text.isNotEmpty);

    // ── 6. Heading ────────────────────────────────────────────────────────────
    final headingLevel = _styles.headingLevel(styleId);
    final properties = _parseParaProperties(pPr, styleId);

    if (headingLevel != null && hasText) {
      result.add(HeadingBlock(
        id: _nextId(),
        runs: runs,
        level: headingLevel,
        properties: properties,
      ));
    } else if (hasText || (imageBlocks.isEmpty)) {
      // Emit paragraph (even if empty, to preserve spacing)
      final listInfo = _parseListInfo(_firstNamed(pPr, 'numPr'));
      result.add(ParagraphBlock(
        id: _nextId(),
        runs: runs,
        properties: properties,
        listInfo: listInfo,
      ));
    }

    // ── 7. Append any images after the paragraph text ─────────────────────────
    result.addAll(imageBlocks);

    return result;
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // IMAGE EXTRACTION
  // ═════════════════════════════════════════════════════════════════════════════

  List<ImageBlock> _extractImages(
      XmlElement p, Map<String, String> rels) {
    final images = <ImageBlock>[];

    for (final el in p.descendants.whereType<XmlElement>()) {
      // ── Standard inline/floating image via <w:drawing> ──────────────────────
      if (el.localName == 'drawing') {
        final info = DrawingParser.parse(el);
        if (info == null) continue;
        images.add(ImageBlock(
          id: _nextId(),
          relationshipId: info.rId,
          widthEmu: info.widthEmu,
          heightEmu: info.heightEmu,
          altText: info.altText ?? info.title,
        ));
      }

      // ── OLE object (e.g. Equation.DSMT4 / MathType legacy equations) ────────
      // These store a WMF/EMF raster preview inside <v:imagedata> and a binary
      // OLE blob in <o:OLEObject>. Flutter can't decode WMF, so we create an
      // ImageBlock anyway — the renderer's errorBuilder shows a placeholder that
      // at least signals to the user that an equation is present.
      if (el.localName == 'object') {
        final imageData = el.descendants
            .whereType<XmlElement>()
            .where((e) => e.localName == 'imagedata')
            .firstOrNull;
        if (imageData == null) continue;

        // Attribute can be r:id or just id depending on namespace resolution
        final rId = imageData.getAttribute('r:id') ??
            imageData.getAttribute('id');
        if (rId == null) continue;

        // Dimensions are stored in dxa (twips). 1 twip = 635 EMU.
        const twipToEmu = 635;
        final dxaW = int.tryParse(
                el.getAttribute('w:dxaOrig') ?? '') ??
            0;
        final dxaH = int.tryParse(
                el.getAttribute('w:dyaOrig') ?? '') ??
            0;

        images.add(ImageBlock(
          id: _nextId(),
          relationshipId: rId,
          widthEmu: dxaW > 0 ? (dxaW * twipToEmu).toDouble() : null,
          heightEmu: dxaH > 0 ? (dxaH * twipToEmu).toDouble() : null,
          altText: '[Phương trình]',
        ));
      }
    }

    return images;
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // TEXT RUNS  <w:r>
  // ═════════════════════════════════════════════════════════════════════════════

  List<TextRun> _extractTextRuns(
    XmlElement p,
    XmlElement? pPr,
    Map<String, String> rels,
  ) {
    final styleId = _wAttr(_firstNamed(pPr, 'pStyle'), 'val');
    final baseStyle = _styles.runStyle(styleId);
    final runs = <TextRun>[];

    for (final child in p.childElements) {
      switch (child.localName) {
        case 'r':
          final run = _parseRun(child, baseStyle);
          if (run != null) runs.add(run);
        case 'hyperlink':
          runs.addAll(_parseHyperlinkRuns(child, baseStyle, rels));
        case 'ins':
          // Tracked change: insertion — render inserted content
          for (final inner in child.childElements) {
            if (inner.localName == 'r') {
              final run = _parseRun(inner, baseStyle);
              if (run != null) runs.add(run);
            }
          }
        case 'del':
        case 'drawing':  // handled separately by _extractImages
        case 'bookmarkStart':
        case 'bookmarkEnd':
        case 'proofErr':
        case 'pPr':
        case 'rPr':
          break;
      }
    }

    return runs;
  }

  TextRun? _parseRun(XmlElement r, TextRunStyle baseStyle) {
    final text = _extractRunText(r);
    if (text == null) return null;

    final rPr = _firstNamed(r, 'rPr');
    final runStyle = rPr != null
        ? baseStyle.merge(_parseRunProperties(rPr))
        : baseStyle;

    return TextRun(text: text, style: runStyle);
  }

  String? _extractRunText(XmlElement r) {
    for (final child in r.childElements) {
      switch (child.localName) {
        case 't':
          return child.innerText;
        case 'delText':
          return null;
        case 'br':
          final type = _wAttr(child, 'type');
          if (type == 'page') return null;
          if (type == 'column') return null;
          return '\n';
        case 'tab':
          return '\t';
        case 'noBreakHyphen':
          return '\u2011';
        case 'softHyphen':
          return '\u00AD';
        case 'sym':
          return _resolveSymbol(_wAttr(child, 'char'));
        case 'drawing':
          return null; // handled by _extractImages
      }
    }
    return null;
  }

  /// Phase 2: hyperlink runs now carry the URL in [TextRun.url].
  List<TextRun> _parseHyperlinkRuns(
    XmlElement hyperlink,
    TextRunStyle baseStyle,
    Map<String, String> rels,
  ) {
    // Resolve URL from relationship ID
    final rId = _rAttr(hyperlink, 'id');
    final anchor = _wAttr(hyperlink, 'anchor');
    String? url = rId != null ? rels[rId] : null;
    if (url == null && anchor != null) url = '#$anchor';

    final linkStyle = baseStyle.copyWith(
      colorArgb: 0xFF1565C0,
      underline: true,
    );

    final runs = <TextRun>[];
    for (final child in hyperlink.childElements) {
      if (child.localName == 'r') {
        final text = _extractRunText(child);
        if (text == null || text.isEmpty) continue;
        final rPr = _firstNamed(child, 'rPr');
        final style = rPr != null
            ? linkStyle.merge(_parseRunProperties(rPr))
            : linkStyle;
        // ← Store URL so the renderer can make it tappable
        runs.add(TextRun(text: text, style: style, url: url));
      }
    }

    return runs;
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // RUN PROPERTIES  <w:rPr>
  // ═════════════════════════════════════════════════════════════════════════════

  TextRunStyle _parseRunProperties(XmlElement rPr) {
    bool bold = false;
    bool italic = false;
    bool underline = false;
    bool strikethrough = false;
    bool superscript = false;
    bool subscript = false;
    double? fontSizePt;
    int? colorArgb;
    int? highlightArgb;
    String? fontFamily;

    for (final child in rPr.childElements) {
      switch (child.localName) {
        case 'b':
        case 'bCs':
          bold = _isToggleOn(child);
        case 'i':
        case 'iCs':
          italic = _isToggleOn(child);
        case 'u':
          final val = _wAttr(child, 'val');
          underline = val != null && val != 'none';
        case 'strike':
        case 'dstrike':
          strikethrough = _isToggleOn(child);
        case 'vertAlign':
          final val = _wAttr(child, 'val');
          superscript = val == 'superscript';
          subscript = val == 'subscript';
        case 'sz':
        case 'szCs':
          final v = _wAttr(child, 'val');
          if (v != null) fontSizePt = (int.tryParse(v) ?? 0) / 2.0;
        case 'color':
          colorArgb = _parseColor(_wAttr(child, 'val'));
        case 'highlight':
          highlightArgb = _parseHighlight(_wAttr(child, 'val'));
        case 'rFonts':
          fontFamily = _wAttr(child, 'ascii') ??
              _wAttr(child, 'hAnsi') ??
              _wAttr(child, 'cs');
        case 'rStyle':
          final sid = _wAttr(child, 'val');
          if (sid != null) {
            final sStyle = _styles.runStyle(sid);
            bold = bold || sStyle.bold;
            italic = italic || sStyle.italic;
            underline = underline || sStyle.underline;
            fontSizePt ??= sStyle.fontSizePt;
            colorArgb ??= sStyle.colorArgb;
            fontFamily ??= sStyle.fontFamily;
          }
        case 'vanish':
        case 'webHidden':
          // Hidden text — still render in Phase 2 (toggle in Phase 4 settings)
          break;
      }
    }

    return TextRunStyle(
      bold: bold,
      italic: italic,
      underline: underline,
      strikethrough: strikethrough,
      superscript: superscript,
      subscript: subscript,
      fontSizePt: fontSizePt,
      colorArgb: colorArgb,
      highlightArgb: highlightArgb,
      fontFamily: fontFamily,
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // PARAGRAPH PROPERTIES  <w:pPr>
  // ═════════════════════════════════════════════════════════════════════════════

  ParagraphProperties _parseParaProperties(XmlElement? pPr, String? styleId) {
    final base = _styles.paragraphProperties(styleId);
    if (pPr == null) return base;

    ParagraphAlignment alignment = base.alignment;
    double spaceBeforePt = base.spaceBeforePt;
    double spaceAfterPt = base.spaceAfterPt;
    double? lineHeightMultiplier = base.lineHeightMultiplier;
    double indentLeftPt = base.indentLeftPt;
    double indentRightPt = base.indentRightPt;
    double firstLineIndentPt = base.firstLineIndentPt;

    for (final child in pPr.childElements) {
      switch (child.localName) {
        case 'jc':
          alignment = _parseAlignment(_wAttr(child, 'val'));
        case 'spacing':
          final before = _wAttr(child, 'before');
          final after  = _wAttr(child, 'after');
          final line   = _wAttr(child, 'line');
          final rule   = _wAttr(child, 'lineRule');
          if (before != null) spaceBeforePt = _twipToPt(before);
          if (after  != null) spaceAfterPt  = _twipToPt(after);
          if (line   != null && rule != 'exact') {
            lineHeightMultiplier = (int.tryParse(line) ?? 240) / 240.0;
          }
        case 'ind':
          final left  = _wAttr(child, 'left');
          final right = _wAttr(child, 'right');
          final first = _wAttr(child, 'firstLine');
          final hang  = _wAttr(child, 'hanging');
          if (left  != null) indentLeftPt       = _twipToPt(left);
          if (right != null) indentRightPt       = _twipToPt(right);
          if (first != null) firstLineIndentPt   = _twipToPt(first);
          if (hang  != null) firstLineIndentPt   = -_twipToPt(hang);
      }
    }

    return ParagraphProperties(
      alignment: alignment,
      spaceBeforePt: spaceBeforePt,
      spaceAfterPt: spaceAfterPt,
      lineHeightMultiplier: lineHeightMultiplier,
      indentLeftPt: indentLeftPt,
      indentRightPt: indentRightPt,
      firstLineIndentPt: firstLineIndentPt,
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // TABLE  <w:tbl>
  // ═════════════════════════════════════════════════════════════════════════════

  DocumentBlock? _parseTable(XmlElement tbl, Map<String, String> rels) {
    final rows = <TableRow>[];

    for (final child in tbl.childElements) {
      if (child.localName == 'tr') {
        rows.add(_parseTableRow(child, rels));
      }
    }

    if (rows.isEmpty) return null;

    // Table width from tblPr/tblW
    double? widthPt;
    final tblPr = _firstNamed(tbl, 'tblPr');
    if (tblPr != null) {
      final tblW = _firstNamed(tblPr, 'tblW');
      if (tblW != null) {
        final type = _wAttr(tblW, 'type');
        final wVal = _wAttr(tblW, 'w');
        if (wVal != null && type == 'dxa') {
          widthPt = _twipToPt(wVal);
        }
      }
    }

    return TableBlock(id: _nextId(), rows: rows, tableWidthPt: widthPt);
  }

  TableRow _parseTableRow(XmlElement tr, Map<String, String> rels) {
    final cells = <TableCell>[];
    for (final child in tr.childElements) {
      if (child.localName == 'tc') {
        cells.add(_parseTableCell(child, rels));
      }
    }
    return TableRow(cells: cells);
  }

  TableCell _parseTableCell(XmlElement tc, Map<String, String> rels) {
    final content = <DocumentBlock>[];
    final tcPr = _firstNamed(tc, 'tcPr');

    // Parse cell dimensions / spans
    int colSpan = 1;
    int rowSpan = 1;
    int? bgArgb;

    if (tcPr != null) {
      // Horizontal span
      final gridSpan = _firstNamed(tcPr, 'gridSpan');
      colSpan = int.tryParse(_wAttr(gridSpan, 'val') ?? '1') ?? 1;

      // Vertical merge
      final vMerge = _firstNamed(tcPr, 'vMerge');
      if (vMerge != null) {
        final mergeVal = _wAttr(vMerge, 'val');
        rowSpan = (mergeVal == 'restart') ? 1 : 0; // 0 = continuation
      }

      // Background colour
      final shd = _firstNamed(tcPr, 'shd');
      bgArgb = _parseColor(_wAttr(shd, 'fill'));
    }

    // Parse cell content
    for (final child in tc.childElements) {
      if (child.localName == 'tcPr') continue;
      try {
        content.addAll(_parseBodyChild(child, rels));
      } catch (e) {
        _warn('Table cell parse error: $e');
      }
    }

    return TableCell(
      content: content,
      properties: TableCellProperties(
        colSpan: colSpan,
        rowSpan: rowSpan,
        backgroundArgb: bgArgb,
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // LIST GROUPING (post-processing)
  // ═════════════════════════════════════════════════════════════════════════════

  /// Groups consecutive [ParagraphBlock]s that share the same [ListInfo.numId]
  /// into [ListBlock] instances.
  List<DocumentBlock> _groupListBlocks(List<DocumentBlock> blocks) {
    final result = <DocumentBlock>[];
    int i = 0;

    while (i < blocks.length) {
      final block = blocks[i];

      if (block is ParagraphBlock && block.listInfo != null) {
        final numId = block.listInfo!.numId;
        final items = <ParagraphBlock>[];

        // Collect all consecutive items with the same numId
        while (i < blocks.length) {
          final b = blocks[i];
          if (b is ParagraphBlock && b.listInfo?.numId == numId) {
            items.add(b);
            i++;
          } else {
            break;
          }
        }

        final topLevel = items.first.listInfo!.ilvl;
        final isOrdered = _numbering.isOrdered(numId, topLevel);
        final startAt = _numbering.startAt(numId, topLevel);

        result.add(ListBlock(
          id: _nextId(),
          items: items,
          isOrdered: isOrdered,
          level: topLevel,
          startNumber: startAt,
        ));
      } else {
        result.add(block);
        i++;
      }
    }

    return result;
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // LIST INFO
  // ═════════════════════════════════════════════════════════════════════════════

  ListInfo? _parseListInfo(XmlElement? numPr) {
    if (numPr == null) return null;
    final numId = int.tryParse(
      _wAttr(_firstNamed(numPr, 'numId'), 'val') ?? '',
    );
    final ilvl = int.tryParse(
      _wAttr(_firstNamed(numPr, 'ilvl'), 'val') ?? '0',
    ) ?? 0;
    if (numId == null || numId == 0) return null;

    final isOrdered = _numbering.isOrdered(numId, ilvl);
    return ListInfo(numId: numId, ilvl: ilvl, isOrdered: isOrdered);
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // RELATIONSHIPS
  // ═════════════════════════════════════════════════════════════════════════════

  Map<String, String> _parseRelationships(String? relsXml) {
    final map = <String, String>{};
    if (relsXml == null || relsXml.isEmpty) return map;
    try {
      final doc = XmlDocument.parse(relsXml);
      for (final el in doc.descendants.whereType<XmlElement>()) {
        if (el.localName != 'Relationship') continue;
        final id     = el.getAttribute('Id');
        final target = el.getAttribute('Target');
        if (id != null && target != null) map[id] = target;
      }
    } catch (e) {
      _warn('Failed to parse relationships: $e');
    }
    return map;
  }

  Map<String, Uint8List> _resolveImages(
    Map<String, String> rels,
    Map<String, Uint8List> mediaFiles,
  ) {
    final resolved = <String, Uint8List>{};
    for (final entry in rels.entries) {
      final rId    = entry.key;
      final target = entry.value;
      for (final candidate in [
        'word/$target',
        target,
        'word/media/${target.split('/').last}',
      ]) {
        final bytes = mediaFiles[candidate];
        if (bytes != null) {
          resolved[rId] = bytes;
          break;
        }
      }
    }
    return resolved;
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // METADATA
  // ═════════════════════════════════════════════════════════════════════════════

  DocumentMetadata _parseMetadata(String? coreXml) {
    if (coreXml == null || coreXml.isEmpty) return DocumentMetadata.empty;
    try {
      final doc = XmlDocument.parse(coreXml);
      String? text(String name) {
        for (final el in doc.descendants.whereType<XmlElement>()) {
          if (el.localName == name) return el.innerText.trim();
        }
        return null;
      }
      DateTime? dt(String? s) {
        if (s == null) return null;
        try { return DateTime.parse(s); } catch (_) { return null; }
      }
      return DocumentMetadata(
        title:       text('title'),
        author:      text('creator'),
        subject:     text('subject'),
        description: text('description'),
        created:     dt(text('created')),
        modified:    dt(text('modified')),
      );
    } catch (e) {
      _warn('Could not parse docProps/core.xml: $e');
      return DocumentMetadata.empty;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // UTILITY HELPERS
  // ═════════════════════════════════════════════════════════════════════════════

  String _nextId() => 'blk_${_idCounter++}';
  void   _warn(String msg) { _warnings.add(msg); AppLogger.warning(msg, tag: 'XmlBodyParser'); }

  XmlElement? _findBody(XmlDocument doc) {
    for (final el in doc.descendants.whereType<XmlElement>()) {
      if (el.localName == 'body') return el;
    }
    return null;
  }

  XmlElement? _firstNamed(XmlElement? parent, String localName) {
    if (parent == null) return null;
    for (final child in parent.childElements) {
      if (child.localName == localName) return child;
    }
    return null;
  }

  XmlElement? _firstChildWithPrefix(XmlElement parent, String prefix, String localName) {
    for (final child in parent.childElements) {
      if (child.localName == localName && child.name.prefix == prefix) return child;
    }
    return null;
  }

  String? _wAttr(XmlElement? el, String localName) {
    if (el == null) return null;
    for (final attr in el.attributes) {
      if (attr.localName == localName) return attr.value;
    }
    return null;
  }

  /// Finds an attribute specifically in the 'r:' namespace.
  String? _rAttr(XmlElement el, String localName) {
    for (final attr in el.attributes) {
      if (attr.localName == localName &&
          (attr.name.prefix == 'r' || attr.name.prefix == 'r16')) {
        return attr.value;
      }
    }
    return null;
  }

  bool _isToggleOn(XmlElement el) {
    final val = _wAttr(el, 'val');
    if (val == null) return true;
    return val != '0' && val.toLowerCase() != 'false';
  }

  bool _hasPageBreak(XmlElement p) {
    for (final el in p.descendants.whereType<XmlElement>()) {
      if (el.localName == 'br' && _wAttr(el, 'type') == 'page') return true;
    }
    return false;
  }

  ParagraphAlignment _parseAlignment(String? val) => switch (val) {
        'center'               => ParagraphAlignment.center,
        'right'                => ParagraphAlignment.right,
        'both' || 'distribute' => ParagraphAlignment.justify,
        _                      => ParagraphAlignment.left,
      };

  double _twipToPt(String twipStr) => (int.tryParse(twipStr) ?? 0) / 20.0;

  int? _parseColor(String? hex) {
    if (hex == null || hex == 'auto' || hex == 'none') return null;
    final clean = hex.startsWith('#') ? hex.substring(1) : hex;
    if (clean.length != 6) return null;
    final rgb = int.tryParse(clean, radix: 16);
    return rgb != null ? (0xFF000000 | rgb) : null;
  }

  int? _parseHighlight(String? name) => switch (name) {
        'yellow'    => 0xFFFFFF00,
        'green'     => 0xFF00FF00,
        'cyan'      => 0xFF00FFFF,
        'magenta'   => 0xFFFF00FF,
        'blue'      => 0xFF0000FF,
        'red'       => 0xFFFF0000,
        'darkBlue'  => 0xFF00008B,
        'darkGray'  => 0xFFA9A9A9,
        'lightGray' => 0xFFD3D3D3,
        _           => null,
      };

  String _resolveSymbol(String? charCode) {
    if (charCode == null) return '';
    final code = int.tryParse(charCode, radix: 16);
    if (code == null) return '';
    return String.fromCharCode(code);
  }
}
