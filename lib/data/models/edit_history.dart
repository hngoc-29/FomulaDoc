import 'document_edit.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// EDIT HISTORY  (undo / redo stack)
// ═══════════════════════════════════════════════════════════════════════════════

/// Maintains the undo and redo stacks for document editing.
///
/// Usage:
/// ```dart
/// final history = EditHistory();
/// history.record(InsertTextEdit(...));
/// final last = history.undo();   // pops undo, pushes redo
/// history.redo();                // pops redo, pushes undo
/// ```
///
/// Not thread-safe; call only from the main isolate.
class EditHistory {
  EditHistory({this.maxDepth = 100});

  /// Maximum number of undo steps retained.
  final int maxDepth;

  final List<DocumentEdit> _undoStack = [];
  final List<DocumentEdit> _redoStack = [];

  // ── Queries ───────────────────────────────────────────────────────────────

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  int get undoCount => _undoStack.length;
  int get redoCount => _redoStack.length;

  /// Description of the last action that can be undone (e.g. "Undo Bold").
  String get undoDescription =>
      _undoStack.isEmpty ? '' : 'Undo ${_undoStack.last.description}';

  /// Description of the last action that can be re-applied.
  String get redoDescription =>
      _redoStack.isEmpty ? '' : 'Redo ${_redoStack.last.description}';

  // ── Mutations ─────────────────────────────────────────────────────────────

  /// Records [edit] on the undo stack and clears the redo stack.
  ///
  /// Any new edit invalidates the redo history (standard editor behaviour).
  void record(DocumentEdit edit) {
    _undoStack.add(edit);
    _redoStack.clear();
    // Enforce depth limit (FIFO eviction of oldest)
    if (_undoStack.length > maxDepth) {
      _undoStack.removeAt(0);
    }
  }

  /// Pops the most recent edit from undo → redo and returns it.
  ///
  /// The caller is responsible for reversing the edit's effect on the model.
  /// Returns `null` when the undo stack is empty.
  DocumentEdit? undo() {
    if (_undoStack.isEmpty) return null;
    final edit = _undoStack.removeLast();
    _redoStack.add(edit);
    return edit;
  }

  /// Pops the most recent edit from redo → undo and returns it.
  ///
  /// The caller is responsible for re-applying the edit's effect on the model.
  /// Returns `null` when the redo stack is empty.
  DocumentEdit? redo() {
    if (_redoStack.isEmpty) return null;
    final edit = _redoStack.removeLast();
    _undoStack.add(edit);
    return edit;
  }

  /// Clears both stacks (e.g. after saving or loading a new document).
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }

  // ── Inspection ────────────────────────────────────────────────────────────

  /// Returns the last [n] undo-able operations, newest first.
  List<DocumentEdit> recentEdits([int n = 10]) {
    final start = (_undoStack.length - n).clamp(0, _undoStack.length);
    return _undoStack.sublist(start).reversed.toList();
  }

  @override
  String toString() =>
      'EditHistory(undo=$undoCount, redo=$redoCount)';
}
