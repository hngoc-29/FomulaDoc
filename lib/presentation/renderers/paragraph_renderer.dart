import 'package:flutter/material.dart';

import '../../data/models/document_block.dart';
import '../../data/models/search_result.dart';
import 'text_run_builder.dart';

/// Renders a [ParagraphBlock] with optional search highlights.
class ParagraphRenderer extends StatelessWidget {
  final ParagraphBlock block;
  final void Function(String url)? onLinkTap;
  final List<SearchHighlight> highlights;
  final double baseFontSize;
  final double lineSpacing;

  const ParagraphRenderer({
    super.key,
    required this.block,
    this.onLinkTap,
    this.highlights   = const [],
    this.baseFontSize = 16.0,
    this.lineSpacing  = 1.2,
  });

  @override
  Widget build(BuildContext context) {
    if (block.isEmpty) return const SizedBox(height: 6);

    final spans = TextRunBuilder.buildSpansWithHighlights(
      block.runs,
      context,
      highlights,
      defaultStyle: TextStyle(fontSize: baseFontSize),
      onLinkTap: onLinkTap,
      lineHeightMultiplier: lineSpacing,
    );

    Widget content = RichText(
      text:      TextSpan(children: spans),
      textAlign: _mapAlign(block.properties.alignment),
    );

    if (block.listInfo != null) {
      content = _ListItemWrapper(info: block.listInfo!, child: content);
    }

    return Padding(
      padding: _padding(block.properties),
      child:   content,
    );
  }

  EdgeInsets _padding(ParagraphProperties p) {
    const k = 1.333;
    return EdgeInsets.only(
      top:    (p.spaceBeforePt * k).clamp(0, 48),
      bottom: (p.spaceAfterPt  * k).clamp(0, 48),
      left:   (p.indentLeftPt  * k).clamp(0, 200),
      right:  (p.indentRightPt * k).clamp(0, 200),
    );
  }

  TextAlign _mapAlign(ParagraphAlignment a) => switch (a) {
        ParagraphAlignment.left    => TextAlign.left,
        ParagraphAlignment.center  => TextAlign.center,
        ParagraphAlignment.right   => TextAlign.right,
        ParagraphAlignment.justify => TextAlign.justify,
      };
}

class _ListItemWrapper extends StatelessWidget {
  final ListInfo info;
  final Widget   child;

  const _ListItemWrapper({required this.info, required this.child});

  @override
  Widget build(BuildContext context) {
    final color  = Theme.of(context).colorScheme.onSurface;
    final bullet = info.isOrdered ? '${info.ilvl + 1}.' : _bulletChar(info.ilvl);
    final indent = (info.ilvl * 16.0) + 4.0;

    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              bullet,
              style: TextStyle(
                  fontSize: 15, height: 1.6, color: color,
                  fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(child: child),
        ],
      ),
    );
  }

  String _bulletChar(int level) =>
      switch (level % 3) { 0 => '•', 1 => '◦', _ => '▪' };
}
