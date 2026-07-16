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
        PdfDocumentBlock()  => PdfDocumentView(
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
          return Text.rich(
            TextSpan(
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
            child: Text.rich(
              TextSpan(
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
      child:   Text.rich(TextSpan(children: spans)),
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

/// Public PDF renderer widget (extracted from the old private
/// `_PdfDocumentWidget`).
///
/// Renders a [PdfDocumentBlock] as a full-viewport [PdfViewPinch] that
/// owns its own scrolling and pinch-to-zoom-and-pan (built on photo_view).
///
/// Key differences from the old `_PdfDocumentWidget`:
///  - No more `SizedBox(height: 0.85 * screenHeight)` constraint. The
///    widget now expands to fill its parent's bounded constraints via
///    [LayoutBuilder] + [SizedBox]. Constraining the PDF to ~85% of the
///    screen was the root cause of "PDF loads incompletely": pdfx's
///    lazy renderer only rasterizes pages whose render rect intersects
///    the visible viewport, and a too-small viewport combined with the
///    outer ListView's nested scrolling meant many pages were never
///    asked to render. Giving it the full available height (and
///    removing the outer ListView for PDFs in ViewerScreen) lets pdfx
///    see a real viewport and lazy-render pages correctly as the user
///    scrolls.
///  - [onControllerCreated] exposes the [PdfControllerPinch] so the
///    host screen can drive programmatic zoom (AppBar zoom buttons)
///    via [PdfControllerPinch.setZoom] — previously the AppBar zoom
///    buttons manipulated the InteractiveViewer's TransformationController
///    which was a no-op for PDF because scaleEnabled was forced off.
class PdfDocumentView extends StatefulWidget {
  const PdfDocumentView({
    super.key,
    required this.block,
    this.initialPage = 1,
    this.onPageChanged,
    this.onControllerCreated,
  });

  final PdfDocumentBlock block;
  final int initialPage;
  final void Function(int page)? onPageChanged;
  final void Function(PdfControllerPinch controller)? onControllerCreated;

  @override
  State<PdfDocumentView> createState() => _PdfDocumentViewState();
}

class _PdfDocumentViewState extends State<PdfDocumentView> {
  PdfControllerPinch? _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = PdfControllerPinch(
      document:    PdfDocument.openData(widget.block.bytes),
      initialPage: widget.initialPage,
    );
    // Fire on the next frame so the host can store the controller
    // before any potential pinch gesture arrives.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _ctrl != null) {
        widget.onControllerCreated?.call(_ctrl!);
      }
    });
  }

  @override
  void didUpdateWidget(covariant PdfDocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the host passes a different PDF block (different identityHash of
    // the bytes), the old controller is now stale and must be rebuilt
    // against the new document. Without this, navigating between two PDFs
    // would reuse the first PDF's controller — undefined behavior in pdfx
    // and a real cause of "loads incompletely" on the second file.
    if (!identical(oldWidget.block.bytes, widget.block.bytes)) {
      final oldCtrl = _ctrl;
      _ctrl = PdfControllerPinch(
        document:    PdfDocument.openData(widget.block.bytes),
        initialPage: widget.initialPage,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ctrl != null) {
          widget.onControllerCreated?.call(_ctrl!);
        }
      });
      oldCtrl?.dispose();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    _ctrl = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder gives us the actual viewport the parent (the Expanded
    // Stack in ViewerScreen) has reserved for the PDF — use its full
    // height instead of guessing 0.85 * screenHeight. A too-small height
    // was why pdfx skipped rendering pages: its renderer only rasterizes
    // pages whose rect intersects the visible viewport, and an
    // artificially small viewport meant many pages were never asked to
    // render.
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.of(context).size.height;
        final w = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;

        return SizedBox(
          width:  w,
          height: h,
          // PdfViewPinch gives each page its own independent
          // pinch-to-zoom-and-pan, built on photo_view — a pinch now
          // scales whichever page you're on, not the whole multi-page
          // scroll as one flat unit. This is also why PDF is excluded
          // from the shared document-level InteractiveViewer in
          // ViewerScreen (see the isPdf comment there): the two would
          // otherwise compete for the same pinch gesture.
          child: PdfViewPinch(
            controller: _ctrl!,
            scrollDirection: Axis.vertical,
            onPageChanged: widget.onPageChanged,
            backgroundDecoration: const BoxDecoration(color: Color(0xFFF0F0F0)),
            builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
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
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SPREADSHEET (XLSX)
// ═══════════════════════════════════════════════════════════════════════════════

/// Renders one XLSX sheet as its own bounded, independently-scrollable grid
/// card instead of dumping every row inline into the outer document
/// ListView.
///
/// v1.2 redesign, round 2 — history on the two trickiest points:
///  - Selection: round 1 assumed the horizontal `SingleChildScrollView` was
///    competing with `SelectionArea` for single-finger drags (the same way
///    `InteractiveViewer` used to — see `_multiTouch` in ViewerScreen) and
///    gated horizontal panning to a deliberate 2-finger drag to protect it.
///    Selection still didn't work — the actual cause turned out to be that
///    `_SpreadsheetRow` (below) already used a real `Text` widget, which
///    *is* selection-aware, unlike the `RichText` used elsewhere in this
///    file at the time. Once every renderer switched to `Text`/`Text.rich`,
///    the 2-finger gate was solving a problem the gesture arena wasn't
///    actually causing — removed, so horizontal panning is a normal
///    single-finger swipe again. Trade-off: dragging sideways to select
///    *across* cells may lose to the scroll gesture, same as any normal
///    horizontal list.
///  - Sizing: was capped at ~50% of screen height ("boxed-in panel" per
///    feedback) — now ~75%, closer to full-screen.
///
/// Both still hold:
///  - Persistent, draggable `Scrollbar` on both axes instead of invisible
///    swipe-to-scroll.
///  - Rows are virtualized via `ListView.builder` with a fixed `itemExtent`
///    (a 500-row sheet no longer means 500 rows alive/built at once).
class _SpreadsheetWidget extends StatefulWidget {
  const _SpreadsheetWidget({required this.block});
  final SpreadsheetBlock block;

  @override
  State<_SpreadsheetWidget> createState() => _SpreadsheetWidgetState();
}

class _SpreadsheetWidgetState extends State<_SpreadsheetWidget> {
  static const double _cellH   = 36.0;
  // Fixed column width; user pans horizontally for wide sheets.
  static const double _colW    = 120.0;
  static const double _rowNumW = 40.0;

  final _hController = ScrollController();
  final _vController = ScrollController();

  @override
  void dispose() {
    _hController.dispose();
    _vController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final block     = widget.block;
    final rowCount  = block.rows.length;
    final double gridWidth = _rowNumW + _colW * block.colCount;

    // Bounded height: rows scroll *inside* the card instead of every row
    // being dumped into the outer document list — a 500-row sheet no
    // longer means dragging the whole page a mile to reach row 500. Sized
    // to feel close to full-screen (~75% of viewport height) rather than a
    // small boxed-in panel; small sheets just fit exactly, no dead space.
    final double maxBodyH = (MediaQuery.sizeOf(context).height * 0.75)
        .clamp(360.0, 720.0)
        .toDouble();
    final double naturalBodyH = rowCount * _cellH;
    final double bodyH = naturalBodyH < maxBodyH ? naturalBodyH : maxBodyH;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: ThemeConstants.cardRadius,
        border: Border.all(color: const Color(0xFFCFD8DC)),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize:       MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Sheet tab ──────────────────────────────────────────────────
          Container(
            width:   double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color:   ThemeConstants.primaryBlue,
            child: Row(
              children: [
                const Icon(Icons.table_chart_outlined,
                    size: 15, color: Colors.white),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    block.sheetName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                ),
                Text('$rowCount dòng',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 11)),
              ],
            ),
          ),
          // ── Grid ─────────────────────────────────────────────────────────
          // Horizontal pan is a normal single-finger swipe (previously
          // gated to a 2-finger drag to protect SelectionArea — that gate
          // is gone now that cells use a real Text widget under
          // SelectionArea, which is what actually makes selection work;
          // the gate was solving a problem the gesture arena wasn't
          // actually causing). Trade-off: dragging sideways to select
          // *across* cells may lose to the scroll gesture, same as any
          // normal horizontal list — selecting within one cell, and
          // vertical selection across rows, aren't affected.
          SizedBox(
            height: bodyH,
            child: Scrollbar(
              controller:      _hController,
              thumbVisibility: true,
              interactive:     true,
              child: SingleChildScrollView(
                controller:      _hController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  width: gridWidth,
                  child: Scrollbar(
                    controller:      _vController,
                    thumbVisibility: true,
                    interactive:     true,
                    child: ListView.builder(
                      controller: _vController,
                      physics:    const BouncingScrollPhysics(),
                      itemExtent: _cellH,
                      itemCount:  rowCount,
                      itemBuilder: (context, rowIdx) => RepaintBoundary(
                        child: _SpreadsheetRow(
                          cells:     block.rows[rowIdx],
                          colCount:  block.colCount,
                          colW:      _colW,
                          rowNumW:   _rowNumW,
                          cellH:     _cellH,
                          isHeader:  rowIdx == 0,
                          isOdd:     rowIdx.isOdd,
                          rowNumber: rowIdx < block.rowNumbers.length
                              ? block.rowNumbers[rowIdx]
                              : rowIdx + 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpreadsheetRow extends StatelessWidget {
  const _SpreadsheetRow({
    required this.cells,
    required this.colCount,
    required this.colW,
    required this.rowNumW,
    required this.cellH,
    required this.isHeader,
    required this.isOdd,
    required this.rowNumber,
  });

  final List<String?> cells;
  final int    colCount;
  final double colW;
  final double rowNumW;
  final double cellH;
  final bool   isHeader;
  final bool   isOdd;
  final int    rowNumber;

  static const _headerBg  = ThemeConstants.primaryBlue;
  static const _altBg     = Color(0xFFF5F8FF);
  static const _gutterBg  = Color(0xFFEEF2F6);
  static const _borderClr = Color(0xFFCFD8DC);
  static const _rowBorder = Border(
    right:  BorderSide(color: _borderClr, width: 0.5),
    bottom: BorderSide(color: _borderClr, width: 0.5),
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Row-number gutter — helps keep track of position now that the
        // sheet scrolls inside its own bounded box instead of the whole
        // page.
        Container(
          width:     rowNumW,
          height:    cellH,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:  isHeader ? _headerBg : _gutterBg,
            border: _rowBorder,
          ),
          child: Text(
            '$rowNumber',
            style: TextStyle(
              fontSize:   11,
              fontWeight: FontWeight.w600,
              color:      isHeader ? Colors.white70 : Colors.black54,
            ),
          ),
        ),
        for (int colIdx = 0; colIdx < colCount; colIdx++)
          Container(
            width:     colW,
            height:    cellH,
            padding:   const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color:  isHeader ? _headerBg : (isOdd ? _altBg : Colors.white),
              border: _rowBorder,
            ),
            child: Text(
              colIdx < cells.length ? (cells[colIdx] ?? '') : '',
              style: TextStyle(
                fontSize:   12,
                fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
                color:      isHeader ? Colors.white : Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
      ],
    );
  }
}
