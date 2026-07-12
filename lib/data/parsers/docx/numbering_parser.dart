import 'package:xml/xml.dart';

import '../../../core/utils/logger.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// VALUE OBJECTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Resolved numbering info for one (numId, ilvl) combination.
class NumberingLevelInfo {
  /// True for decimal / letter / roman numerals; false for bullets.
  final bool isOrdered;

  /// Bullet character for unordered levels (e.g. "•", "◦", "▪").
  final String bulletChar;

  /// Number format string for ordered levels (e.g. "decimal", "lowerRoman").
  final String numFmt;

  /// Starting number for ordered lists (default 1).
  final int startAt;

  const NumberingLevelInfo({
    required this.isOrdered,
    this.bulletChar = '•',
    this.numFmt = 'decimal',
    this.startAt = 1,
  });

  static const unordered = NumberingLevelInfo(isOrdered: false);
  static const ordered = NumberingLevelInfo(isOrdered: true);
}

// ═══════════════════════════════════════════════════════════════════════════════
// NUMBERING PARSER
// ═══════════════════════════════════════════════════════════════════════════════

/// Parses `word/numbering.xml` to determine whether each list level is
/// ordered (decimal, roman, letter) or unordered (bullet).
///
/// Lookup chain:
///   numId → abstractNumId → lvl[ilvl] → numFmt
///
/// Used by [XmlBodyParser] to correctly type list items as ordered/unordered
/// and to group them into [ListBlock] instances.
class NumberingParser {
  // abstractNumId → (ilvl → info)
  final Map<int, Map<int, NumberingLevelInfo>> _abstractNums = {};
  // numId → abstractNumId
  final Map<int, int> _numToAbstract = {};
  // numId → (ilvl → override info)
  final Map<int, Map<int, NumberingLevelInfo>> _overrides = {};

  NumberingParser(String? numberingXml) {
    if (numberingXml != null && numberingXml.isNotEmpty) {
      _parse(numberingXml);
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns true if the list at [numId] / [ilvl] is an ordered (numbered) list.
  bool isOrdered(int numId, int ilvl) =>
      getInfo(numId, ilvl)?.isOrdered ?? false;

  /// Returns the bullet character for an unordered level.
  String bulletChar(int numId, int ilvl) =>
      getInfo(numId, ilvl)?.bulletChar ?? _defaultBullet(ilvl);

  /// Returns the starting number for an ordered level.
  int startAt(int numId, int ilvl) =>
      getInfo(numId, ilvl)?.startAt ?? 1;

  /// Full info lookup with override chain.
  NumberingLevelInfo? getInfo(int numId, int ilvl) {
    // Check num-level override first
    final override = _overrides[numId]?[ilvl];
    if (override != null) return override;

    final abstractId = _numToAbstract[numId];
    if (abstractId == null) return null;
    return _abstractNums[abstractId]?[ilvl];
  }

  // ── Parsing ───────────────────────────────────────────────────────────────

  void _parse(String xml) {
    try {
      final doc = XmlDocument.parse(xml);

      // 1. Parse abstractNum definitions
      for (final el in doc.descendants.whereType<XmlElement>()) {
        if (el.localName == 'abstractNum') {
          _parseAbstractNum(el);
        }
      }

      // 2. Parse num → abstractNumId mappings + overrides
      for (final el in doc.descendants.whereType<XmlElement>()) {
        if (el.localName == 'num') {
          _parseNum(el);
        }
      }

      AppLogger.debug(
        'NumberingParser: ${_abstractNums.length} abstract defs, '
        '${_numToAbstract.length} num instances',
        tag: 'NumberingParser',
      );
    } catch (e) {
      AppLogger.warning(
        'Failed to parse numbering.xml: $e',
        tag: 'NumberingParser',
      );
    }
  }

  void _parseAbstractNum(XmlElement abstractNumEl) {
    final abstractNumId = int.tryParse(
      _wAttr(abstractNumEl, 'abstractNumId') ?? '',
    );
    if (abstractNumId == null) return;

    final levels = <int, NumberingLevelInfo>{};

    for (final child in abstractNumEl.childElements) {
      if (child.localName != 'lvl') continue;
      final ilvl = int.tryParse(_wAttr(child, 'ilvl') ?? '0') ?? 0;
      final info = _parseLvl(child);
      levels[ilvl] = info;
    }

    _abstractNums[abstractNumId] = levels;
  }

  NumberingLevelInfo _parseLvl(XmlElement lvlEl) {
    String numFmt = 'bullet';
    String lvlText = '•';
    int startAt = 1;

    for (final child in lvlEl.childElements) {
      switch (child.localName) {
        case 'numFmt':
          numFmt = _wAttr(child, 'val') ?? 'bullet';
        case 'lvlText':
          lvlText = _wAttr(child, 'val') ?? '•';
        case 'start':
          startAt = int.tryParse(_wAttr(child, 'val') ?? '1') ?? 1;
      }
    }

    final ordered = _isOrderedFormat(numFmt);

    return NumberingLevelInfo(
      isOrdered: ordered,
      bulletChar: ordered ? '' : _normaliseBullet(lvlText),
      numFmt: numFmt,
      startAt: startAt,
    );
  }

  void _parseNum(XmlElement numEl) {
    final numId = int.tryParse(_wAttr(numEl, 'numId') ?? '');
    if (numId == null) return;

    // abstractNumId
    final abstractEl = _firstNamed(numEl, 'abstractNumId');
    final abstractId = int.tryParse(_wAttr(abstractEl, 'val') ?? '');
    if (abstractId != null) {
      _numToAbstract[numId] = abstractId;
    }

    // Level overrides
    for (final child in numEl.childElements) {
      if (child.localName != 'lvlOverride') continue;
      final ilvl = int.tryParse(_wAttr(child, 'ilvl') ?? '0') ?? 0;
      final lvlEl = _firstNamed(child, 'lvl');
      if (lvlEl != null) {
        _overrides.putIfAbsent(numId, () => {})[ilvl] = _parseLvl(lvlEl);
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _isOrderedFormat(String fmt) => switch (fmt) {
        'decimal' ||
        'decimalZero' ||
        'upperRoman' ||
        'lowerRoman' ||
        'upperLetter' ||
        'lowerLetter' ||
        'ordinal' ||
        'cardinalText' ||
        'ordinalText' =>
          true,
        _ => false,
      };

  String _normaliseBullet(String raw) {
    if (raw.isEmpty) return '•';
    // Map common Unicode bullets
    return switch (raw) {
      '·' => '•',
      '-' => '–',
      'o' => '◦',
      _ => raw.length == 1 ? raw : '•',
    };
  }

  String _defaultBullet(int level) => switch (level % 3) {
        0 => '•',
        1 => '◦',
        _ => '▪',
      };

  XmlElement? _firstNamed(XmlElement parent, String localName) {
    for (final child in parent.childElements) {
      if (child.localName == localName) return child;
    }
    return null;
  }

  String? _wAttr(XmlElement? el, String name) {
    if (el == null) return null;
    for (final attr in el.attributes) {
      if (attr.localName == name) return attr.value;
    }
    return null;
  }
}
