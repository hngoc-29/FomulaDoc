import 'package:flutter/material.dart';

import '../../core/constants/theme_constants.dart';
import '../../data/models/document_block.dart';
import '../../data/models/search_result.dart';
import 'text_run_builder.dart';

/// Renders a [HeadingBlock] (H1–H6) with appropriate typography and spacing.
///
/// Each heading level has:
///   • A distinct font size and weight
///   • Proportional top/bottom spacing
///   • A subtle left accent line for H1 / H2
///   • Adaptive color for light / dark mode
class HeadingRenderer extends StatelessWidget {
  final HeadingBlock block;
  final List<SearchHighlight> highlights;
  final double baseFontSize;
  final double lineSpacing;

  const HeadingRenderer({
    super.key,
    required this.block,
    this.highlights   = const [],
    this.baseFontSize = 16.0,
    this.lineSpacing  = 1.3,
  });

  @override
  Widget build(BuildContext context) {
    final config = _HeadingConfig.forLevel(block.level);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final color = isDark
        ? _darkColor(block.level)
        : _lightColor(block.level);

    // Scale heading size relative to baseFontSize (default 16)
    final scale     = baseFontSize / 16.0;
    final baseStyle = TextStyle(
      fontSize:      config.fontSize * scale,
      fontWeight:    config.fontWeight,
      color:         color,
      height:        lineSpacing,
      letterSpacing: config.letterSpacing,
    );

    final spans = TextRunBuilder.buildSpansWithHighlights(
      block.runs,
      context,
      highlights,
      defaultStyle: baseStyle,
      lineHeightMultiplier: lineSpacing,
    );

    Widget heading = Text.rich(
      TextSpan(style: baseStyle, children: spans),
      textAlign: _mapAlignment(block.properties.alignment),
    );

    // Accent bar for H1 / H2
    if (block.level == HeadingLevel.h1 || block.level == HeadingLevel.h2) {
      final barColor = isDark
          ? ThemeConstants.primaryBlueLight.withValues(alpha: 0.7)
          : ThemeConstants.primaryBlue;

      heading = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: block.level == HeadingLevel.h1 ? 4 : 3,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: heading),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        top: config.topSpacing,
        bottom: config.bottomSpacing,
      ),
      child: heading,
    );
  }

  Color _lightColor(HeadingLevel level) => switch (level) {
        HeadingLevel.h1 => ThemeConstants.h1Color,
        HeadingLevel.h2 => ThemeConstants.h2Color,
        HeadingLevel.h3 => ThemeConstants.h3Color,
        _ => ThemeConstants.hNColor,
      };

  Color _darkColor(HeadingLevel level) => switch (level) {
        HeadingLevel.h1 => const Color(0xFF90CAF9),
        HeadingLevel.h2 => const Color(0xFF64B5F6),
        HeadingLevel.h3 => const Color(0xFF42A5F5),
        _ => const Color(0xFFEEEEEE),
      };

  TextAlign _mapAlignment(ParagraphAlignment a) => switch (a) {
        ParagraphAlignment.center => TextAlign.center,
        ParagraphAlignment.right => TextAlign.right,
        ParagraphAlignment.justify => TextAlign.justify,
        _ => TextAlign.left,
      };
}

// ─── Heading Config ───────────────────────────────────────────────────────────

class _HeadingConfig {
  final double fontSize;
  final FontWeight fontWeight;
  final double letterSpacing;
  final double topSpacing;
  final double bottomSpacing;

  const _HeadingConfig({
    required this.fontSize,
    required this.fontWeight,
    required this.letterSpacing,
    required this.topSpacing,
    required this.bottomSpacing,
  });

  static _HeadingConfig forLevel(HeadingLevel level) => switch (level) {
        HeadingLevel.h1 => const _HeadingConfig(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            topSpacing: 28,
            bottomSpacing: 10,
          ),
        HeadingLevel.h2 => const _HeadingConfig(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            topSpacing: 24,
            bottomSpacing: 8,
          ),
        HeadingLevel.h3 => const _HeadingConfig(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            topSpacing: 20,
            bottomSpacing: 6,
          ),
        HeadingLevel.h4 => const _HeadingConfig(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            topSpacing: 16,
            bottomSpacing: 4,
          ),
        HeadingLevel.h5 => const _HeadingConfig(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            topSpacing: 14,
            bottomSpacing: 4,
          ),
        HeadingLevel.h6 => const _HeadingConfig(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            topSpacing: 12,
            bottomSpacing: 4,
          ),
      };
}
