import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:printing/printing.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/models/document_block.dart'
    hide TableRow, TableCell;
import '../../../data/models/document_model.dart';
import '../../../domain/abstractions/document_source.dart';
import '../../providers/document_provider.dart';
import '../../providers/font_size_provider.dart';
import '../../providers/reading_prefs_provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/search_provider.dart';
import '../../providers/service_providers.dart';
import '../../../services/reading_stats_service.dart';
import '../../renderers/document_renderer_widget.dart';
import '../../theme/app_theme.dart';
import '../../widgets/document_search_bar.dart';
import '../../widgets/scroll_position_indicator.dart';
import 'widgets/toc_drawer.dart';
import '../editor/editor_screen.dart';
import '../editor/xlsx_editor_screen.dart';
import 'widgets/viewer_error_widget.dart';
import 'widgets/viewer_loading_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// VIEWER SCREEN  (Phase 4)
// ═══════════════════════════════════════════════════════════════════════════════

class ViewerScreen extends ConsumerStatefulWidget {
  final DocumentSource? source;
  final String?         filePath;

  const ViewerScreen({super.key, this.source, this.filePath});

  const ViewerScreen.fromPath(String path, {super.key})
      : source   = null,
        filePath = path;

  @override
  ConsumerState<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends ConsumerState<ViewerScreen> {
  late final ScrollController _scrollController;
  final _transformController = TransformationController();
  final _scaffoldKey         = GlobalKey<ScaffoldState>();
  final _sessionStopwatch    = Stopwatch();

  // ValueNotifier instead of a plain field + setState. onInteractionUpdate
  // (below) fires on every single frame of an active pinch — setState()
  // there was rebuilding the entire Scaffold body (AppBar, search bar, the
  // whole document tree) 60 times a second, which is exactly what made
  // pinch-zoom feel stuttery. _ViewerAppBar now reads this via
  // ValueListenableBuilder, scoping the rebuild to just the "100%" text.
  final ValueNotifier<double> _zoomNotifier =
      ValueNotifier<double>(AppConstants.defaultZoom);
  // Deliberately separate from _zoomNotifier — see the comment above
  // onInteractionUpdate for why this stays a plain bool + setState (it only
  // changes at gesture end / button press, never on a per-frame update, so
  // there's no smoothness cost to it triggering a normal rebuild).
  bool    _isZoomed        = false;
  bool    _showWarnings   = false;
  String? _currentFileId;
  Timer?  _scrollSaveTimer;
  bool    _resumeToastShown = false;
  int     _currentPdfPage = 1;       // for PDF session restore

  // ── Text-to-speech ────────────────────────────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  bool  _isSpeaking = false;
  int   _ttsBlockIndex = 0;

  // ── Zoom / gesture tracking ────────────────────────────────────────────────
  // Tracks how many fingers are currently on screen so we can switch between
  // "scroll mode" (1 finger at zoom=1) and "pan/zoom mode" (2 fingers or
  // any finger when scale > 1).
  int  _activePointers = 0;
  bool _multiTouch     = false;

  // Note: previously there was a `_panActive` getter (true when zoomed OR
  // multi-touch) used to drive InteractiveViewer.panEnabled. That caused a
  // gesture-arena conflict with SelectionArea (see panEnabled comment below),
  // so panEnabled now depends on `_multiTouch` alone.

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _sessionStopwatch.start();

    _tts.setLanguage('vi-VN');
    _tts.setCompletionHandler(_onTtsSegmentDone);
    _tts.setCancelHandler(() => setState(() => _isSpeaking = false));
    _tts.setErrorHandler((_) => setState(() => _isSpeaking = false));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _openDocumentIfNeeded();
      _restoreScrollPosition();
    });
  }

  @override
  void dispose() {
    _scrollSaveTimer?.cancel();
    _pdfPageSaveTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _transformController.dispose();
    _zoomNotifier.dispose();
    _tts.stop();
    _sessionStopwatch.stop();
    // Fire-and-forget: dispose() can't be async, and this is a best-effort
    // local stat, not something the user is blocked on.
    unawaited(ReadingStatsService().recordSession(_sessionStopwatch.elapsed));
    super.dispose();
  }

  // ── Document loading ──────────────────────────────────────────────────────

  Future<void> _openDocumentIfNeeded() async {
    final notifier = ref.read(documentNotifierProvider.notifier);
    if (widget.source != null) {
      await notifier.open(widget.source!);
    } else if (widget.filePath != null) {
      await notifier.open(FileDocumentSource(widget.filePath!));
    }

    // Bind model to search notifier
    final model = ref.read(documentNotifierProvider).model;
    ref.read(searchNotifierProvider.notifier).bindDocument(model);

    if (model != null) {
      // Best-effort, local-only reading stats — not awaited on the critical
      // open path since it's non-essential to the viewer working correctly.
      unawaited(ReadingStatsService().recordDocumentOpened());
    }
  }

  // ── Phase 4: scroll position save (debounced 800 ms) ─────────────────────

  void _onScroll() {
    _scrollSaveTimer?.cancel();
    _scrollSaveTimer = Timer(const Duration(milliseconds: 800), _saveScrollPos);
  }

  // ── PDF page tracking (session resume) ───────────────────────────────────
  //
  // PDF documents render as a single PdfDocumentBlock inside the outer
  // ListView, so the ListView's own maxScrollExtent stays ~0 and the normal
  // scroll-fraction save/restore (used for DOCX/XLSX) never fires. We track
  // the PDF's own internal page number instead and persist that separately.

  Timer? _pdfPageSaveTimer;

  void _onPdfPageChanged(int page) {
    _currentPdfPage = page;
    _pdfPageSaveTimer?.cancel();
    _pdfPageSaveTimer = Timer(const Duration(milliseconds: 600), () {
      final filePath = widget.filePath ?? widget.source?.path
          ?? ref.read(documentNotifierProvider).currentFilePath;
      if (filePath == null) return;
      final record = ref.read(historyNotifierProvider).recentFiles
          .where((r) => r.path == filePath).firstOrNull;
      if (record != null) {
        ref.read(historyServiceProvider).savePdfPage(record.id, page);
      }
    });
  }

  void _saveScrollPos() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    final fraction = (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0);

    final filePath = widget.filePath
        ?? widget.source?.path
        ?? ref.read(documentNotifierProvider).currentFilePath;
    if (filePath == null) return;

    // Find file record id for this path
    final record = ref
        .read(historyNotifierProvider)
        .recentFiles
        .where((r) => r.path == filePath)
        .firstOrNull;
    if (record != null) {
      ref
          .read(historyNotifierProvider.notifier)
          .saveScrollPosition(record.id, fraction);
    }
  }

  // ── Phase 4: scroll position restore ─────────────────────────────────────

  void _restoreScrollPosition() {
    final filePath = widget.filePath
        ?? widget.source?.path
        ?? ref.read(documentNotifierProvider).currentFilePath;
    if (filePath == null) return;

    final record = ref
        .read(historyNotifierProvider)
        .recentFiles
        .where((r) => r.path == filePath)
        .firstOrNull;
    if (record == null) return;

    // PDF: restore last page (PdfController reads this via pdfInitialPage).
    if (record.lastPdfPage > 1) {
      setState(() => _currentPdfPage = record.lastPdfPage);
      _showResumeToastText('Tiếp tục từ trang ${record.lastPdfPage}');
      return;
    }

    if (record.lastScrollPosition < 0.02) return;

    // ListView with images may not have its full extent on the first frame.
    // We retry up to 10 times (every 100 ms) until maxScrollExtent > 0.
    _scrollRestoreWithRetry(record.lastScrollPosition, retries: 10);
  }

  void _scrollRestoreWithRetry(double fraction, {required int retries}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (max <= 0 && retries > 0) {
        // Not rendered yet — try again after a short delay
        Future.delayed(const Duration(milliseconds: 100), () {
          _scrollRestoreWithRetry(fraction, retries: retries - 1);
        });
        return;
      }
      final target = (fraction * max).clamp(0.0, max);
      if (target > 10) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 400),
          curve:    Curves.easeOut,
        );
        _showResumeToast(fraction);
      }
    });
  }

  // ── Zoom ─────────────────────────────────────────────────────────────────

  void _applyZoom(double zoom) {
    final clamped = zoom.clamp(AppConstants.minZoom, AppConstants.maxZoom);
    _zoomNotifier.value = clamped;
    setState(() => _isZoomed = clamped > 1.005);
    _transformController.value = Matrix4.diagonal3Values(clamped, clamped, 1);
  }

  // ── Table of contents ─────────────────────────────────────────────────────

  void _openToc() => _scaffoldKey.currentState?.openDrawer();

  void _jumpToBlock(int blockIndex) {
    if (!_scrollController.hasClients) return;
    // Estimate scroll position: assumes ~60px per block on average
    final target = (blockIndex * 60.0)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 400),
      curve:    Curves.easeInOut,
    );
  }

  // ── Share file ────────────────────────────────────────────────────────────

  Future<void> _shareFile() async {
    final state = ref.read(documentNotifierProvider);
    final path  = state.currentFilePath;
    if (path == null) return;
    try {
      await Share.shareXFiles([XFile(path)],
          subject: state.currentFileName ?? 'Tài liệu');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể chia sẻ file này')),
        );
      }
    }
  }

  // ── Favorite ──────────────────────────────────────────────────────────────

  Future<void> _toggleFavorite() async {
    final state = ref.read(documentNotifierProvider);
    final path  = state.currentFilePath;
    if (path == null) return;
    final histSvc = ref.read(historyServiceProvider);
    final record  = ref.read(historyNotifierProvider)
        .recentFiles
        .where((r) => r.path == path)
        .firstOrNull;
    if (record == null) return;
    await histSvc.toggleFavorite(record.id);
    await ref.read(historyNotifierProvider.notifier).load();
    if (mounted) {
      final isFav = ref.read(historyNotifierProvider)
          .favorites
          .any((r) => r.id == record.id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isFav ? 'Đã thêm vào yêu thích' : 'Đã xóa khỏi yêu thích'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  // ── Document stats ────────────────────────────────────────────────────────

  void _showStats() {
    final state = ref.read(documentNotifierProvider);
    final model = state.model;
    if (model == null) return;

    final meta = model.metadata;
    final rows = <_StatRow>[
      if (meta.title   != null) _StatRow('Tiêu đề',   meta.title!),
      if (meta.author  != null) _StatRow('Tác giả',   meta.author!),
      if (meta.subject != null) _StatRow('Chủ đề',    meta.subject!),
      if (meta.created != null) _StatRow('Tạo lúc',
          '${meta.created!.day}/${meta.created!.month}/${meta.created!.year}'),
      _StatRow('Số block',        '${model.blocks.length}'),
      if (model.equationCount > 0)
        _StatRow('Công thức',     '${model.equationCount}'),
      if (model.images.isNotEmpty)
        _StatRow('Hình ảnh',      '${model.images.length}'),
      if (model.hasWarnings)
        _StatRow('Cảnh báo',      '${model.parseWarnings.length}'),
    ];

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Thông tin tài liệu',
                style: Theme.of(context)
                    .textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...rows.map((r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(r.label,
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 13,
                        )),
                  ),
                  Expanded(
                    child: Text(r.value,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  // ── Print (PDF only) ─────────────────────────────────────────────────────
  //
  // Scoped to PDF documents only: we already hold the exact original PDF
  // bytes (PdfDocumentBlock.bytes), so printing is a direct pass-through to
  // the system print dialog. DOCX/XLSX printing would require accurately
  // re-laying-out our custom Flutter rendering into paginated PDF output —
  // a substantially bigger, separate task — so it isn't offered here to
  // avoid promising print output that doesn't match what's on screen.

  Future<void> _printDocument() async {
    final model = ref.read(documentNotifierProvider).model;
    final pdfBlock = model?.blocks.whereType<PdfDocumentBlock>().firstOrNull;
    if (pdfBlock == null) return;
    await Printing.layoutPdf(onLayout: (_) async => pdfBlock.bytes);
  }

  // ── Editor ────────────────────────────────────────────────────────────────

  void _openEditor() {
    final ds    = ref.read(documentNotifierProvider);
    final model = ds.model;
    final path  = ds.currentFilePath;
    final name  = ds.currentFileName ?? 'document.docx';
    if (model == null || path == null) return;

    final isXlsx = name.toLowerCase().endsWith('.xlsx');

    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => isXlsx
          ? XlsxEditorScreen(model: model, filePath: path, fileName: name)
          : EditorScreen(model: model, filePath: path, fileName: name),
    )).then((_) {
      // Reload the document after returning from the editor in case it was
      // saved, so the viewer reflects the latest content.
      ref.read(documentNotifierProvider.notifier).open(FileDocumentSource(path));
    });
  }

  // ── Text-to-speech ────────────────────────────────────────────────────────

  Future<void> _toggleTts() async {
    if (_isSpeaking) {
      await _tts.stop();
      setState(() => _isSpeaking = false);
      return;
    }
    final model = ref.read(documentNotifierProvider).model;
    if (model == null) return;

    // Find the first readable block at or after the current scroll position,
    // so "read aloud" resumes from roughly where the user is looking rather
    // than always restarting from the top of the document.
    _ttsBlockIndex = _estimateVisibleBlockIndex(model);
    setState(() => _isSpeaking = true);
    await _speakBlockAt(model, _ttsBlockIndex);
  }

  int _estimateVisibleBlockIndex(DocumentModel model) {
    if (!_scrollController.hasClients || model.blocks.isEmpty) return 0;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return 0;
    final fraction = (_scrollController.offset / max).clamp(0.0, 1.0);
    return (fraction * (model.blocks.length - 1)).round();
  }

  Future<void> _speakBlockAt(DocumentModel model, int index) async {
    if (index >= model.blocks.length) {
      setState(() => _isSpeaking = false);
      return;
    }
    final block = model.blocks[index];
    final text = switch (block) {
      ParagraphBlock() => block.plainText,
      HeadingBlock()   => block.plainText,
      _                => '',
    };
    _ttsBlockIndex = index;
    if (text.trim().isEmpty) {
      // Skip empty/non-text blocks (images, tables, equations) immediately.
      await _speakBlockAt(model, index + 1);
      return;
    }
    await _tts.speak(text);
  }

  void _onTtsSegmentDone() {
    if (!_isSpeaking || !mounted) return;
    final model = ref.read(documentNotifierProvider).model;
    if (model == null) {
      setState(() => _isSpeaking = false);
      return;
    }
    _speakBlockAt(model, _ttsBlockIndex + 1);
  }

  // ── Bookmarks ─────────────────────────────────────────────────────────────

  Future<void> _toggleCurrentBookmark() async {
    final model = ref.read(documentNotifierProvider).model;
    final filePath = widget.filePath ?? widget.source?.path
        ?? ref.read(documentNotifierProvider).currentFilePath;
    if (model == null || filePath == null) return;

    final record = ref.read(historyNotifierProvider).recentFiles
        .where((r) => r.path == filePath).firstOrNull;
    if (record == null) return;

    final blockIndex = _estimateVisibleBlockIndex(model);
    final marks = await ref.read(historyServiceProvider)
        .toggleBookmark(record.id, blockIndex);
    await ref.read(historyNotifierProvider.notifier).load();

    if (!mounted) return;
    final added = marks.contains(blockIndex);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:  Text(added ? 'Đã đánh dấu trang này' : 'Đã bỏ đánh dấu'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Reading theme picker ──────────────────────────────────────────────────

  void _showReadingThemePicker() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => Consumer(builder: (sheetContext, sheetRef, _) {
        final current = sheetRef.watch(readingThemeProvider);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Giao diện đọc',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 8),
                for (final mode in ReadingThemeMode.values)
                  RadioListTile<ReadingThemeMode>(
                    value: mode,
                    groupValue: current,
                    title: Row(children: [
                      Container(
                        width: 20, height: 20,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.paperColorFor(mode),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                      ),
                      Text(_readingThemeName(mode)),
                    ]),
                    onChanged: (v) {
                      sheetRef.read(readingThemeProvider.notifier).setMode(v!);
                      Navigator.pop(sheetContext);
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      }),
    );
  }

  String _readingThemeName(ReadingThemeMode mode) => switch (mode) {
        ReadingThemeMode.light        => 'Sáng',
        ReadingThemeMode.sepia        => 'Sepia (giấy vàng)',
        ReadingThemeMode.dark         => 'Tối',
        ReadingThemeMode.highContrast => 'Tương phản cao',
      };

  // ── Collections ───────────────────────────────────────────────────────────

  Future<void> _showCollectionsPicker() async {
    final filePath = widget.filePath ?? widget.source?.path
        ?? ref.read(documentNotifierProvider).currentFilePath;
    if (filePath == null) return;
    final record = ref.read(historyNotifierProvider).recentFiles
        .where((r) => r.path == filePath).firstOrNull;
    if (record == null) return;

    final histSvc  = ref.read(historyServiceProvider);
    final existing = await histSvc.getAllCollections();
    final current  = Set<String>.from(record.collections);
    final controller = TextEditingController();

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bộ sưu tập',
                  style: Theme.of(sheetContext).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (existing.isEmpty)
                const Text('Chưa có bộ sưu tập nào.',
                    style: TextStyle(color: Colors.black45)),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: existing.map((name) {
                  final selected = current.contains(name);
                  return FilterChip(
                    label:    Text(name),
                    selected: selected,
                    onSelected: (v) async {
                      if (v) {
                        await histSvc.addToCollection(record.id, name);
                        current.add(name);
                      } else {
                        await histSvc.removeFromCollection(record.id, name);
                        current.remove(name);
                      }
                      setSheetState(() {});
                      await ref.read(historyNotifierProvider.notifier).load();
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: 'Tên bộ sưu tập mới…',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    final name = controller.text.trim();
                    if (name.isEmpty) return;
                    await histSvc.addToCollection(record.id, name);
                    await ref.read(historyNotifierProvider.notifier).load();
                    controller.clear();
                    setSheetState(() {});
                  },
                  child: const Text('Thêm'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // ── Resume toast ──────────────────────────────────────────────────────────

  void _showResumeToast(double fraction) {
    final pct = (fraction * 100).round();
    _showResumeToastText(
      'Tiếp tục từ $pct%',
      action: SnackBarAction(
        label:     'Đầu trang',
        onPressed: () => _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 400),
          curve:    Curves.easeOut,
        ),
      ),
    );
  }

  void _showResumeToastText(String text, {SnackBarAction? action}) {
    if (_resumeToastShown) return;
    _resumeToastShown = true;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      action:  action,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }



  Future<void> _handleLinkTap(String url) async {
    final svc = ref.read(hyperlinkServiceProvider);
    final ok  = await svc.open(url);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể mở: $url'),
          action:  SnackBarAction(
            label:     'Sao chép',
            onPressed: () => svc.copyToClipboard(url),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Search navigation → auto-scroll to match ──────────────────────────────

  void _onSearchNavigate(int resultIndex) {
    final results = ref.read(searchNotifierProvider).results;
    if (resultIndex < 0 || resultIndex >= results.length) return;

    final result     = results[resultIndex];
    final blockIndex = ref
        .read(documentNotifierProvider)
        .model
        ?.blocks
        .indexWhere((b) => b.id == result.blockId) ?? -1;

    if (blockIndex == -1 || !_scrollController.hasClients) return;

    // Estimate offset: 64px per block on average
    final estimated = (blockIndex * 64.0).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      estimated,
      duration: const Duration(milliseconds: 300),
      curve:    Curves.easeOut,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documentNotifierProvider);

    // Bind newly loaded document to search notifier
    ref.listen(documentNotifierProvider, (prev, next) {
      if (next.isLoaded && next.model != prev?.model) {
        ref.read(searchNotifierProvider.notifier).bindDocument(next.model);
      }
    });

    final fontSize      = ref.watch(fontSizeProvider);
    final lineSpacing   = ref.watch(lineSpacingProvider);
    final readingMargin = ref.watch(readingMarginProvider);
    final readingTheme  = ref.watch(readingThemeProvider);
    final paperColor    = AppTheme.paperColorFor(readingTheme);

    return Scaffold(
      key:             _scaffoldKey,
      backgroundColor: paperColor,
      drawer: state.isLoaded && state.model != null
          ? TocDrawer(
              model:  state.model!,
              onJump: _jumpToBlock,
            )
          : null,
      body: Column(
        children: [
          // ── AppBar ────────────────────────────────────────────────────────
          _ViewerAppBar(
            state:        state,
            currentZoom:  _zoomNotifier,
            readingTheme: readingTheme,
            isSpeaking:   _isSpeaking,
            onBack:      () {
              _saveScrollPos();
              _tts.stop();
              ref.read(documentNotifierProvider.notifier).reset();
              ref.read(searchNotifierProvider.notifier).close();
              Navigator.of(context).pop();
            },
            onZoomIn:    () => _applyZoom(_zoomNotifier.value + 0.25),
            onZoomOut:   () => _applyZoom(_zoomNotifier.value - 0.25),
            onZoomReset: () => _applyZoom(1.0),
            onSearch:    () {
              ref.read(searchNotifierProvider.notifier).open();
            },
            onWarnings:     () => setState(() => _showWarnings = !_showWarnings),
            onToc:          _openToc,
            onShare:        _shareFile,
            onFavorite:     _toggleFavorite,
            onStats:        _showStats,
            onReadingTheme: _showReadingThemePicker,
            onBookmark:     _toggleCurrentBookmark,
            onTts:          _toggleTts,
            onCollections:  _showCollectionsPicker,
            onEdit:         _openEditor,
            onPrint:        _printDocument,
          ),

          // ── Phase 4: animated search bar ──────────────────────────────────
          DocumentSearchBar(onNavigate: _onSearchNavigate),

          // ── Main content area ─────────────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                if (state.isLoaded && state.model != null)
                  _buildDocumentView(
                    context, state, fontSize, lineSpacing, readingMargin, readingTheme, paperColor),
                if (state.isInitial)
                  const Center(child: CircularProgressIndicator()),
                if (state.isLoading)
                  ViewerLoadingWidget(
                    fileName: state.currentFileName,
                    progress: state.loadingProgress,
                  ),
                if (state.hasError)
                  ViewerErrorWidget(
                    message:       state.errorMessage ?? 'An unknown error occurred.',
                    onRetry:       _openDocumentIfNeeded,
                    onPickAnother: () => Navigator.of(context).pop(),
                  ),
                if (_showWarnings && state.model != null)
                  _WarningsPanel(
                    warnings:  state.model!.parseWarnings,
                    onDismiss: () => setState(() => _showWarnings = false),
                  ),

                // ── Phase 4: scroll position indicator ────────────────────
                if (state.isLoaded)
                  Positioned(
                    right:  12,
                    bottom: 24,
                    child:  ScrollPositionIndicator(controller: _scrollController),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentView(
    BuildContext context,
    DocumentState state,
    double fontSize,
    double lineSpacing,
    double horizontalMargin,
    ReadingThemeMode readingTheme,
    Color paperColor,
  ) {
    // PDF pages render as flat images with no text layer (see
    // _PdfDocumentWidget) — nothing here is selectable, and PdfViewPinch
    // (used inside DocumentRendererWidget for pdf blocks) handles its own
    // proper per-page pinch-zoom-and-pan via photo_view. The shared
    // InteractiveViewer/AbsorbPointer below is for DOCX/XLSX zoom+select;
    // for PDFs it's made inert (never pans/scales/absorbs) further down so
    // it just gets out of the way instead of fighting PdfViewPinch for the
    // same touches — that fight is what caused pinching a PDF to scale the
    // whole multi-page canvas as one flat unit instead of one page.
    final isPdf = (state.currentFileName ?? '').toLowerCase().endsWith('.pdf');

    // ── Listener tracks active pointer count ────────────────────────────────
    // We use raw pointer events (not GestureDetector) so we can reliably
    // count fingers without fighting the gesture arena.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        _activePointers++;
        // As soon as a second finger touches, enable pan in InteractiveViewer
        // so the pinch-zoom gesture can include a pan component (Flutter
        // requires panEnabled:true for reliable multi-touch scale).
        if (_activePointers >= 2 && !_multiTouch) {
          setState(() => _multiTouch = true);
        }
      },
      onPointerUp: (_) {
        if (_activePointers > 0) _activePointers--;
        if (_activePointers < 2 && _multiTouch) {
          setState(() => _multiTouch = false);
        }
      },
      onPointerCancel: (_) {
        if (_activePointers > 0) _activePointers--;
        if (_activePointers < 2 && _multiTouch) {
          setState(() => _multiTouch = false);
        }
      },
      child: LayoutBuilder(builder: (context, constraints) {
        final viewW = constraints.maxWidth;
        final viewH = constraints.maxHeight;

        return Stack(children: [
          // ── White gap fill ─────────────────────────────────────────────
          // When scale < 1 the shrunken content leaves gaps. A plain white
          // Container behind the InteractiveViewer fills them so the user
          // never sees the dark Scaffold background.
          Container(color: paperColor),

          // Double-tap-to-reset-zoom. GestureDetector only instantiates a
          // DoubleTapGestureRecognizer when onDoubleTap is non-null, so at
          // normal 1× zoom (callback = null) this adds zero competition
          // against SelectionArea's own double-tap-to-select-word — the
          // recognizer simply doesn't exist until the user has zoomed in.
          //
          // Gated on _isZoomed, NOT the live zoom value. That value updates
          // every onInteractionUpdate frame *during* an active pinch: if
          // onDoubleTap flipped null→non-null mid-gesture, GestureDetector
          // has to instantiate a brand new DoubleTapGestureRecognizer and
          // insert it into an arena that's already mid-resolution for the
          // pinch — which was derailing the in-progress scale gesture
          // entirely (pinching in would stop increasing the zoom % partway
          // through). _isZoomed only changes in onInteractionEnd/_applyZoom,
          // never while a gesture is actively updating, so this recognizer's
          // existence is stable for the full duration of any single gesture.
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: (!isPdf && _isZoomed) ? () => _applyZoom(1.0) : null,
            child: InteractiveViewer(
            transformationController: _transformController,
            minScale: AppConstants.minZoom,
            maxScale: AppConstants.maxZoom,
            constrained: false, // lets content exceed viewport when zoomed in

            // Scale (pinch) only during an actual 2-finger gesture — see the
            // long comment above scaleEnabled below for why that one stays
            // strictly multi-touch-gated.
            //
            // Pan is gated differently: multi-touch OR already zoomed in
            // (_isZoomed — see the onDoubleTap comment above for why this
            // isn't the live per-frame zoom value). At 1× zoom, single-finger
            // drags are reserved for SelectionArea (this is what makes text
            // selection work at all). But once the user has deliberately
            // zoomed in, panning around with one finger is the expected
            // behavior (same as Google Photos, Maps, etc.) — requiring 2
            // fingers just to look around a zoomed page was needlessly
            // awkward. This does reopen the same recognizer that competes
            // with SelectionArea, but only *while already zoomed*, which is
            // an acceptable trade: at that point the user has shown
            // pan/inspect intent over select intent. If this makes
            // selection flaky specifically while zoomed, that's the
            // trade-off to revisit.
            //
            // Both flags are forced off entirely for PDF — see the isPdf
            // comment at the top of this method.
            panEnabled:   !isPdf && (_multiTouch || _isZoomed),
            // Kept strictly multi-touch (and off entirely for PDF). Beyond
            // the reasons above: InteractiveViewer uses a SINGLE
            // ScaleGestureRecognizer for both single-finger pan and
            // multi-finger pinch (that recognizer naturally handles 1-finger
            // drags as "scale 1.0 + translation"), so leaving scaleEnabled
            // always-on meant that recognizer stayed active and kept
            // competing with SelectionArea's long-press recognizer for
            // EVERY single-finger touch everywhere in the document — not
            // just when zoomed — which is why text selection was unreliable
            // across all file types, not only in one view.
            scaleEnabled: !isPdf && _multiTouch,

            onInteractionUpdate: (_) {
              // Write straight to the ValueNotifier — no setState here.
              // This fires every single frame of an active pinch; a
              // setState() in this callback was rebuilding the entire
              // Scaffold body 60 times a second, which was the main cause
              // of pinch-zoom feeling stuttery. _isZoomed deliberately
              // stays untouched here too — see the onDoubleTap comment above
              // for why.
              final s = _transformController.value.getMaxScaleOnAxis();
              if ((s - _zoomNotifier.value).abs() > 0.01) {
                _zoomNotifier.value = s;
              }
            },
            onInteractionEnd: (_) {
              // Gesture has fully ended — safe to settle _isZoomed now (a
              // real setState here is fine; it happens once per gesture,
              // not once per frame).
              final s = _transformController.value.getMaxScaleOnAxis();
              if (s <= 1.005) {
                _transformController.value = Matrix4.identity();
                _zoomNotifier.value = 1.0;
                if (_isZoomed) setState(() => _isZoomed = false);
              } else if (!_isZoomed) {
                setState(() => _isZoomed = true);
              }
            },

            child: SizedBox(
              // Explicit viewport dimensions give the inner ListView bounded
              // height constraints (constrained:false would pass ∞ otherwise).
              width:  viewW,
              height: viewH,
              child: AbsorbPointer(
                // Only block child touch events during a 2-finger gesture
                // (pinch) — and never for PDF, where there's no gesture to
                // protect here (see the isPdf comment above) and blocking
                // would just stop PdfViewPinch from seeing the pinch itself.
                // Absorbing based on zoom level too would also
                // block SelectionArea's long-press, preventing text copy
                // entirely whenever the document is zoomed in.
                absorbing: !isPdf && _multiTouch,
                // No Center/ConstrainedBox(maxWidth: documentMaxWidth) here
                // anymore — that capped every file type's reading column at
                // 780px, centered with empty space on either side on any
                // screen wider than that (tablets, landscape, wide phones).
                // Content now fills the full available width for DOCX, PDF,
                // and XLSX alike. documentMaxWidth itself is kept for
                // _ImageWidget, which still needs *some* sane ceiling for an
                // embedded image with no explicit size of its own — that
                // usage now derives from the actual available width instead
                // of this constant, so it stays consistent with this change.
                child: Theme(
                  // Reading theme (Sáng/Sepia/Tối/Tương phản cao) is a
                  // per-viewer preference independent of the app's system
                  // theme — document content is normally forced to
                  // light/paper-white regardless of dark mode, but the
                  // user can explicitly opt into one of 4 reading
                  // surfaces here. text_run_builder already adapts
                  // hardcoded document colors for legibility based on
                  // Theme.of(context).brightness, so switching this is
                  // sufficient for all 4 modes.
                  data: AppTheme.forReadingMode(readingTheme),
                  child: Container(
                    color: paperColor,
                    child: SelectionArea(
                      child: DocumentRendererWidget(
                        model:            state.model!,
                        scrollController: _scrollController,
                        onLinkTap:        _handleLinkTap,
                        baseFontSize:     fontSize,
                        lineSpacing:      lineSpacing,
                        horizontalMargin: horizontalMargin,
                        pdfInitialPage:   _currentPdfPage,
                        onPdfPageChanged: _onPdfPageChanged,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          ),
        ]);
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// APP BAR
// ═══════════════════════════════════════════════════════════════════════════════

class _ViewerAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final DocumentState state;
  // ValueListenable instead of a plain double so the live zoom % readout
  // can update every pinch frame via ValueListenableBuilder below, without
  // rebuilding the rest of this AppBar (search button, popup menu, etc.) —
  // see the ValueNotifier field comment in _ViewerScreenState for the full
  // story on why the old plain-double + setState was a stutter source.
  final ValueListenable<double> currentZoom;
  final ReadingThemeMode readingTheme;
  final bool          isSpeaking;
  final VoidCallback  onBack;
  final VoidCallback  onZoomIn;
  final VoidCallback  onZoomOut;
  final VoidCallback  onZoomReset;
  final VoidCallback  onSearch;
  final VoidCallback  onWarnings;
  final VoidCallback  onToc;
  final VoidCallback  onShare;
  final VoidCallback  onFavorite;
  final VoidCallback  onStats;
  final VoidCallback  onReadingTheme;
  final VoidCallback  onBookmark;
  final VoidCallback  onTts;
  final VoidCallback  onCollections;
  final VoidCallback  onEdit;
  final VoidCallback  onPrint;

  const _ViewerAppBar({
    required this.state,
    required this.currentZoom,
    required this.readingTheme,
    required this.isSpeaking,
    required this.onBack,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
    required this.onSearch,
    required this.onWarnings,
    required this.onToc,
    required this.onShare,
    required this.onFavorite,
    required this.onStats,
    required this.onReadingTheme,
    required this.onBookmark,
    required this.onTts,
    required this.onCollections,
    required this.onEdit,
    required this.onPrint,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchState = ref.watch(searchNotifierProvider);
    final fileName    = state.currentFileName ?? 'Document';

    return AppBar(
      leading: IconButton(
        icon:      const Icon(Icons.arrow_back),
        onPressed: onBack,
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize:       MainAxisSize.min,
        children: [
          Text(
            fileName,
            style:    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (state.isLoaded && state.model != null)
            Text(
              '${state.model!.blockCount} blocks'
              '${state.model!.equationCount > 0 ? ' · ${state.model!.equationCount} eq.' : ''}'
              '${state.model!.images.isNotEmpty ? ' · ${state.model!.images.length} img' : ''}'
              '${searchState.isSearching ? ' · ${searchState.statusText}' : ''}',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
        ],
      ),
      actions: [
        // Search toggle
        if (state.isLoaded)
          IconButton(
            icon: Icon(
              searchState.isOpen ? Icons.search_off : Icons.search,
              color: searchState.isOpen ? Colors.orange.shade200 : null,
            ),
            tooltip:  'Tìm kiếm',
            onPressed: onSearch,
          ),

        // Zoom controls — all three wrapped in one ValueListenableBuilder so
        // they rebuild together, and only when the zoom value itself
        // changes, not on every other AppBar rebuild.
        if (state.isLoaded)
          ValueListenableBuilder<double>(
            valueListenable: currentZoom,
            builder: (context, zoom, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon:      const Icon(Icons.zoom_out, size: 20),
                  tooltip:   'Thu nhỏ',
                  onPressed: zoom > AppConstants.minZoom ? onZoomOut : null,
                ),
                GestureDetector(
                  onTap: onZoomReset,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Center(
                      child: Text(
                        '${(zoom * 100).round()}%',
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon:      const Icon(Icons.zoom_in, size: 20),
                  tooltip:   'Phóng to',
                  onPressed: zoom < AppConstants.maxZoom ? onZoomIn : null,
                ),
              ],
            ),
          ),

        // More actions menu
        if (state.isLoaded)
          PopupMenuButton<_AppBarAction>(
            icon: const Icon(Icons.more_vert),
            onSelected: (action) {
              switch (action) {
                case _AppBarAction.toc:         onToc();
                case _AppBarAction.share:       onShare();
                case _AppBarAction.favorite:    onFavorite();
                case _AppBarAction.stats:       onStats();
                case _AppBarAction.readingTheme: onReadingTheme();
                case _AppBarAction.bookmark:    onBookmark();
                case _AppBarAction.tts:         onTts();
                case _AppBarAction.collections: onCollections();
                case _AppBarAction.edit:        onEdit();
                case _AppBarAction.print:       onPrint();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _AppBarAction.toc,
                child: Row(children: [
                  Icon(Icons.list_alt_outlined, size: 18),
                  SizedBox(width: 12), Text('Mục lục'),
                ]),
              ),
              PopupMenuItem(
                value: _AppBarAction.bookmark,
                child: const Row(children: [
                  Icon(Icons.bookmark_add_outlined, size: 18),
                  SizedBox(width: 12), Text('Đánh dấu trang này'),
                ]),
              ),
              const PopupMenuItem(
                value: _AppBarAction.favorite,
                child: Row(children: [
                  Icon(Icons.star_outline, size: 18),
                  SizedBox(width: 12), Text('Thêm yêu thích'),
                ]),
              ),
              const PopupMenuItem(
                value: _AppBarAction.collections,
                child: Row(children: [
                  Icon(Icons.folder_special_outlined, size: 18),
                  SizedBox(width: 12), Text('Thêm vào bộ sưu tập'),
                ]),
              ),
              PopupMenuItem(
                value: _AppBarAction.readingTheme,
                child: Row(children: [
                  Icon(_readingThemeIcon(readingTheme), size: 18),
                  const SizedBox(width: 12),
                  const Text('Giao diện đọc'),
                ]),
              ),
              PopupMenuItem(
                value: _AppBarAction.tts,
                child: Row(children: [
                  Icon(isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined, size: 18),
                  const SizedBox(width: 12),
                  Text(isSpeaking ? 'Dừng đọc' : 'Đọc to văn bản'),
                ]),
              ),
              const PopupMenuItem(
                value: _AppBarAction.share,
                child: Row(children: [
                  Icon(Icons.share_outlined, size: 18),
                  SizedBox(width: 12), Text('Chia sẻ'),
                ]),
              ),
              const PopupMenuItem(
                value: _AppBarAction.stats,
                child: Row(children: [
                  Icon(Icons.info_outline, size: 18),
                  SizedBox(width: 12), Text('Thông tin tài liệu'),
                ]),
              ),
              if ((state.currentFileName ?? '').toLowerCase().endsWith('.docx') ||
                  (state.currentFileName ?? '').toLowerCase().endsWith('.xlsx'))
                const PopupMenuItem(
                  value: _AppBarAction.edit,
                  child: Row(children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 12), Text('Chỉnh sửa'),
                  ]),
                ),
              if ((state.currentFileName ?? '').toLowerCase().endsWith('.pdf'))
                const PopupMenuItem(
                  value: _AppBarAction.print,
                  child: Row(children: [
                    Icon(Icons.print_outlined, size: 18),
                    SizedBox(width: 12), Text('In tài liệu'),
                  ]),
                ),
            ],
          ),

        // Warnings badge
        if (state.isLoaded && state.model != null && state.model!.hasWarnings)
          IconButton(
            tooltip: '${state.model!.parseWarnings.length} cảnh báo',
            icon: Badge(
              label: Text('${state.model!.parseWarnings.length}'),
              child: const Icon(Icons.warning_amber_outlined),
            ),
            onPressed: onWarnings,
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WARNINGS PANEL
// ═══════════════════════════════════════════════════════════════════════════════

class _WarningsPanel extends StatelessWidget {
  final List<String> warnings;
  final VoidCallback onDismiss;

  const _WarningsPanel({required this.warnings, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Material(
        elevation: 8,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 220),
          color:        const Color(0xFFFFF8E1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Color(0xFFF57F17), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${warnings.length} parse warning(s)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600, color: Color(0xFFF57F17)),
                      ),
                    ),
                    IconButton(
                      icon:      const Icon(Icons.close, size: 18),
                      onPressed: onDismiss,
                      color:     const Color(0xFFF57F17),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap:  true,
                  padding:     const EdgeInsets.all(12),
                  itemCount:   warnings.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child:   Text('• ${warnings[i]}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF5D4037))),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Supporting types ──────────────────────────────────────────────────────────

enum _AppBarAction { toc, share, favorite, stats, readingTheme, bookmark, tts, collections, edit, print }

IconData _readingThemeIcon(ReadingThemeMode mode) => switch (mode) {
      ReadingThemeMode.light        => Icons.wb_sunny_outlined,
      ReadingThemeMode.sepia        => Icons.menu_book_outlined,
      ReadingThemeMode.dark         => Icons.dark_mode_outlined,
      ReadingThemeMode.highContrast => Icons.contrast_outlined,
    };

class _StatRow {
  final String label;
  final String value;
  const _StatRow(this.label, this.value);
}
