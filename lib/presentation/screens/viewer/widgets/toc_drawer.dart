import 'package:flutter/material.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../data/models/document_block.dart';
import '../../../../data/models/document_model.dart';

/// Sliding drawer that lists all [HeadingBlock]s in the document.
/// Tapping a heading calls [onJump] with the heading's index in the block list,
/// so the viewer can scroll directly to it.
class TocDrawer extends StatelessWidget {
  final DocumentModel model;
  final void Function(int blockIndex) onJump;

  const TocDrawer({super.key, required this.model, required this.onJump});

  @override
  Widget build(BuildContext context) {
    final headings = <_TocEntry>[];

    for (int i = 0; i < model.blocks.length; i++) {
      final b = model.blocks[i];
      if (b is HeadingBlock) {
        headings.add(_TocEntry(
          index: i,
          level: b.level.index + 1,  // HeadingLevel.h1=0 → level 1, h2=1 → level 2, …
          text:  b.runs.map((r) => r.text).join(),
        ));
      }
    }

    return Drawer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Container(
            width:   double.infinity,
            padding: EdgeInsets.fromLTRB(
                16, MediaQuery.of(context).padding.top + 16, 16, 14),
            color:   ThemeConstants.primaryBlue,
            child: const Text(
              'Mục lục',
              style: TextStyle(
                fontSize:   18,
                fontWeight: FontWeight.w700,
                color:      Colors.white,
              ),
            ),
          ),

          // ── Heading list ─────────────────────────────────────────────────
          if (headings.isEmpty)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.list_alt_outlined,
                        size: 48, color: Colors.black26),
                    SizedBox(height: 12),
                    Text('Tài liệu không có mục lục',
                        style: TextStyle(color: Colors.black45)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding:     const EdgeInsets.symmetric(vertical: 8),
                itemCount:   headings.length,
                itemBuilder: (_, i) => _TocTile(
                  entry:  headings[i],
                  onTap:  () {
                    Navigator.of(context).pop();   // close drawer
                    onJump(headings[i].index);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TocEntry {
  final int    index;
  final int    level;
  final String text;
  const _TocEntry({required this.index, required this.level, required this.text});
}

class _TocTile extends StatelessWidget {
  final _TocEntry   entry;
  final VoidCallback onTap;
  const _TocTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Indent by level: H1=0, H2=16, H3=32 …
    final indent = (entry.level - 1) * 16.0;
    final fontSize = switch (entry.level) {
      1 => 14.0,
      2 => 13.0,
      _ => 12.0,
    };
    final fontWeight = entry.level <= 2 ? FontWeight.w600 : FontWeight.normal;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16 + indent, 10, 16, 10),
        child: Row(
          children: [
            // Level indicator dot
            Container(
              width:  6, height: 6,
              margin: const EdgeInsets.only(right: 10, top: 1),
              decoration: BoxDecoration(
                color: entry.level == 1
                    ? ThemeConstants.primaryBlue
                    : ThemeConstants.primaryBlue.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Text(
                entry.text.isEmpty ? '(Tiêu đề trống)' : entry.text,
                style: TextStyle(fontSize: fontSize, fontWeight: fontWeight),
                maxLines:  3,
                overflow:  TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
