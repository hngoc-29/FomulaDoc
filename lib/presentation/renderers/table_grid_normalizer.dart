import '../../data/models/document_block.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TABLE GRID NORMALIZER
// ═══════════════════════════════════════════════════════════════════════════════

/// Flutter's [Table] widget requires every [TableRow] to have **exactly the
/// same number of children**. OOXML tables don't guarantee that: a row with
/// a merged cell (`gridSpan` / `colSpan > 1`) emits *fewer* `<w:tc>` elements
/// than a row without merges, even though both occupy the same number of
/// logical grid columns.
///
/// Without normalization, [Table] throws an assertion error at runtime the
/// first time a real-world DOCX with merged cells is opened. This class
/// prevents that by padding short rows with invisible filler cells so every
/// row has the same cell *count*, while still respecting [TableCellProperties.colSpan]
/// for visual width hints.
///
/// Pure Dart — no Flutter import — so it is independently unit-testable.
class TableGridNormalizer {
  TableGridNormalizer._();

  /// Returns a new list of rows where every row has the same number of cells
  /// (`columnCount`), padding short rows with empty filler cells at the end.
  ///
  /// [columnCount] is the logical grid width, computed as the maximum over
  /// all rows of `sum(cell.colSpan for cell in row)`.
  static List<TableRow> normalize(List<TableRow> rows) {
    if (rows.isEmpty) return rows;

    final columnCount = computeColumnCount(rows);
    if (columnCount == 0) return rows;

    return rows.map((row) {
      final occupied = row.cells.fold<int>(
        0,
        (sum, c) => sum + c.properties.colSpan.clamp(1, columnCount),
      );
      if (occupied >= columnCount) return row;

      final filler = List.generate(
        columnCount - occupied,
        (_) => const TableCell(content: []),
      );
      return TableRow(cells: [...row.cells, ...filler]);
    }).toList();
  }

  /// Computes the logical column count: the maximum, over all rows, of the
  /// sum of each cell's `colSpan`.
  static int computeColumnCount(List<TableRow> rows) {
    int max = 0;
    for (final row in rows) {
      final total = row.cells.fold<int>(
        0,
        (sum, c) => sum + (c.properties.colSpan < 1 ? 1 : c.properties.colSpan),
      );
      if (total > max) max = total;
    }
    return max;
  }

  /// Returns `true` if [rows] would already satisfy Flutter's [Table]
  /// constraint (every row has the same cell count) without normalization.
  static bool isAlreadyUniform(List<TableRow> rows) {
    if (rows.isEmpty) return true;
    final first = rows.first.cells.length;
    return rows.every((r) => r.cells.length == first);
  }
}
