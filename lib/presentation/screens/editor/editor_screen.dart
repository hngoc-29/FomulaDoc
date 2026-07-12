import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/theme_constants.dart';
import '../../../data/models/document_block.dart'
    hide TableRow, TableCell;
import '../../../data/models/document_edit.dart';
import '../../../data/models/document_model.dart';
import '../../providers/editor_provider.dart';
import '../../../services/version_history_service.dart';

/// A focused, MVP DOCX editor: lets the user edit paragraph/heading text and
/// toggle Bold / Italic / Underline on a selection, then save back to the
/// original .docx file.
///
/// Scope intentionally limited to text-run editing (the parts of the
/// document infrastructure — [DocumentEdit], [EditHistory], [DocxSerializer]
/// — that were already fully implemented). Tables, images, and equations are
/// shown read-only; inserting/deleting whole blocks is not exposed in this
/// first pass.
class EditorScreen extends ConsumerStatefulWidget {
  final DocumentModel model;
  final String        filePath;
  final String        fileName;

  const EditorScreen({
    super.key,
    required this.model,
    required this.filePath,
    required this.fileName,
  });

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode>              _focusNodes  = {};
  String? _focusedBlockId;

  @override
  void initState() {
    super.initState();
    ref.read(editorNotifierProvider.notifier).loadDocument(widget.model);
    _rebuildControllers(widget.model);
  }

  void _rebuildControllers(DocumentModel model) {
    for (final block in model.blocks) {
      final text = switch (block) {
        ParagraphBlock() => block.plainText,
        HeadingBlock()   => block.plainText,
        _                => null,
      };
      if (text == null) continue;
      if (!_controllers.containsKey(block.id)) {
        final ctrl = TextEditingController(text: text);
        final node = FocusNode();
        node.addListener(() {
          if (node.hasFocus) setState(() => _focusedBlockId = block.id);
        });
        _controllers[block.id] = ctrl;
        _focusNodes[block.id]  = node;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    for (final n in _focusNodes.values) n.dispose();
    super.dispose();
  }

  // ── Style toggle ──────────────────────────────────────────────────────────

  void _toggleStyle({bool? bold, bool? italic, bool? underline}) {
    final blockId = _focusedBlockId;
    if (blockId == null) return;
    final ctrl = _controllers[blockId];
    if (ctrl == null) return;

    final sel = ctrl.selection;
    if (!sel.isValid || sel.isCollapsed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Bôi đen văn bản trước khi định dạng'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final editor = ref.read(editorNotifierProvider);
    final model  = editor.current;
    if (model == null) return;
    final block = model.blocks.firstWhere((b) => b.id == blockId);
    final runs  = switch (block) {
      ParagraphBlock() => block.runs,
      HeadingBlock()   => block.runs,
      _                => const <TextRun>[],
    };
    if (runs.isEmpty) return;

    // Determine current style at selection start (used as the base for
    // toggling — this keeps other attributes like color/font untouched).
    int consumed = 0;
    TextRunStyle baseStyle = runs.first.style;
    for (final r in runs) {
      if (sel.start < consumed + r.text.length) { baseStyle = r.style; break; }
      consumed += r.text.length;
    }

    final newStyle = baseStyle.copyWith(
      bold:      bold      ?? baseStyle.bold,
      italic:    italic    ?? baseStyle.italic,
      underline: underline ?? baseStyle.underline,
    );

    ref.read(editorNotifierProvider.notifier).applyEdit(ApplyRunStyleEdit(
      blockId:      blockId,
      charStart:    sel.start,
      charEnd:      sel.end,
      newStyle:     newStyle,
      previousRuns: runs,
    ));
  }

  // ── Text change ───────────────────────────────────────────────────────────
  //
  // IMPORTANT SAFETY NOTE: DocumentEdit's Insert/Delete/Replace text
  // primitives operate on a SINGLE run (runIndex + local character offset).
  // A TextField's onChanged gives us the whole block's new text, which for
  // multi-run paragraphs (e.g. "normal text **bold text** more normal") would
  // require correctly diffing across run boundaries — getting this wrong
  // risks silently corrupting the user's real .docx content on save.
  // To avoid that risk, free-text typing here is only wired up for blocks
  // that have exactly ONE run (the common case for simple paragraphs).
  // Multi-run paragraphs remain read-only in this first editor pass; the
  // Bold/Italic/Underline toolbar (which uses the already-implemented,
  // range-safe ApplyRunStyleEdit/_splitAndStyle path) still works everywhere.

  void _onTextChanged(String blockId, String newText) {
    final editor = ref.read(editorNotifierProvider);
    final model  = editor.current;
    if (model == null) return;
    final block = model.blocks.firstWhere((b) => b.id == blockId);
    final runs  = switch (block) {
      ParagraphBlock() => block.runs,
      HeadingBlock()   => block.runs,
      _                => const <TextRun>[],
    };
    if (runs.length != 1) return;  // see safety note above

    final oldText = runs.first.text;
    if (newText == oldText) return;

    // Simple, correct common-prefix/common-suffix diff — safe because we've
    // already guaranteed this maps to exactly one run.
    int prefix = 0;
    final maxPrefix = oldText.length < newText.length ? oldText.length : newText.length;
    while (prefix < maxPrefix && oldText[prefix] == newText[prefix]) prefix++;

    int oldEnd = oldText.length, newEnd = newText.length;
    while (oldEnd > prefix && newEnd > prefix && oldText[oldEnd - 1] == newText[newEnd - 1]) {
      oldEnd--; newEnd--;
    }

    final deletedText  = oldText.substring(prefix, oldEnd);
    final insertedText = newText.substring(prefix, newEnd);

    ref.read(editorNotifierProvider.notifier).applyEdit(ReplaceTextEdit(
      blockId:      blockId,
      runIndex:     0,
      charStart:    prefix,
      charEnd:      oldEnd,
      newText:      insertedText,
      originalText: deletedText,
    ));
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final editor = ref.read(editorNotifierProvider);
    final model  = editor.current;
    if (model == null) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref.read(editorNotifierProvider.notifier).exportDocx();
      if (bytes == null) throw Exception('Không thể tạo file');

      // Snapshot the CURRENT on-disk content before overwriting, so an edit
      // gone wrong can always be recovered via "Lịch sử phiên bản".
      await VersionHistoryService().snapshotBeforeSave(widget.filePath);

      await File(widget.filePath).writeAsBytes(bytes);
      ref.read(editorNotifierProvider.notifier).markSaved();
      messenger.showSnackBar(const SnackBar(
        content: Text('Đã lưu tài liệu'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Lỗi khi lưu: $e'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _showVersionHistory() async {
    final svc = VersionHistoryService();
    final versions = await svc.listVersionsForPath(widget.filePath);
    if (!mounted) return;

    if (versions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Chưa có phiên bản cũ nào được lưu'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lịch sử phiên bản',
                style: Theme.of(sheetContext).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Lưu tối đa 5 phiên bản gần nhất trước mỗi lần lưu',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            ...versions.map((v) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history),
              title: Text(_formatVersionDate(v.savedAt)),
              subtitle: Text('${(v.sizeBytes / 1024).toStringAsFixed(1)} KB'),
              trailing: TextButton(
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Khôi phục phiên bản này?'),
                      content: Text(
                          'Nội dung hiện tại sẽ được lưu lại trước khi khôi phục, '
                          'nên bạn vẫn có thể quay lại nếu đổi ý.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
                        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Khôi phục')),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                  await svc.restore(widget.filePath, v);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Đã khôi phục — mở lại file để xem'),
                    behavior: SnackBarBehavior.floating,
                  ));
                  Navigator.of(context).pop(); // leave editor, viewer will reload
                },
                child: const Text('Khôi phục'),
              ),
            )),
          ],
        ),
      ),
    );
  }

  String _formatVersionDate(DateTime dt) {
    final now = DateTime.now();
    final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final time = '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    if (sameDay) return 'Hôm nay $time';
    return '${dt.day}/${dt.month}/${dt.year} $time';
  }

  Future<bool> _confirmDiscard() async {
    final editor = ref.read(editorNotifierProvider);
    if (!editor.hasUnsavedChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title:   const Text('Thoát mà không lưu?'),
        content: const Text('Các thay đổi chưa lưu sẽ bị mất.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Thoát')),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(editorNotifierProvider);
    _rebuildControllers(editor.current ?? widget.model);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: ThemeConstants.paperLight,
        appBar: AppBar(
          title: Text(widget.fileName, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Hoàn tác',
              onPressed: editor.canUndo
                  ? () => ref.read(editorNotifierProvider.notifier).undo()
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              tooltip: 'Làm lại',
              onPressed: editor.canRedo
                  ? () => ref.read(editorNotifierProvider.notifier).redo()
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Lịch sử phiên bản',
              onPressed: _showVersionHistory,
            ),
            TextButton.icon(
              onPressed: editor.hasUnsavedChanges ? _save : null,
              icon: editor.isSaving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined, color: Colors.white),
              label: const Text('Lưu', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: Column(
          children: [
            // ── Formatting toolbar ─────────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.format_bold),
                    tooltip: 'Đậm',
                    onPressed: () => _toggleStyle(bold: true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.format_italic),
                    tooltip: 'Nghiêng',
                    onPressed: () => _toggleStyle(italic: true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.format_underline),
                    tooltip: 'Gạch chân',
                    onPressed: () => _toggleStyle(underline: true),
                  ),
                  const Spacer(),
                  if (editor.hasUnsavedChanges)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Chưa lưu',
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.error)),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ── Editable content ───────────────────────────────────────────
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: (editor.current ?? widget.model).blocks.length,
                itemBuilder: (context, i) {
                  final block = (editor.current ?? widget.model).blocks[i];
                  return _buildBlockEditor(block);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockEditor(DocumentBlock block) {
    final ctrl = _controllers[block.id];
    final node = _focusNodes[block.id];

    if (ctrl == null || node == null) {
      // Non-text content (tables, images, equations) — show a locked hint.
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Text(_blockTypeLabel(block),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ]),
      );
    }

    final isHeading = block is HeadingBlock;
    final runs = switch (block) {
      ParagraphBlock() => block.runs,
      HeadingBlock()   => block.runs,
      _                => const <TextRun>[],
    };
    // Multi-run paragraphs (mixed formatting within one paragraph) are kept
    // read-only for typing — see the safety note on _onTextChanged. The
    // Bold/Italic/Underline toolbar still works on these via text selection.
    final isTypingSafe = runs.length <= 1;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: ctrl,
            focusNode:  node,
            maxLines:   null,
            readOnly:   !isTypingSafe,
            style: TextStyle(
              fontSize:   isHeading ? 20 : 15,
              fontWeight: isHeading ? FontWeight.bold : FontWeight.normal,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
            ),
            onChanged: isTypingSafe
                ? (text) => _onTextChanged(block.id, text)
                : null,
          ),
          if (!isTypingSafe)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Đoạn có nhiều định dạng khác nhau — chỉ đổi được Đậm/Nghiêng/Gạch chân bằng cách bôi đen, chưa gõ chữ mới trực tiếp được',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }

  String _blockTypeLabel(DocumentBlock block) => switch (block) {
        ImageBlock()      => 'Hình ảnh (không chỉnh sửa được)',
        EquationBlock()   => 'Công thức (không chỉnh sửa được)',
        TableBlock()      => 'Bảng (không chỉnh sửa được)',
        PdfDocumentBlock() => 'Nội dung PDF',
        SpreadsheetBlock() => 'Nội dung Excel',
        _                 => 'Nội dung khác',
      };
}
