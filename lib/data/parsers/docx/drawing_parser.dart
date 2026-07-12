import 'package:xml/xml.dart';

import '../../../core/utils/logger.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DRAWING INFO
// ═══════════════════════════════════════════════════════════════════════════════

/// Metadata extracted from a `<w:drawing>` element.
class DrawingInfo {
  /// Relationship ID (e.g. "rId5") — used to look up bytes in [DocumentModel.images].
  final String? rId;

  /// Width in EMU (English Metric Units). 914400 EMU = 1 inch.
  final double? widthEmu;

  /// Height in EMU.
  final double? heightEmu;

  /// Alt text / image description from `<pic:cNvPr descr="…">`.
  final String? altText;

  /// Title from `<pic:cNvPr name="…">`.
  final String? title;

  const DrawingInfo({
    this.rId,
    this.widthEmu,
    this.heightEmu,
    this.altText,
    this.title,
  });

  bool get hasRelationship => rId != null && rId!.isNotEmpty;
}

// ═══════════════════════════════════════════════════════════════════════════════
// DRAWING PARSER
// ═══════════════════════════════════════════════════════════════════════════════

/// Extracts image metadata from `<w:drawing>` elements found inside run children.
///
/// Word XML structure for inline images:
/// ```xml
/// <w:drawing>
///   <wp:inline>                          <!-- or wp:anchor for floating -->
///     <wp:extent cx="5274310" cy="3555240"/>
///     <a:graphic>
///       <a:graphicData>
///         <pic:pic>
///           <pic:nvPicPr>
///             <pic:cNvPr name="img.png" descr="alt text"/>
///           </pic:nvPicPr>
///           <pic:blipFill>
///             <a:blip r:embed="rId5"/>   <!-- ← relationship ID -->
///           </pic:blipFill>
///         </pic:pic>
///       </a:graphicData>
///     </a:graphic>
///   </wp:inline>
/// </w:drawing>
/// ```
class DrawingParser {
  DrawingParser._();

  /// Parses a `<w:drawing>` element and returns [DrawingInfo], or `null` if
  /// the element doesn't contain a recognisable image reference.
  static DrawingInfo? parse(XmlElement drawingEl) {
    try {
      return _doParse(drawingEl);
    } catch (e) {
      AppLogger.warning(
        'DrawingParser failed: $e',
        tag: 'DrawingParser',
      );
      return null;
    }
  }

  static DrawingInfo? _doParse(XmlElement drawingEl) {
    // Find wp:inline or wp:anchor
    XmlElement? container;
    for (final child in drawingEl.childElements) {
      if (child.localName == 'inline' || child.localName == 'anchor') {
        container = child;
        break;
      }
    }
    if (container == null) return null;

    // Dimensions from <wp:extent cx="…" cy="…"/>
    double? widthEmu;
    double? heightEmu;
    for (final child in container.childElements) {
      if (child.localName == 'extent') {
        widthEmu = double.tryParse(_attr(child, 'cx') ?? '');
        heightEmu = double.tryParse(_attr(child, 'cy') ?? '');
        break;
      }
    }

    // Image rId and alt text — recurse into graphic tree
    String? rId;
    String? altText;
    String? title;

    for (final el in container.descendants.whereType<XmlElement>()) {
      switch (el.localName) {
        case 'blip':
          // <a:blip r:embed="rId5"/>
          rId ??= _rAttr(el, 'embed') ?? _rAttr(el, 'link');
        case 'cNvPr':
          // <pic:cNvPr name="image1.png" descr="alt text"/>
          altText ??= _attr(el, 'descr');
          title ??= _attr(el, 'name');
        case 'docPr':
          // <wp:docPr id="1" name="Picture 1" descr="alt text"/>
          altText ??= _attr(el, 'descr');
          title ??= _attr(el, 'name');
      }
    }

    if (rId == null && widthEmu == null) return null;

    return DrawingInfo(
      rId: rId,
      widthEmu: widthEmu,
      heightEmu: heightEmu,
      altText: altText,
      title: title,
    );
  }

  // ── Attribute helpers ─────────────────────────────────────────────────────

  /// Gets attribute value by local name (any namespace prefix).
  static String? _attr(XmlElement el, String name) {
    for (final attr in el.attributes) {
      if (attr.localName == name) return attr.value;
    }
    return null;
  }

  /// Gets attribute value specifically from the 'r:' relationship namespace.
  static String? _rAttr(XmlElement el, String name) {
    for (final attr in el.attributes) {
      if (attr.localName == name &&
          (attr.name.prefix == 'r' || attr.name.prefix == 'r16')) {
        return attr.value;
      }
    }
    // Fallback: try any attr with this localName
    return _attr(el, name);
  }
}
