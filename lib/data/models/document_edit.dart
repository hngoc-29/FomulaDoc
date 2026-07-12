import 'document_block.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DOCUMENT EDIT OPERATIONS  (Phase 5 — DOCX editor foundation)
// ═══════════════════════════════════════════════════════════════════════════════

/// Base class for all document edit operations.
///
/// Sealed so that [DocumentEditApplicator] must handle every operation type
/// at compile-time — adding a new operation forces all handlers to update.
///
/// Operations are designed to be:
///   • **Reversible** — each operation stores enough info to undo itself.
///   • **Composable** — multiple operations can be batched in [CompositeEdit].
///   • **Serializable** — pure Dart, no Flutter dependencies.
sealed class DocumentEdit {
  const DocumentEdit();

  /// Human-readable label shown in undo/redo UI (e.g. "Undo Bold").
  String get description;
}

// ── Text edits ────────────────────────────────────────────────────────────────

/// Inserts [text] at [charOffset] within the run at [runIndex] of [blockId].
final class InsertTextEdit extends DocumentEdit {
  final String blockId;
  final int runIndex;
  final int charOffset;
  final String text;

  const InsertTextEdit({
    required this.blockId,
    required this.runIndex,
    required this.charOffset,
    required this.text,
  });

  @override
  String get description => 'Type "${text.length > 20 ? '${text.substring(0, 20)}…' : text}"';
}

/// Deletes characters [charStart]..[charEnd] within a run.
final class DeleteTextEdit extends DocumentEdit {
  final String blockId;
  final int runIndex;
  final int charStart;
  final int charEnd;
  /// Original text removed — stored so the edit can be undone.
  final String deletedText;

  const DeleteTextEdit({
    required this.blockId,
    required this.runIndex,
    required this.charStart,
    required this.charEnd,
    required this.deletedText,
  });

  @override
  String get description => 'Delete text';
}

/// Replaces the text in a run's character range with [newText].
final class ReplaceTextEdit extends DocumentEdit {
  final String blockId;
  final int runIndex;
  final int charStart;
  final int charEnd;
  final String newText;
  final String originalText;

  const ReplaceTextEdit({
    required this.blockId,
    required this.runIndex,
    required this.charStart,
    required this.charEnd,
    required this.newText,
    required this.originalText,
  });

  @override
  String get description => 'Replace text';
}

// ── Style edits ───────────────────────────────────────────────────────────────

/// Applies [newStyle] to runs spanning [charStart]..[charEnd] in [blockId].
///
/// [previousRuns] stores the original run list for undo.
final class ApplyRunStyleEdit extends DocumentEdit {
  final String blockId;
  final int charStart;
  final int charEnd;
  final TextRunStyle newStyle;
  final List<TextRun> previousRuns;

  const ApplyRunStyleEdit({
    required this.blockId,
    required this.charStart,
    required this.charEnd,
    required this.newStyle,
    required this.previousRuns,
  });

  @override
  String get description {
    if (newStyle.bold)      return 'Bold';
    if (newStyle.italic)    return 'Italic';
    if (newStyle.underline) return 'Underline';
    return 'Apply style';
  }
}

/// Changes the paragraph alignment of [blockId].
final class SetAlignmentEdit extends DocumentEdit {
  final String blockId;
  final ParagraphAlignment newAlignment;
  final ParagraphAlignment oldAlignment;

  const SetAlignmentEdit({
    required this.blockId,
    required this.newAlignment,
    required this.oldAlignment,
  });

  @override
  String get description => 'Align ${newAlignment.name}';
}

// ── Block-level edits ─────────────────────────────────────────────────────────

/// Inserts a [block] after position [afterIndex] in the block list.
final class InsertBlockEdit extends DocumentEdit {
  final int afterIndex;
  final DocumentBlock block;

  const InsertBlockEdit({required this.afterIndex, required this.block});

  @override
  String get description => switch (block) {
        ParagraphBlock() => 'Insert paragraph',
        HeadingBlock()   => 'Insert heading',
        TableBlock()     => 'Insert table',
        ImageBlock()     => 'Insert image',
        _                => 'Insert block',
      };
}

/// Removes the block with [blockId].
final class DeleteBlockEdit extends DocumentEdit {
  final String blockId;
  /// Stored for undo.
  final DocumentBlock deletedBlock;
  /// Original position in block list for undo.
  final int originalIndex;

  const DeleteBlockEdit({
    required this.blockId,
    required this.deletedBlock,
    required this.originalIndex,
  });

  @override
  String get description => 'Delete ${deletedBlock.runtimeType.toString().replaceAll('Block', '').toLowerCase()}';
}

/// Moves [blockId] from [fromIndex] to [toIndex].
final class MoveBlockEdit extends DocumentEdit {
  final String blockId;
  final int fromIndex;
  final int toIndex;

  const MoveBlockEdit({
    required this.blockId,
    required this.fromIndex,
    required this.toIndex,
  });

  @override
  String get description => 'Move block';
}

// ── Heading edits ─────────────────────────────────────────────────────────────

/// Promotes / demotes a heading or converts a paragraph to a heading.
final class ChangeHeadingLevelEdit extends DocumentEdit {
  final String blockId;
  final HeadingLevel? newLevel; // null = convert to paragraph
  final HeadingLevel? oldLevel; // null = was a paragraph

  const ChangeHeadingLevelEdit({
    required this.blockId,
    required this.newLevel,
    required this.oldLevel,
  });

  @override
  String get description => newLevel != null
      ? 'Set ${newLevel!.name.toUpperCase()}'
      : 'Convert to paragraph';
}

// ── Table edits ───────────────────────────────────────────────────────────────

/// Inserts a row into [tableBlockId] at [rowIndex].
final class InsertTableRowEdit extends DocumentEdit {
  final String tableBlockId;
  final int rowIndex;

  const InsertTableRowEdit({required this.tableBlockId, required this.rowIndex});

  @override
  String get description => 'Insert table row';
}

/// Deletes row [rowIndex] from [tableBlockId].
final class DeleteTableRowEdit extends DocumentEdit {
  final String tableBlockId;
  final int rowIndex;
  final TableRow deletedRow;

  const DeleteTableRowEdit({
    required this.tableBlockId,
    required this.rowIndex,
    required this.deletedRow,
  });

  @override
  String get description => 'Delete table row';
}

// ── Composite edit (batch undo/redo) ──────────────────────────────────────────

/// Groups multiple edits into a single undo-able action.
///
/// Example: "Bold" applies bold to multiple runs → one undo step.
final class CompositeEdit extends DocumentEdit {
  final List<DocumentEdit> edits;
  final String _description;

  const CompositeEdit({required this.edits, required String description})
      : _description = description;

  @override
  String get description => _description;
}
