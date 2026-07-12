import 'dart:typed_data';

// ═══════════════════════════════════════════════════════════════════════════════
// TEXT STYLING
// ═══════════════════════════════════════════════════════════════════════════════

/// All character-level formatting attributes for a [TextRun].
///
/// Colors are stored as raw ARGB integers (not Flutter [Color]) so the model
/// is fully isolate-safe and can be created inside a `compute()` call without
/// importing Flutter.
class TextRunStyle {
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final bool superscript;
  final bool subscript;

  /// Font size in points (pt). Null → use inherited / default.
  final double? fontSizePt;

  /// Text color as 0xAARRGGBB. Null → use theme default.
  final int? colorArgb;

  /// Highlight / background color as 0xAARRGGBB.
  final int? highlightArgb;

  /// Font family name (e.g. "Times New Roman"). Null → use default.
  final String? fontFamily;

  const TextRunStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.superscript = false,
    this.subscript = false,
    this.fontSizePt,
    this.colorArgb,
    this.highlightArgb,
    this.fontFamily,
  });

  static const TextRunStyle empty = TextRunStyle();

  TextRunStyle copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    bool? superscript,
    bool? subscript,
    double? fontSizePt,
    int? colorArgb,
    int? highlightArgb,
    String? fontFamily,
  }) {
    return TextRunStyle(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strikethrough: strikethrough ?? this.strikethrough,
      superscript: superscript ?? this.superscript,
      subscript: subscript ?? this.subscript,
      fontSizePt: fontSizePt ?? this.fontSizePt,
      colorArgb: colorArgb ?? this.colorArgb,
      highlightArgb: highlightArgb ?? this.highlightArgb,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }

  /// Returns a new style where [other] overrides non-null / non-false values.
  TextRunStyle merge(TextRunStyle other) {
    return TextRunStyle(
      bold: other.bold || bold,
      italic: other.italic || italic,
      underline: other.underline || underline,
      strikethrough: other.strikethrough || strikethrough,
      superscript: other.superscript || superscript,
      subscript: other.subscript || subscript,
      fontSizePt: other.fontSizePt ?? fontSizePt,
      colorArgb: other.colorArgb ?? colorArgb,
      highlightArgb: other.highlightArgb ?? highlightArgb,
      fontFamily: other.fontFamily ?? fontFamily,
    );
  }

  @override
  String toString() =>
      'TextRunStyle(bold:$bold, italic:$italic, size:$fontSizePt)';
}

// ═══════════════════════════════════════════════════════════════════════════════
// TEXT RUN
// ═══════════════════════════════════════════════════════════════════════════════

/// A contiguous run of text sharing identical [TextRunStyle].
///
/// Word XML maps to `<w:r>` with `<w:t>` content.
class TextRun {
  final String text;
  final TextRunStyle style;
  final String? url;

  const TextRun({required this.text, required this.style, this.url});

  bool get isHyperlink => url != null && url!.isNotEmpty;

  TextRun copyWith({String? text, TextRunStyle? style, String? url}) =>
      TextRun(
        text: text ?? this.text,
        style: style ?? this.style,
        url: url ?? this.url,
      );

  @override
  String toString() => 'TextRun("${text.length > 20 ? '${text.substring(0, 20)}…' : text}")';
}

// ═══════════════════════════════════════════════════════════════════════════════
// PARAGRAPH PROPERTIES
// ═══════════════════════════════════════════════════════════════════════════════

enum ParagraphAlignment { left, center, right, justify }

/// Block-level formatting applied to an entire paragraph.
class ParagraphProperties {
  final ParagraphAlignment alignment;

  /// Space before paragraph in pt (Word `w:before` / 20).
  final double spaceBeforePt;

  /// Space after paragraph in pt (Word `w:after` / 20).
  final double spaceAfterPt;

  /// Line-height multiplier (1.0 = single, 1.5 = one-and-a-half, etc.).
  final double? lineHeightMultiplier;

  /// Left indent in pt (Word `w:left` / 20).
  final double indentLeftPt;

  /// Right indent in pt.
  final double indentRightPt;

  /// First-line hanging/indent in pt (Word `w:firstLine` or `w:hanging` / 20).
  final double firstLineIndentPt;

  const ParagraphProperties({
    this.alignment = ParagraphAlignment.left,
    this.spaceBeforePt = 0,
    this.spaceAfterPt = 8,
    this.lineHeightMultiplier,
    this.indentLeftPt = 0,
    this.indentRightPt = 0,
    this.firstLineIndentPt = 0,
  });

  static const ParagraphProperties empty = ParagraphProperties();
}

// ═══════════════════════════════════════════════════════════════════════════════
// LIST INFO
// ═══════════════════════════════════════════════════════════════════════════════

/// Numbering info extracted from `<w:numPr>` — resolved in Phase 2.
class ListInfo {
  final int numId;
  final int ilvl;
  final bool isOrdered;

  const ListInfo({
    required this.numId,
    required this.ilvl,
    required this.isOrdered,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// TABLE STRUCTURES
// ═══════════════════════════════════════════════════════════════════════════════

class TableCellProperties {
  final int rowSpan;
  final int colSpan;
  final ParagraphAlignment verticalAlign;
  final int? backgroundArgb;
  final double? widthPt;

  const TableCellProperties({
    this.rowSpan = 1,
    this.colSpan = 1,
    this.verticalAlign = ParagraphAlignment.left,
    this.backgroundArgb,
    this.widthPt,
  });

  static const TableCellProperties empty = TableCellProperties();
}

/// One cell within a table row.
class TableCell {
  final List<DocumentBlock> content;
  final TableCellProperties properties;

  const TableCell({
    required this.content,
    this.properties = const TableCellProperties(),
  });
}

/// One row within a [TableBlock].
class TableRow {
  final List<TableCell> cells;

  const TableRow({required this.cells});
}

// ═══════════════════════════════════════════════════════════════════════════════
// HEADING LEVEL
// ═══════════════════════════════════════════════════════════════════════════════

enum HeadingLevel { h1, h2, h3, h4, h5, h6 }

// ═══════════════════════════════════════════════════════════════════════════════
// DOCUMENT BLOCK HIERARCHY  (sealed → exhaustive switch in renderer)
// ═══════════════════════════════════════════════════════════════════════════════

/// Base class for every top-level content unit in the document model.
///
/// Sealed so that `switch (block)` in renderers is exhaustively checked at
/// compile time — adding a new block type forces every renderer to handle it.
sealed class DocumentBlock {
  final String id;
  const DocumentBlock({required this.id});
}

// ── Text paragraph ────────────────────────────────────────────────────────────

/// A standard body paragraph (`<w:p>` without heading style).
final class ParagraphBlock extends DocumentBlock {
  final List<TextRun> runs;
  final ParagraphProperties properties;

  /// Non-null when this paragraph is part of a list (`<w:numPr>`).
  final ListInfo? listInfo;

  const ParagraphBlock({
    required super.id,
    required this.runs,
    this.properties = const ParagraphProperties(),
    this.listInfo,
  });

  bool get isEmpty => runs.every((r) => r.text.trim().isEmpty);

  String get plainText => runs.map((r) => r.text).join();
}

// ── Heading ───────────────────────────────────────────────────────────────────

/// A heading paragraph mapped from Word styles Heading1–Heading6.
final class HeadingBlock extends DocumentBlock {
  final List<TextRun> runs;
  final HeadingLevel level;
  final ParagraphProperties properties;

  const HeadingBlock({
    required super.id,
    required this.runs,
    required this.level,
    this.properties = const ParagraphProperties(),
  });

  String get plainText => runs.map((r) => r.text).join();
}

// ── Page break ────────────────────────────────────────────────────────────────

/// An explicit `<w:br w:type="page"/>` page break.
final class PageBreakBlock extends DocumentBlock {
  const PageBreakBlock({required super.id});
}

// ── Image ─────────────────────────────────────────────────────────────────────

/// An embedded image (`<w:drawing>` / `<w:pict>`).
final class ImageBlock extends DocumentBlock {
  /// Raw image bytes, resolved from `word/media/` by [DocxParser].
  final Uint8List? bytes;

  /// Relationship ID (`rId`) used to look up bytes from [DocumentModel.images].
  final String? relationshipId;

  /// Original dimensions in EMU. Convert with [AppConstants.emuToLogicalPx].
  final double? widthEmu;
  final double? heightEmu;

  /// Alternate text / title attribute.
  final String? altText;

  const ImageBlock({
    required super.id,
    this.bytes,
    this.relationshipId,
    this.widthEmu,
    this.heightEmu,
    this.altText,
  });

  double? get widthPx =>
      widthEmu != null ? widthEmu! * (96.0 / 914400.0) : null;
  double? get heightPx =>
      heightEmu != null ? heightEmu! * (96.0 / 914400.0) : null;
}

// ── Equation (OMML) ───────────────────────────────────────────────────────────

/// A mathematical equation derived from `<m:oMath>` or `<m:oMathPara>`.
///
/// Phase 1: [latex] is null; the renderer shows a placeholder.
/// Phase 3: [latex] contains the OMML→LaTeX string for flutter_math_fork.
final class EquationBlock extends DocumentBlock {
  /// Converted LaTeX string. Null until Phase 3 OMML parser is active.
  final String? latex;

  /// Raw OMML XML, preserved for re-parsing and debugging.
  final String rawOmml;

  /// `true` when the equation appears inline inside a paragraph.
  final bool isInline;

  const EquationBlock({
    required super.id,
    required this.rawOmml,
    this.latex,
    this.isInline = false,
  });

  bool get hasLatex => latex != null && latex!.isNotEmpty;
}

// ── Table ─────────────────────────────────────────────────────────────────────

/// A Word table (`<w:tbl>`).
final class TableBlock extends DocumentBlock {
  final List<TableRow> rows;

  /// Total table width in pt, if specified.
  final double? tableWidthPt;

  const TableBlock({
    required super.id,
    required this.rows,
    this.tableWidthPt,
  });

  int get rowCount => rows.length;
  int get columnCount => rows.isEmpty ? 0 : rows.first.cells.length;
}

// ── List ──────────────────────────────────────────────────────────────────────

/// A rendered bulleted or numbered list group.
///
/// Phase 1: list items are kept as [ParagraphBlock] with [listInfo];
/// Phase 2 groups them into this dedicated block type.
final class ListBlock extends DocumentBlock {
  final List<ParagraphBlock> items;
  final bool isOrdered;
  final int level;
  final int startNumber;

  const ListBlock({
    required super.id,
    required this.items,
    required this.isOrdered,
    this.level = 0,
    this.startNumber = 1,
  });
}

// ── Hyperlink ─────────────────────────────────────────────────────────────────

/// An external hyperlink (`<w:hyperlink r:id="...">`).
final class HyperlinkBlock extends DocumentBlock {
  final String url;
  final List<TextRun> runs;

  const HyperlinkBlock({
    required super.id,
    required this.url,
    required this.runs,
  });

  String get displayText => runs.map((r) => r.text).join();
}

// ── PDF ──────────────────────────────────────────────────────────────────────

/// Represents a whole PDF file — rendered page-by-page by the native platform
/// renderer (Android PdfRenderer / iOS PDFKit via the pdfx package).
final class PdfDocumentBlock extends DocumentBlock {
  final Uint8List bytes;
  final int       pageCount;
  const PdfDocumentBlock({
    required super.id,
    required this.bytes,
    required this.pageCount,
  });
}

// ── XLSX ─────────────────────────────────────────────────────────────────────

/// One sheet of an Excel workbook rendered as a scrollable data grid.
final class SpreadsheetBlock extends DocumentBlock {
  final String              sheetName;
  final List<List<String?>> rows;      // rows × cols, null = empty cell
  final int                 colCount;

  /// Intra-ZIP path of the sheet XML this block was parsed from
  /// (e.g. 'xl/worksheets/sheet1.xml'). Needed to safely write edited cells
  /// back to the correct sheet without touching any other sheet/file in the
  /// workbook. Null for blocks not backed by an editable source (shouldn't
  /// normally happen for XLSX, but kept nullable for safety/back-compat).
  final String? sourceFilePath;

  /// The ACTUAL 1-based XLSX row number for each entry in [rows].
  /// XLSX rows can be sparse (an entirely empty row is often omitted from
  /// the XML), so `rows[i]`'s real row number is not always `i + 1`.
  /// Writing edits back using the wrong row number would silently corrupt
  /// a different row than the one the user actually edited, so this must
  /// be tracked explicitly rather than assumed positionally.
  final List<int> rowNumbers;

  const SpreadsheetBlock({
    required super.id,
    required this.sheetName,
    required this.rows,
    required this.colCount,
    this.sourceFilePath,
    this.rowNumbers = const [],
  });
}
