import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/theme_constants.dart';
import '../../data/models/document_block.dart'
    hide TableRow, TableCell;
import '../../data/models/document_model.dart';
import '../../data/models/search_result.dart';
import '../providers/search_provider.dart';
import 'equation_renderer.dart';
import 'heading_renderer.dart';
import 'paragraph_renderer.dart';
import 'table_grid_normalizer.dart';
import 'text_run_builder.dart';

import '../../data/models/document_block.dart' as docmodel
    show TableBlock, TableRow, TableCell;

// ═══════════════════════════════════════════════════════════════════════════════
// DOCUMENT RENDERER WIDGET  (Phase 4)
// ═══════════════════════════════════════════════════════════════════════════════

/// Renders a [DocumentModel] as a scrollable [ListView].
///
/// Phase 4: now a [ConsumerWidget] so it can watch [searchNotifierProvider]
/// and pass [SearchHighlight] annotations to per-block renderers.
class DocumentRendererWidget extends ConsumerWidget {
  final DocumentModel  model;
  final ScrollController? scrollController;
  final void Function(String url)? onLinkTap;
  final double baseFontSize;
  final double lineSpacing;
  final double horizontalMargin;
  final int pdfInitialPage;
  final void Function(int page)? onPdfPageChanged;

  const DocumentRendererWidget({
    super.key,
    required this.model,
    this.scrollController,
    this.onLinkTap,
    this.baseFontSize     = 16.0,
    this.lineSpacing      = 1.2,
    this.horizontalMargin = AppConstants.documentHorizontalPadding,
    this.pdfInitialPage   = 1,
    this.onPdfPageChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchState = ref.watch(searchNotifierProvider);

    return ListView.builder(
      controller: scrollController,
      physics:    const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: horizontalMargin,
        vertical:   AppConstants.documentVerticalPadding,
      ),
      itemCount: model.blocks.length,
      itemBuilder: (context, index) {
        final block      = model.blocks[index];
        final highlights = searchState.highlightsForBlock(block.id);
        return _buildBlock(block, context, highlights);
      },
    );
  }

  Widget _buildBlock(
    DocumentBlock        block,
    BuildContext         context,
    List<SearchHighlight> highlights,
  ) {
    try {
      return switch (block) {
        ParagraphBlock()  => ParagraphRenderer(
            block:        block,
            onLinkTap:    onLinkTap,
            highlights:   highlights,
            baseFontSize: baseFontSize,
            lineSpacing:  lineSpacing,
          ),
        HeadingBlock()    => HeadingRenderer(
            block:        block,
            highlights:   highlights,
            baseFontSize: baseFontSize,
            lineSpacing:  lineSpacing + 0.1, // headings keep a touch more room than body text
          ),
        PageBreakBlock()  => const _PageBreakWidget(),
        EquationBlock()   => EquationRenderer(block: block),
        ImageBlock()      => _ImageWidget(block: block, images: model.images),
        TableBlock()      => _TableWidget(
            block:     block,
            images:    model.images,
            onLinkTap: onLinkTap,
          ),
        ListBlock()       => _ListBlockWidget(
            block:     block,
            onLinkTap: onLinkTap,
          ),
        HyperlinkBlock()  => _HyperlinkWidget(
            block:     block,
            onLinkTap: onLinkTap,
          ),
        PdfDocumentBlock()  => _PdfDocumentWidget(
            block:         block,
            initialPage:   pdfInitialPage,
            onPageChanged: onPdfPageChanged,
          ),
        SpreadsheetBlock()  => _SpreadsheetWidget(block: block),
      };
    } catch (e) {
      return _ErrorBlock(blockId: block.id, error: e.toString());
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAGE BREAK
// ═══════════════════════════════════════════════════════════════════════════════

class _PageBreakWidget extends StatelessWidget {
  const _PageBreakWidget();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '─── Page Break ───',
              style: TextStyle(
                fontSize:     11,
                color:        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                letterSpacing: 1.2,
              ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// IMAGE
// ═══════════════════════════════════════════════════════════════════════════════

class _ImageWidget extends StatelessWidget {
  final ImageBlock          block;
  final Map<String, Uint8List> images;

  const _ImageWidget({required this.block, required this.images});

  @override
  Widget build(BuildContext context) {
    final bytes = block.bytes
        ?? (block.relationshipId != null ? images[block.relationshipId!] : null);

    if (bytes == null) return _placeholder(context);

    final maxW = AppConstants.documentMaxWidth -
                 AppConstants.documentHorizontalPadding * 2;
    final w = (block.widthPx ?? maxW).clamp(0.0, maxW);
    final h = block.heightPx;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: w),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: h != null
                ? Image.memory(bytes, width: w, height: h, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => _placeholder(context))
                : Image.memory(bytes, width: w, fit: BoxFit.fitWidth,
                    errorBuilder: (_, __, ___) => _placeholder(context)),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final label = block.altText;
    return Container(
      height: block.heightPx?.clamp(40.0, 120.0) ?? 80,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(ThemeConstants.radiusSm),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            label == '[Phương trình]'
                ? Icons.functions_outlined
                : Icons.image_not_supported_outlined,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ]),
      ),
    );
  }
} // end _ImageWidget

// ═══════════════════════════════════════════════════════════════════════════════
// TABLE
// ═══════════════════════════════════════════════════════════════════════════════

class _TableWidget extends StatelessWidget {
  final TableBlock             block;
  final Map<String, Uint8List> images;
  final void Function(String)? onLinkTap;

  const _TableWidget({
    required this.block,
    required this.images,
    this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    if (block.rows.isEmpty) return const SizedBox.shrink();

    // Since the document area is always forced to light theme (white paper),
    // we use fixed light-mode colors here.
    const borderColor = Color(0xFFCCCCCC);
    const headerBg    = Color(0xFFE3F2FD);
    const altBg       = Color(0xFFF9F9F9);

    final normalizedRows = TableGridNormalizer.isAlreadyUniform(block.rows)
        ? block.rows
        : TableGridNormalizer.normalize(block.rows);

    if (normalizedRows.isEmpty) return const SizedBox.shrink();

    final colCount =
        (normalizedRows.first as docmodel.TableRow).cells.length;
    if (colCount == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      // LayoutBuilder gives the Table a bounded maxWidth so FlexColumnWidth
      // can distribute space and RichText inside cells can wrap.
      // Previously SingleChildScrollView gave infinite width → text never wrapped.
      child: LayoutBuilder(
        builder: (context, constraints) => Table(
          border:        TableBorder.all(color: borderColor, width: 0.8),
          // FlexColumnWidth distributes available width equally among columns.
          // Text in cells now has a bounded width and wraps correctly.
          columnWidths: {
            for (int i = 0; i < colCount; i++) i: const FlexColumnWidth(),
          },
          children: normalizedRows.asMap().entries.map((entry) {
            final rowIdx   = entry.key;
            final docRow   = entry.value as docmodel.TableRow;
            final isHeader = rowIdx == 0;
            return TableRow(
              decoration: BoxDecoration(
                color: isHeader ? headerBg : (rowIdx.isOdd ? altBg : null),
              ),
              children: docRow.cells.map((docCell) {
                final cell = docCell as docmodel.TableCell;
                final bg   = cell.properties.backgroundArgb != null
                    ? Color(cell.properties.backgroundArgb!) : null;
                return TableCell(
                  child: Container(
                    color: bg,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    child: _CellContent(
                      cell:      cell,
                      isHeader:  isHeader,
                      onLinkTap: onLinkTap,
                    ),
                  ),
                );
              }).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _CellContent extends StatelessWidget {
  final docmodel.TableCell       cell;
  final bool                     isHeader;
  final void Function(String)?   onLinkTap;

  const _CellContent({
    required this.cell,
    required this.isHeader,
    this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    if (cell.content.isEmpty) return const SizedBox(width: 40, height: 20);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize:       MainAxisSize.min,
      children: cell.content.map((block) {
        if (block is ParagraphBlock) {
          if (block.isEmpty) return const SizedBox(height: 4);
          final spans = TextRunBuilder.buildSpans(block.runs, context,
              onLinkTap: onLinkTap);
          return RichText(
            text: TextSpan(
              style: TextStyle(
                fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
                fontSize:   14,
                color:      Theme.of(context).colorScheme.onSurface,
              ),
              children: spans,
            ),
          );
        }
        return const SizedBox.shrink();
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LIST BLOCK
// ═══════════════════════════════════════════════════════════════════════════════

class _ListBlockWidget extends StatelessWidget {
  final ListBlock              block;
  final void Function(String)? onLinkTap;

  const _ListBlockWidget({required this.block, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: block.items.asMap().entries.map((e) {
          return _ListRow(
            item:        e.value,
            index:       e.key,
            isOrdered:   block.isOrdered,
            startNumber: block.startNumber,
            level:       block.level,
            onLinkTap:   onLinkTap,
          );
        }).toList(),
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  final ParagraphBlock          item;
  final int                     index;
  final bool                    isOrdered;
  final int                     startNumber;
  final int                     level;
  final void Function(String)?  onLinkTap;

  const _ListRow({
    required this.item,
    required this.index,
    required this.isOrdered,
    required this.startNumber,
    required this.level,
    this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    final color  = Theme.of(context).colorScheme.onSurface;
    final bullet = isOrdered ? '${startNumber + index}.' : _bulletChar(level);
    final spans  = TextRunBuilder.buildSpans(item.runs, context, onLinkTap: onLinkTap);

    return Padding(
      padding: EdgeInsets.only(left: level * 16.0, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(bullet,
                style: TextStyle(fontSize: 15, height: 1.6, color: color,
                    fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: RichText(
              text: TextSpan(
                style:    TextStyle(fontSize: 15, height: 1.6, color: color),
                children: spans,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _bulletChar(int l) =>
      switch (l % 3) { 0 => '•', 1 => '◦', _ => '▪' };
}

// ═══════════════════════════════════════════════════════════════════════════════
// HYPERLINK BLOCK
// ═══════════════════════════════════════════════════════════════════════════════

class _HyperlinkWidget extends StatelessWidget {
  final HyperlinkBlock          block;
  final void Function(String)?  onLinkTap;

  const _HyperlinkWidget({required this.block, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    final spans = TextRunBuilder.buildSpans(block.runs, context, onLinkTap: onLinkTap);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child:   RichText(text: TextSpan(children: spans)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ERROR BLOCK
// ═══════════════════════════════════════════════════════════════════════════════

class _ErrorBlock extends StatelessWidget {
  final String blockId;
  final String error;

  const _ErrorBlock({required this.blockId, required this.error});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color:        Theme.of(context).colorScheme.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
          border:       Border.all(
              color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3)),
        ),
        child: Text(
          '[Render error in block $blockId: $error]',
          style: TextStyle(
            fontSize:   11,
            color:      Theme.of(context).colorScheme.error,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PDF DOCUMENT
// ═══════════════════════════════════════════════════════════════════════════════

class _PdfDocumentWidget extends StatefulWidget {
  const _PdfDocumentWidget({required this.block, this.initialPage = 1, this.onPageChanged});
  final PdfDocumentBlock block;
  final int initialPage;
  final void Function(int page)? onPageChanged;
  @override
  State<_PdfDocumentWidget> createState() => _PdfDocumentWidgetState();
}

class _PdfDocumentWidgetState extends State<_PdfDocumentWidget> {
  late final PdfController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = PdfController(
      document:        PdfDocument.openData(widget.block.bytes),
      initialPage:     widget.initialPage,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: PdfView(
        controller: _ctrl,
        scrollDirection: Axis.vertical,
        pageSnapping: false,
        onPageChanged: widget.onPageChanged,
        backgroundDecoration: const BoxDecoration(color: Color(0xFFF0F0F0)),
        builders: PdfViewBuilders<DefaultBuilderOptions>(
          options: const DefaultBuilderOptions(),
          documentLoaderBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
          pageLoaderBuilder: (_) =>
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          errorBuilder: (_, e) => Center(
            child: Text('Không thể render trang: $e',
                style: const TextStyle(color: Colors.red)),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SPREADSHEET (XLSX)
// ═══════════════════════════════════════════════════════════════════════════════

class _SpreadsheetWidget extends StatelessWidget {
  const _SpreadsheetWidget({required this.block});
  final SpreadsheetBlock block;

  @override
  Widget build(BuildContext context) {
    const headerBg  = Color(0xFF1565C0);
    const headerFg  = Colors.white;
    const altBg     = Color(0xFFF5F8FF);
    const borderClr = Color(0xFFCFD8DC);
    const cellH     = 36.0;
    // Fixed column width; user can scroll horizontally for wide sheets
    const colW      = 120.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Sheet tab ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: headerBg,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6), topRight: Radius.circular(6)),
          ),
          child: Text(block.sheetName,
              style: const TextStyle(
                  color: headerFg, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        // ── Grid ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: colW * block.colCount,
              // Plain Column instead of a nested ListView.builder.
              // The previous ListView here had shrinkWrap:true +
              // NeverScrollableScrollPhysics — it wasn't actually scrolling
              // anything (vertical scroll was always handled by the outer
              // document ListView), so it only added a second Viewport layer
              // nested inside the horizontal SingleChildScrollView. Two
              // stacked Viewport widgets like that interfered with
              // SelectionArea's ability to find/select the Text widgets
              // inside — long-press-to-select silently did nothing in the
              // spreadsheet grid. A flat Column removes that extra layer;
              // for a spreadsheet-sized row count, eager building is fine.
              child: Column(
                children: [
                  for (int rowIdx = 0; rowIdx < block.rows.length; rowIdx++)
                    Builder(builder: (context) {
                      final row      = block.rows[rowIdx];
                      final isHeader = rowIdx == 0;
                      return Container(
                        height: cellH,
                        decoration: BoxDecoration(
                          color: isHeader ? headerBg : (rowIdx.isOdd ? altBg : Colors.white),
                          border: const Border(
                              bottom: BorderSide(color: borderClr, width: 0.5)),
                        ),
                        child: Row(
                          children: List.generate(block.colCount, (colIdx) {
                            final cell = colIdx < row.length ? row[colIdx] : null;
                            return Container(
                              width: colW,
                              height: cellH,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                border: Border(
                                    right: BorderSide(
                                        color: borderClr, width: 0.5)),
                              ),
                              child: Text(
                                cell ?? '',
                                style: TextStyle(
                                  fontSize:   12,
                                  fontWeight: isHeader
                                      ? FontWeight.w600 : FontWeight.normal,
                                  color: isHeader ? headerFg : Colors.black87,
                                ),
                                overflow:   TextOverflow.ellipsis,
                                maxLines:   1,
                              ),
                            );
                          }),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
