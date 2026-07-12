import 'package:xml/xml.dart';

import '../../../core/utils/logger.dart';
import '../../models/document_block.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// INTERNAL STYLE RECORD
// ═══════════════════════════════════════════════════════════════════════════════

class _StyleRecord {
  final String styleId;
  final String? basedOn;
  final String? nameVal;
  final HeadingLevel? headingLevel;
  final TextRunStyle runStyle;
  final ParagraphProperties paragraphProps;

  const _StyleRecord({
    required this.styleId,
    this.basedOn,
    this.nameVal,
    this.headingLevel,
    this.runStyle = TextRunStyle.empty,
    this.paragraphProps = ParagraphProperties.empty,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// STYLE RESOLVER
// ═══════════════════════════════════════════════════════════════════════════════

/// Parses `word/styles.xml` and provides style lookup for the body parser.
///
/// Handles:
///  • Default run / paragraph properties from `<w:docDefaults>`
///  • Heading level detection (Heading1 … Heading6, and locale variants)
///  • Basic style inheritance via `<w:basedOn>`
///
/// Runs synchronously inside the parser isolate.
class StyleResolver {
  final Map<String, _StyleRecord> _styles = {};
  TextRunStyle _defaultRunStyle = TextRunStyle.empty;
  ParagraphProperties _defaultParaProps = ParagraphProperties.empty;

  StyleResolver(String? stylesXml) {
    if (stylesXml != null && stylesXml.isNotEmpty) {
      _parse(stylesXml);
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns [HeadingLevel] for [styleId], or null if it's a body style.
  HeadingLevel? headingLevel(String? styleId) {
    if (styleId == null) return null;
    return _resolved(styleId)?.headingLevel;
  }

  /// Returns the merged [TextRunStyle] for [styleId] (resolves inheritance).
  TextRunStyle runStyle(String? styleId) {
    if (styleId == null) return _defaultRunStyle;
    return _defaultRunStyle.merge(_resolved(styleId)?.runStyle ?? TextRunStyle.empty);
  }

  /// Returns the merged [ParagraphProperties] for [styleId].
  ParagraphProperties paragraphProperties(String? styleId) {
    if (styleId == null) return _defaultParaProps;
    return _resolved(styleId)?.paragraphProps ?? _defaultParaProps;
  }

  TextRunStyle get defaultRunStyle => _defaultRunStyle;
  ParagraphProperties get defaultParagraphProperties => _defaultParaProps;

  // ── Parsing ───────────────────────────────────────────────────────────────

  void _parse(String xml) {
    try {
      final doc = XmlDocument.parse(xml);

      // Doc defaults
      for (final el in doc.descendants.whereType<XmlElement>()) {
        if (el.localName == 'rPrDefault') {
          final rPr = _firstChildNamed(el, 'rPr');
          if (rPr != null) _defaultRunStyle = _parseRunPr(rPr);
        }
        if (el.localName == 'pPrDefault') {
          final pPr = _firstChildNamed(el, 'pPr');
          if (pPr != null) _defaultParaProps = _parseParaPr(pPr);
        }
      }

      // Named styles
      for (final el in doc.descendants.whereType<XmlElement>()) {
        if (el.localName != 'style') continue;
        _parseStyle(el);
      }

      AppLogger.debug(
        'StyleResolver: loaded ${_styles.length} styles',
        tag: 'StyleResolver',
      );
    } catch (e) {
      AppLogger.warning('Failed to parse styles.xml: $e', tag: 'StyleResolver');
    }
  }

  void _parseStyle(XmlElement styleEl) {
    final styleId = _wAttr(styleEl, 'styleId') ?? _wAttr(styleEl, 'id');
    if (styleId == null) return;

    final nameEl = _firstChildNamed(styleEl, 'name');
    final nameVal = _wAttr(nameEl, 'val') ?? '';

    final basedOnEl = _firstChildNamed(styleEl, 'basedOn');
    final basedOn = _wAttr(basedOnEl, 'val');

    final rPr = _firstChildNamed(styleEl, 'rPr');
    final pPr = _firstChildNamed(styleEl, 'pPr');

    final headingLevel = _detectHeadingLevel(styleId, nameVal);

    _styles[styleId] = _StyleRecord(
      styleId: styleId,
      basedOn: basedOn,
      nameVal: nameVal,
      headingLevel: headingLevel,
      runStyle: rPr != null ? _parseRunPr(rPr) : TextRunStyle.empty,
      paragraphProps: pPr != null ? _parseParaPr(pPr) : ParagraphProperties.empty,
    );
  }

  // ── Run property parsing ──────────────────────────────────────────────────

  TextRunStyle _parseRunPr(XmlElement rPr) {
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
          strikethrough = _isToggleOn(child);
        case 'dstrike':
          strikethrough = _isToggleOn(child);
        case 'vertAlign':
          final val = _wAttr(child, 'val');
          superscript = val == 'superscript';
          subscript = val == 'subscript';
        case 'sz':
        case 'szCs':
          final val = _wAttr(child, 'val');
          if (val != null) {
            fontSizePt = (int.tryParse(val) ?? 0) / 2.0;
          }
        case 'color':
          final val = _wAttr(child, 'val');
          colorArgb = _parseColor(val);
        case 'highlight':
          final val = _wAttr(child, 'val');
          highlightArgb = _parseHighlightColor(val);
        case 'rFonts':
          fontFamily = _wAttr(child, 'ascii') ??
              _wAttr(child, 'hAnsi') ??
              _wAttr(child, 'cs');
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

  // ── Paragraph property parsing ────────────────────────────────────────────

  ParagraphProperties _parseParaPr(XmlElement pPr) {
    ParagraphAlignment alignment = ParagraphAlignment.left;
    double spaceBeforePt = 0;
    double spaceAfterPt = 8;
    double? lineHeightMultiplier;
    double indentLeftPt = 0;
    double indentRightPt = 0;
    double firstLineIndentPt = 0;

    for (final child in pPr.childElements) {
      switch (child.localName) {
        case 'jc':
          final val = _wAttr(child, 'val');
          alignment = _parseAlignment(val);
        case 'spacing':
          final before = _wAttr(child, 'before');
          final after = _wAttr(child, 'after');
          final line = _wAttr(child, 'line');
          final lineRule = _wAttr(child, 'lineRule');
          if (before != null) spaceBeforePt = _twipToPt(before);
          if (after != null) spaceAfterPt = _twipToPt(after);
          if (line != null && lineRule != 'exact') {
            lineHeightMultiplier = (int.tryParse(line) ?? 240) / 240.0;
          }
        case 'ind':
          final left = _wAttr(child, 'left');
          final right = _wAttr(child, 'right');
          final firstLine = _wAttr(child, 'firstLine');
          final hanging = _wAttr(child, 'hanging');
          if (left != null) indentLeftPt = _twipToPt(left);
          if (right != null) indentRightPt = _twipToPt(right);
          if (firstLine != null) firstLineIndentPt = _twipToPt(firstLine);
          if (hanging != null) firstLineIndentPt = -_twipToPt(hanging);
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

  // ── Style inheritance resolution ──────────────────────────────────────────

  /// Resolves a style with full inheritance chain (up to 10 levels deep).
  _StyleRecord? _resolved(String styleId, [int depth = 0]) {
    if (depth > 10) return null; // Guard against circular refs
    final record = _styles[styleId];
    if (record == null) return null;
    if (record.basedOn == null) return record;

    final parent = _resolved(record.basedOn!, depth + 1);
    if (parent == null) return record;

    // Merge: child overrides parent
    return _StyleRecord(
      styleId: record.styleId,
      basedOn: record.basedOn,
      nameVal: record.nameVal,
      headingLevel: record.headingLevel ?? parent.headingLevel,
      runStyle: parent.runStyle.merge(record.runStyle),
      paragraphProps: record.paragraphProps,
    );
  }

  // ── Heading detection ─────────────────────────────────────────────────────

  HeadingLevel? _detectHeadingLevel(String styleId, String nameVal) {
    // Match by styleId (most reliable)
    final byId = _headingByStyleId(styleId);
    if (byId != null) return byId;

    // Match by name value (handles localized heading names)
    final lowerName = nameVal.toLowerCase().trim();
    if (lowerName == 'heading 1' || lowerName == 'title') {
      return HeadingLevel.h1;
    }
    for (int i = 1; i <= 6; i++) {
      if (lowerName == 'heading $i') return HeadingLevel.values[i - 1];
    }

    return null;
  }

  HeadingLevel? _headingByStyleId(String styleId) {
    return switch (styleId.toLowerCase()) {
      'heading1' || '1' => HeadingLevel.h1,
      'heading2' || '2' => HeadingLevel.h2,
      'heading3' || '3' => HeadingLevel.h3,
      'heading4' || '4' => HeadingLevel.h4,
      'heading5' || '5' => HeadingLevel.h5,
      'heading6' || '6' => HeadingLevel.h6,
      _ => null,
    };
  }

  // ── Attribute / value helpers ─────────────────────────────────────────────

  String? _wAttr(XmlElement? el, String localName) {
    if (el == null) return null;
    for (final attr in el.attributes) {
      if (attr.localName == localName) return attr.value;
    }
    return null;
  }

  XmlElement? _firstChildNamed(XmlElement parent, String localName) {
    for (final child in parent.childElements) {
      if (child.localName == localName) return child;
    }
    return null;
  }

  bool _isToggleOn(XmlElement el) {
    final val = _wAttr(el, 'val');
    if (val == null) return true; // Element present with no val → true
    return val != '0' && val != 'false';
  }

  ParagraphAlignment _parseAlignment(String? val) => switch (val) {
        'center' => ParagraphAlignment.center,
        'right' => ParagraphAlignment.right,
        'both' || 'distribute' => ParagraphAlignment.justify,
        _ => ParagraphAlignment.left,
      };

  /// Word spacing values are in twentieths of a point (twips).
  double _twipToPt(String twipStr) {
    final twip = int.tryParse(twipStr) ?? 0;
    return twip / 20.0;
  }

  int? _parseColor(String? hex) {
    if (hex == null || hex == 'auto') return null;
    final clean = hex.startsWith('#') ? hex.substring(1) : hex;
    if (clean.length != 6) return null;
    final rgb = int.tryParse(clean, radix: 16);
    if (rgb == null) return null;
    return 0xFF000000 | rgb;
  }

  int? _parseHighlightColor(String? name) {
    return switch (name) {
      'yellow' => 0xFFFFFF00,
      'green' => 0xFF00FF00,
      'cyan' => 0xFF00FFFF,
      'magenta' => 0xFFFF00FF,
      'blue' => 0xFF0000FF,
      'red' => 0xFFFF0000,
      'darkBlue' => 0xFF00008B,
      'darkCyan' => 0xFF008B8B,
      'darkGreen' => 0xFF006400,
      'darkMagenta' => 0xFF8B008B,
      'darkRed' => 0xFF8B0000,
      'darkYellow' => 0xFF808000,
      'darkGray' => 0xFFA9A9A9,
      'lightGray' => 0xFFD3D3D3,
      'white' => 0xFFFFFFFF,
      _ => null,
    };
  }
}
