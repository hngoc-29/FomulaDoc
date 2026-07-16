import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../data/models/document_block.dart';
import '../../data/models/search_result.dart';

/// Converts [TextRun] lists into Flutter [InlineSpan] children.
///
/// Phase 2: hyperlink runs are tappable via [TapGestureRecognizer].
/// Phase 4: character ranges in [highlights] are rendered with coloured
///          backgrounds (yellow = match, orange = current match).
class TextRunBuilder {
  TextRunBuilder._();

  // ── Main entry points ─────────────────────────────────────────────────────

  static List<InlineSpan> buildSpans(
    List<TextRun> runs,
    BuildContext context, {
    TextStyle?               defaultStyle,
    void Function(String url)? onLinkTap,
    double lineHeightMultiplier = 1.2,
  }) =>
      buildSpansWithHighlights(
        runs,
        context,
        const [],
        defaultStyle: defaultStyle,
        onLinkTap:    onLinkTap,
        lineHeightMultiplier: lineHeightMultiplier,
      );

  /// Phase 4: builds spans with optional character-level highlights.
  ///
  /// [highlights] are [SearchHighlight] objects whose offsets refer to the
  /// **concatenated flat text** of all runs (`runs.map(r=>r.text).join()`).
  static List<InlineSpan> buildSpansWithHighlights(
    List<TextRun>         runs,
    BuildContext          context,
    List<SearchHighlight> highlights, {
    TextStyle?               defaultStyle,
    void Function(String url)? onLinkTap,
    double lineHeightMultiplier = 1.2,
  }) {
    final baseColor    = Theme.of(context).colorScheme.onSurface;
    final isDark       = Theme.of(context).brightness == Brightness.dark;
    final baseFontSize = defaultStyle?.fontSize ?? 16.0;
    final spans        = <InlineSpan>[];
    int   charOffset   = 0; // running position through all runs

    for (final run in runs) {
      final runEnd = charOffset + run.text.length;

      // Highlights that overlap this run
      final overlapping = highlights
          .where((h) => h.charEnd > charOffset && h.charStart < runEnd)
          .toList();

      if (overlapping.isEmpty) {
        spans.add(_singleSpan(
          run,
          baseColor:    baseColor,
          baseFontSize: baseFontSize,
          isDark:       isDark,
          onLinkTap:    onLinkTap,
          lineHeightMultiplier: lineHeightMultiplier,
        ));
      } else {
        spans.addAll(_highlightedSpans(
          run,
          runStart:     charOffset,
          highlights:   overlapping,
          baseColor:    baseColor,
          baseFontSize: baseFontSize,
          isDark:       isDark,
          onLinkTap:    onLinkTap,
          lineHeightMultiplier: lineHeightMultiplier,
        ));
      }

      charOffset = runEnd;
    }

    return spans;
  }

  // ── Single span (no highlights) ───────────────────────────────────────────

  static InlineSpan _singleSpan(
    TextRun run, {
    required Color  baseColor,
    required double baseFontSize,
    required bool   isDark,
    void Function(String url)? onLinkTap,
    double lineHeightMultiplier = 1.2,
  }) {
    final style = _buildStyle(run.style, baseColor, baseFontSize,
        isDark: isDark, lineHeightMultiplier: lineHeightMultiplier);

    if (run.style.superscript || run.style.subscript) {
      return _scriptSpan(run, style, run.style.fontSizePt ?? baseFontSize);
    }

    if (run.isHyperlink && onLinkTap != null) {
      return TextSpan(
        text:       run.text,
        style:      style.copyWith(decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()..onTap = () => onLinkTap(run.url!),
      );
    }

    return TextSpan(text: run.text, style: style);
  }

  // ── Spans split at highlight boundaries ───────────────────────────────────

  static List<InlineSpan> _highlightedSpans(
    TextRun               run, {
    required int                  runStart,
    required List<SearchHighlight> highlights,
    required Color                baseColor,
    required double               baseFontSize,
    required bool                 isDark,
    void Function(String url)?    onLinkTap,
    double lineHeightMultiplier = 1.2,
  }) {
    final text   = run.text;
    final base   = _buildStyle(run.style, baseColor, baseFontSize,
        isDark: isDark, lineHeightMultiplier: lineHeightMultiplier);
    final result = <InlineSpan>[];

    // Convert to run-local offsets and sort
    final segs = highlights
        .map((h) => (
              start:     (h.charStart - runStart).clamp(0, text.length),
              end:       (h.charEnd   - runStart).clamp(0, text.length),
              isCurrent: h.isCurrent,
            ))
        .where((s) => s.start < s.end)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    int pos = 0;
    for (final seg in segs) {
      // Normal text before highlight
      if (pos < seg.start) {
        result.add(TextSpan(
          text:  text.substring(pos, seg.start),
          style: base,
        ));
      }
      // Highlighted text
      result.add(TextSpan(
        text:  text.substring(seg.start, seg.end),
        style: base.copyWith(
          backgroundColor: seg.isCurrent
              ? const Color(0xFFFF9800)  // orange  = current
              : const Color(0xFFFFEB3B), // yellow  = other match
          color: Colors.black87,
        ),
      ));
      pos = seg.end;
    }
    // Remaining text
    if (pos < text.length) {
      result.add(TextSpan(text: text.substring(pos), style: base));
    }

    return result;
  }

  // ── Script span (super/sub) ────────────────────────────────────────────────

  static WidgetSpan _scriptSpan(TextRun run, TextStyle base, double fontSize) {
    final s      = run.style;
    final small  = fontSize * 0.65;
    final offset = s.superscript ? -(fontSize * 0.35) : (fontSize * 0.15);
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline:  TextBaseline.alphabetic,
      child:     Transform.translate(
        offset: Offset(0, offset),
        child:  Text(run.text, style: base.copyWith(fontSize: small)),
      ),
    );
  }

  // ── TextStyle builder ─────────────────────────────────────────────────────

  static TextStyle _buildStyle(
    TextRunStyle style,
    Color        baseColor,
    double       baseFontSize, {
    bool isDark = false,
    double lineHeightMultiplier = 1.2,
  }) {
    // Adapt the document's explicit color so it stays readable.
    // DOCX files often hardcode black (0xFF000000) or white text, or a
    // medium gray for de-emphasized labels. In dark mode, black — and even
    // a mid-gray meant to read as "subtle" against white paper — becomes
    // low-contrast against 0xFF1E1E1E; in light mode near-white does the
    // same against 0xFFFAFAFA. The threshold is deliberately conservative
    // (not just "technically distinguishable") — 0.4/0.5 rather than a
    // near-black/near-white cutoff — because a color can be *readable* in
    // the sense of computeLuminance() clearing a low bar while still being
    // genuinely hard to read at body-text size. Fall back to the theme's
    // own onSurface, which is chosen to contrast well with the current
    // reading surface by construction, whenever a document color doesn't
    // clearly clear that higher bar.
    Color color = baseColor;
    if (style.colorArgb != null) {
      final docColor  = Color(style.colorArgb!);
      final luminance = docColor.computeLuminance();
      final isLegible = isDark
          ? luminance >= 0.4  // dark bg  → need bright-enough text
          : luminance <= 0.5; // light bg → need dark-enough text
      color = isLegible ? docColor : baseColor;
    }

    final hlt      = style.highlightArgb != null ? Color(style.highlightArgb!) : null;
    // fontSizePt is in typographic points. On screen at 96 dpi:
    // 1pt = 1/72 inch = 96/72 px = 1.3333px.
    // However the xml_body_parser stores values already in pt
    // (half-pt ÷ 2), so the multiplier is correct.
    // We clamp to 8–96 to handle edge cases.
    final fontSize = style.fontSizePt != null
        ? (style.fontSizePt! * 1.3333).clamp(8.0, 96.0)
        : baseFontSize;

    // Line height: Word uses "auto" spacing ≈ 1.15–1.20 of font size.
    // Configurable via the reading-preferences "Giãn dòng" slider; defaults
    // to 1.2 (the previous hardcoded value) when not overridden.
    final lineHeight = lineHeightMultiplier;

    return TextStyle(
      fontWeight:      style.bold      ? FontWeight.bold   : FontWeight.normal,
      fontStyle:       style.italic    ? FontStyle.italic  : FontStyle.normal,
      decoration:      _decoration(style),
      decorationColor: color,
      fontSize:        fontSize,
      color:           color,
      backgroundColor: hlt,
      fontFamily:      style.fontFamily,
      height:          lineHeight,
    );
  }

  static TextDecoration _decoration(TextRunStyle s) {
    if (!s.underline && !s.strikethrough) return TextDecoration.none;
    if (s.underline && s.strikethrough) {
      return TextDecoration.combine(
          [TextDecoration.underline, TextDecoration.lineThrough]);
    }
    return s.underline ? TextDecoration.underline : TextDecoration.lineThrough;
  }
}
