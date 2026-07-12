import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../../core/utils/logger.dart';
import '../../data/models/document_block.dart';
import '../../data/models/document_edit.dart';
import '../../data/models/document_model.dart';
import '../../data/models/edit_history.dart';
import '../../data/serializers/docx_serializer.dart';
import 'service_providers.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════════════════════════

class EditorState {
  final DocumentModel? original;
  final DocumentModel? current;
  final EditHistory    history;
  final bool           hasUnsavedChanges;
  final bool           isSaving;
  final String?        saveError;

  EditorState({
    this.original,
    this.current,
    EditHistory? history,
    this.hasUnsavedChanges = false,
    this.isSaving          = false,
    this.saveError,
  }) : history = history ?? EditHistory();

  bool get canUndo  => history.canUndo;
  bool get canRedo  => history.canRedo;
  bool get hasModel => current != null;

  EditorState copyWith({
    DocumentModel? original,
    DocumentModel? current,
    EditHistory?   history,
    bool?          hasUnsavedChanges,
    bool?          isSaving,
    String?        saveError,
  }) =>
      EditorState(
        original:          original          ?? this.original,
        current:           current           ?? this.current,
        history:           history           ?? this.history,
        hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
        isSaving:          isSaving          ?? this.isSaving,
        saveError:         saveError,
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// NOTIFIER  —  full text-level edit implementation
// ═══════════════════════════════════════════════════════════════════════════════

class EditorNotifier extends StateNotifier<EditorState> {
  final Ref            _ref;
  final DocxSerializer _serializer;

  EditorNotifier(this._ref, this._serializer)
      : super(EditorState(history: EditHistory()));

  // ── Binding ───────────────────────────────────────────────────────────────

  void loadDocument(DocumentModel model) {
    state = EditorState(
      original: model,
      current:  model,
      history:  EditHistory(maxDepth: 100),
    );
  }

  void markSaved() => state = state.copyWith(
        original:          state.current,
        hasUnsavedChanges: false,
      );

  // ── Apply ─────────────────────────────────────────────────────────────────

  void applyEdit(DocumentEdit edit) {
    final current = state.current;
    if (current == null) return;
    final updated = _apply(current, edit);
    if (updated == null) return;
    state.history.record(edit);
    state = state.copyWith(current: updated, hasUnsavedChanges: true);
    AppLogger.debug('Applied: ${edit.description}', tag: 'EditorNotifier');
  }

  void undo() {
    final edit = state.history.undo();
    if (edit == null) return;
    _rebuildFromHistory();
    AppLogger.debug('Undo: ${edit.description}', tag: 'EditorNotifier');
  }

  void redo() {
    final edit = state.history.redo();
    if (edit == null) return;
    final updated = _apply(state.current!, edit);
    if (updated != null) {
      state = state.copyWith(current: updated, hasUnsavedChanges: true);
    }
  }

  // ── High-level helpers ────────────────────────────────────────────────────

  void applyBold(String blockId, int charStart, int charEnd) =>
      applyEdit(ApplyRunStyleEdit(
        blockId:      blockId,
        charStart:    charStart,
        charEnd:      charEnd,
        newStyle:     const TextRunStyle(bold: true),
        previousRuns: _runsOf(blockId) ?? [],
      ));

  void applyItalic(String blockId, int charStart, int charEnd) =>
      applyEdit(ApplyRunStyleEdit(
        blockId:      blockId,
        charStart:    charStart,
        charEnd:      charEnd,
        newStyle:     const TextRunStyle(italic: true),
        previousRuns: _runsOf(blockId) ?? [],
      ));

  void insertParagraphAfter(String blockId) => applyEdit(InsertBlockEdit(
        afterIndex: _indexOf(blockId),
        block: ParagraphBlock(
          id:   'new_${DateTime.now().millisecondsSinceEpoch}',
          runs: const [],
        ),
      ));

  void deleteBlock(String blockId) {
    final current = state.current;
    if (current == null) return;
    final idx = _indexOf(blockId);
    if (idx == -1) return;
    applyEdit(DeleteBlockEdit(
      blockId:       blockId,
      deletedBlock:  current.blocks[idx],
      originalIndex: idx,
    ));
  }

  // ── Export ────────────────────────────────────────────────────────────────

  Future<Uint8List?> exportDocx() async {
    final current = state.current;
    if (current == null) return null;
    state = state.copyWith(isSaving: true, saveError: null);
    try {
      final bytes = await _serializer.serialize(current);
      markSaved();
      state = state.copyWith(isSaving: false);
      return bytes;
    } catch (e) {
      state = state.copyWith(isSaving: false, saveError: e.toString());
      return null;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // EDIT APPLICATION ENGINE
  // ═════════════════════════════════════════════════════════════════════════════

  DocumentModel? _apply(DocumentModel m, DocumentEdit edit) {
    try {
      return switch (edit) {
        InsertTextEdit()         => _applyInsertText(m, edit),
        DeleteTextEdit()         => _applyDeleteText(m, edit),
        ReplaceTextEdit()        => _applyReplaceText(m, edit),
        ApplyRunStyleEdit()      => _applyRunStyle(m, edit),
        SetAlignmentEdit()       => _applyAlignment(m, edit),
        InsertBlockEdit()        => _applyInsertBlock(m, edit),
        DeleteBlockEdit()        => _applyDeleteBlock(m, edit),
        MoveBlockEdit()          => _applyMoveBlock(m, edit),
        ChangeHeadingLevelEdit() => _applyHeadingChange(m, edit),
        InsertTableRowEdit()     => null, // Phase 6
        DeleteTableRowEdit()     => null, // Phase 6
        CompositeEdit()          => _applyComposite(m, edit),
      };
    } catch (e) {
      AppLogger.warning('Edit apply failed: $e', tag: 'EditorNotifier');
      return null;
    }
  }

  // ── Insert text ───────────────────────────────────────────────────────────

  DocumentModel _applyInsertText(DocumentModel m, InsertTextEdit edit) {
    final blocks  = List<DocumentBlock>.from(m.blocks);
    final blockIdx = blocks.indexWhere((b) => b.id == edit.blockId);
    if (blockIdx == -1) return m;

    final block = blocks[blockIdx];
    final runs  = _editableRuns(block);
    if (runs == null || edit.runIndex >= runs.length) return m;

    final run    = runs[edit.runIndex];
    final offset = edit.charOffset.clamp(0, run.text.length);
    final newText = run.text.substring(0, offset)
        + edit.text
        + run.text.substring(offset);

    final newRuns = List<TextRun>.from(runs)
      ..[edit.runIndex] = TextRun(text: newText, style: run.style);

    blocks[blockIdx] = _withRuns(block, _mergeAdjacent(newRuns));
    return m.copyWith(blocks: blocks);
  }

  // ── Delete text ───────────────────────────────────────────────────────────

  DocumentModel _applyDeleteText(DocumentModel m, DeleteTextEdit edit) {
    final blocks   = List<DocumentBlock>.from(m.blocks);
    final blockIdx = blocks.indexWhere((b) => b.id == edit.blockId);
    if (blockIdx == -1) return m;

    final block = blocks[blockIdx];
    final runs  = _editableRuns(block);
    if (runs == null) return m;

    final newRuns = _deleteRange(runs, edit.charStart, edit.charEnd);
    blocks[blockIdx] = _withRuns(block, _mergeAdjacent(newRuns));
    return m.copyWith(blocks: blocks);
  }

  // ── Replace text ──────────────────────────────────────────────────────────

  DocumentModel _applyReplaceText(DocumentModel m, ReplaceTextEdit edit) {
    // Delete then insert
    final after1 = _applyDeleteText(m,
        DeleteTextEdit(
          blockId:     edit.blockId,
          runIndex:    edit.runIndex,
          charStart:   edit.charStart,
          charEnd:     edit.charEnd,
          deletedText: edit.originalText,
        ));
    return _applyInsertText(after1,
        InsertTextEdit(
          blockId:    edit.blockId,
          runIndex:   edit.runIndex,
          charOffset: edit.charStart,
          text:       edit.newText,
        ));
  }

  // ── Apply run style ───────────────────────────────────────────────────────

  DocumentModel _applyRunStyle(DocumentModel m, ApplyRunStyleEdit edit) {
    final blocks   = List<DocumentBlock>.from(m.blocks);
    final blockIdx = blocks.indexWhere((b) => b.id == edit.blockId);
    if (blockIdx == -1) return m;

    final block = blocks[blockIdx];
    final runs  = _editableRuns(block);
    if (runs == null) return m;

    final newRuns = _splitAndStyle(runs, edit.charStart, edit.charEnd, edit.newStyle);
    blocks[blockIdx] = _withRuns(block, _mergeAdjacent(newRuns));
    return m.copyWith(blocks: blocks);
  }

  // ── Alignment ─────────────────────────────────────────────────────────────

  DocumentModel _applyAlignment(DocumentModel m, SetAlignmentEdit edit) {
    final blocks   = List<DocumentBlock>.from(m.blocks);
    final blockIdx = blocks.indexWhere((b) => b.id == edit.blockId);
    if (blockIdx == -1) return m;

    final block = blocks[blockIdx];
    if (block is ParagraphBlock) {
      blocks[blockIdx] = ParagraphBlock(
        id:         block.id,
        runs:       block.runs,
        properties: ParagraphProperties(
          alignment:            edit.newAlignment,
          spaceBeforePt:        block.properties.spaceBeforePt,
          spaceAfterPt:         block.properties.spaceAfterPt,
          lineHeightMultiplier: block.properties.lineHeightMultiplier,
          indentLeftPt:         block.properties.indentLeftPt,
          indentRightPt:        block.properties.indentRightPt,
          firstLineIndentPt:    block.properties.firstLineIndentPt,
        ),
        listInfo: block.listInfo,
      );
    }
    return m.copyWith(blocks: blocks);
  }

  // ── Block operations ──────────────────────────────────────────────────────

  DocumentModel _applyInsertBlock(DocumentModel m, InsertBlockEdit edit) {
    final blocks = List<DocumentBlock>.from(m.blocks);
    final idx    = (edit.afterIndex + 1).clamp(0, blocks.length);
    blocks.insert(idx, edit.block);
    return m.copyWith(blocks: blocks);
  }

  DocumentModel _applyDeleteBlock(DocumentModel m, DeleteBlockEdit edit) {
    final blocks = List<DocumentBlock>.from(m.blocks)
      ..removeWhere((b) => b.id == edit.blockId);
    return m.copyWith(blocks: blocks);
  }

  DocumentModel _applyMoveBlock(DocumentModel m, MoveBlockEdit edit) {
    final blocks = List<DocumentBlock>.from(m.blocks);
    if (edit.fromIndex < 0 || edit.fromIndex >= blocks.length) return m;
    final block = blocks.removeAt(edit.fromIndex);
    blocks.insert(edit.toIndex.clamp(0, blocks.length), block);
    return m.copyWith(blocks: blocks);
  }

  DocumentModel _applyHeadingChange(DocumentModel m, ChangeHeadingLevelEdit edit) {
    final blocks   = List<DocumentBlock>.from(m.blocks);
    final blockIdx = blocks.indexWhere((b) => b.id == edit.blockId);
    if (blockIdx == -1) return m;

    final block = blocks[blockIdx];
    final runs  = _editableRuns(block) ?? [];
    final props = block is ParagraphBlock
        ? block.properties
        : block is HeadingBlock ? block.properties : ParagraphProperties.empty;

    if (edit.newLevel != null) {
      blocks[blockIdx] = HeadingBlock(
        id:         block.id,
        runs:       runs,
        level:      edit.newLevel!,
        properties: props,
      );
    } else {
      blocks[blockIdx] = ParagraphBlock(
        id:         block.id,
        runs:       runs,
        properties: props,
      );
    }
    return m.copyWith(blocks: blocks);
  }

  DocumentModel _applyComposite(DocumentModel m, CompositeEdit edit) {
    var model = m;
    for (final e in edit.edits) {
      model = _apply(model, e) ?? model;
    }
    return model;
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // RUN MANIPULATION HELPERS
  // ═════════════════════════════════════════════════════════════════════════════

  /// Splits runs at [charStart]..[charEnd] and applies [style] to the middle.
  List<TextRun> _splitAndStyle(
    List<TextRun>  runs,
    int            charStart,
    int            charEnd,
    TextRunStyle   newStyle,
  ) {
    final result = <TextRun>[];
    int offset   = 0;

    for (final run in runs) {
      final runEnd = offset + run.text.length;

      if (runEnd <= charStart || offset >= charEnd) {
        result.add(run);
      } else {
        final splitStart = (charStart - offset).clamp(0, run.text.length);
        final splitEnd   = (charEnd   - offset).clamp(0, run.text.length);

        if (splitStart > 0) {
          result.add(TextRun(
            text:  run.text.substring(0, splitStart),
            style: run.style,
            url:   run.url,
          ));
        }
        result.add(TextRun(
          text:  run.text.substring(splitStart, splitEnd),
          style: run.style.merge(newStyle),
          url:   run.url,
        ));
        if (splitEnd < run.text.length) {
          result.add(TextRun(
            text:  run.text.substring(splitEnd),
            style: run.style,
            url:   run.url,
          ));
        }
      }
      offset = runEnd;
    }
    return result;
  }

  /// Removes chars [charStart]..[charEnd] across run boundaries.
  List<TextRun> _deleteRange(List<TextRun> runs, int charStart, int charEnd) {
    final result = <TextRun>[];
    int offset   = 0;

    for (final run in runs) {
      final runEnd = offset + run.text.length;

      if (runEnd <= charStart || offset >= charEnd) {
        result.add(run);
      } else {
        final keepBefore = charStart > offset
            ? run.text.substring(0, charStart - offset)
            : '';
        final keepAfter = charEnd < runEnd
            ? run.text.substring(charEnd - offset)
            : '';
        if (keepBefore.isNotEmpty) {
          result.add(TextRun(text: keepBefore, style: run.style, url: run.url));
        }
        if (keepAfter.isNotEmpty) {
          result.add(TextRun(text: keepAfter,  style: run.style, url: run.url));
        }
      }
      offset = runEnd;
    }

    if (result.isEmpty) {
      result.add(const TextRun(text: '', style: TextRunStyle.empty));
    }
    return result;
  }

  /// Merges adjacent runs with identical style (reduces run count after edits).
  List<TextRun> _mergeAdjacent(List<TextRun> runs) {
    if (runs.length <= 1) return runs;
    final merged = <TextRun>[runs.first];

    for (int i = 1; i < runs.length; i++) {
      final prev = merged.last;
      final cur  = runs[i];
      final sameStyle = prev.style.bold      == cur.style.bold      &&
                        prev.style.italic    == cur.style.italic    &&
                        prev.style.underline == cur.style.underline &&
                        prev.style.colorArgb == cur.style.colorArgb &&
                        prev.style.fontSizePt== cur.style.fontSizePt&&
                        prev.url             == cur.url;
      if (sameStyle) {
        merged[merged.length - 1] = TextRun(
          text:  prev.text + cur.text,
          style: prev.style,
          url:   prev.url,
        );
      } else {
        merged.add(cur);
      }
    }
    return merged;
  }

  // ── Block accessors ───────────────────────────────────────────────────────

  List<TextRun>? _editableRuns(DocumentBlock block) => switch (block) {
        ParagraphBlock() => block.runs,
        HeadingBlock()   => block.runs,
        _                => null,
      };

  List<TextRun>? _runsOf(String blockId) {
    final block = state.current?.blocks
        .where((b) => b.id == blockId)
        .firstOrNull;
    return block != null ? _editableRuns(block) : null;
  }

  DocumentBlock _withRuns(DocumentBlock block, List<TextRun> runs) =>
      switch (block) {
        ParagraphBlock() => ParagraphBlock(
            id:         block.id,
            runs:       runs,
            properties: block.properties,
            listInfo:   block.listInfo,
          ),
        HeadingBlock() => HeadingBlock(
            id:         block.id,
            runs:       runs,
            level:      block.level,
            properties: block.properties,
          ),
        _ => block,
      };

  int _indexOf(String blockId) =>
      state.current?.blocks.indexWhere((b) => b.id == blockId) ?? -1;

  // ── History rebuild ───────────────────────────────────────────────────────

  void _rebuildFromHistory() {
    var model = state.original;
    if (model == null) return;
    for (final edit in state.history.recentEdits(state.history.undoCount).reversed) {
      model = _apply(model!, edit) ?? model;
    }
    state = state.copyWith(
      current:           model,
      hasUnsavedChanges: state.history.canUndo,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

final editorNotifierProvider =
    StateNotifierProvider.autoDispose<EditorNotifier, EditorState>(
  (ref) => EditorNotifier(ref, ref.read(docxSerializerProvider)),
  name: 'editorNotifierProvider',
);
