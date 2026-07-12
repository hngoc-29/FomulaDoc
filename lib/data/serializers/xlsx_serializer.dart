import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:xml/xml.dart';

/// A single pending cell edit: a specific sheet file + row + column + new
/// text value (null = clear the cell).
class XlsxCellEdit {
  final String sheetFilePath; // e.g. 'xl/worksheets/sheet1.xml'
  final int    rowNumber;     // 1-based, actual XLSX row number
  final int    colIndex;      // 0-based (A=0, B=1, …)
  final String? value;

  const XlsxCellEdit({
    required this.sheetFilePath,
    required this.rowNumber,
    required this.colIndex,
    required this.value,
  });
}

/// Writes a batch of cell edits back into the original XLSX bytes.
///
/// SAFETY DESIGN — this deliberately avoids the riskiest parts of XLSX
/// mutation:
///   • Only the specific `xl/worksheets/sheetN.xml` files that actually
///     have edits are touched; every other file in the archive (styles,
///     other sheets, shared strings, workbook.xml, …) is copied through
///     byte-for-byte unchanged.
///   • Edited cells are always written as inline strings
///     (`t="inlineStr"`, `<is><t>…</t></is>`), never by mutating the
///     shared-strings table. Shared strings can be referenced by many
///     unrelated cells across the workbook; editing a shared string in
///     place would silently change the text of every other cell that
///     happens to reference the same index. Inline strings sidestep that
///     class of bug entirely, at the cost of numeric values losing their
///     native numeric type (they become text-flavored cells) — a
///     deliberate, documented trade-off for a first-pass, corruption-safe
///     implementation. Formulas elsewhere in the workbook that reference
///     an edited cell may not recompute correctly as a result.
class XlsxSerializer {
  /// Apply [edits] to [originalBytes] and return the new XLSX bytes.
  /// Throws if the ZIP can't be decoded or a target sheet file is missing.
  Future<Uint8List> applyEdits({
    required Uint8List originalBytes,
    required List<XlsxCellEdit> edits,
  }) async {
    if (edits.isEmpty) return originalBytes;

    final archive = ZipDecoder().decodeBytes(originalBytes);

    // Group edits by sheet file so we parse/re-serialize each sheet XML
    // exactly once, even if it has multiple edited cells.
    final bySheet = <String, List<XlsxCellEdit>>{};
    for (final e in edits) {
      bySheet.putIfAbsent(e.sheetFilePath, () => []).add(e);
    }

    final newArchive = Archive();
    for (final file in archive.files) {
      final sheetEdits = bySheet[file.name];
      if (!file.isFile || sheetEdits == null) {
        // Unrelated file — copy through untouched.
        newArchive.addFile(file);
        continue;
      }

      final patchedXml = _applyEditsToSheetXml(
        String.fromCharCodes(file.content as List<int>),
        sheetEdits,
      );
      final bytes = Uint8List.fromList(patchedXml.codeUnits);
      newArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
    }

    final encoded = ZipEncoder().encode(newArchive);
    if (encoded == null) {
      throw Exception('Không thể đóng gói lại file XLSX');
    }
    return Uint8List.fromList(encoded);
  }

  // ── Sheet XML patching ─────────────────────────────────────────────────────

  String _applyEditsToSheetXml(String xmlSource, List<XlsxCellEdit> edits) {
    final doc = XmlDocument.parse(xmlSource);
    final sheetData = doc.findAllElements('sheetData').firstOrNull;
    if (sheetData == null) {
      throw Exception('Sheet XML missing <sheetData>');
    }

    // Group edits by row so we find/create each <row> only once.
    final byRow = <int, List<XlsxCellEdit>>{};
    for (final e in edits) {
      byRow.putIfAbsent(e.rowNumber, () => []).add(e);
    }

    for (final entry in byRow.entries) {
      final rowNum   = entry.key;
      final rowEdits = entry.value;
      final rowEl    = _findOrCreateRow(sheetData, rowNum);
      for (final e in rowEdits) {
        _setCell(rowEl, rowNum, e.colIndex, e.value);
      }
    }

    return doc.toXmlString();
  }

  /// Find `<row r="rowNum">` or create + insert it in ascending row order.
  XmlElement _findOrCreateRow(XmlElement sheetData, int rowNum) {
    final rows = sheetData.findElements('row').toList();
    for (final r in rows) {
      final rAttr = int.tryParse(r.getAttribute('r') ?? '');
      if (rAttr == rowNum) return r;
    }

    final newRow = XmlElement(XmlName('row'), [
      XmlAttribute(XmlName('r'), '$rowNum'),
    ]);

    // Insert in ascending row-number order so downstream tools that expect
    // sorted rows (Excel itself is lenient, but some libraries aren't) keep
    // working correctly.
    XmlElement? insertBefore;
    for (final r in rows) {
      final rAttr = int.tryParse(r.getAttribute('r') ?? '');
      if (rAttr != null && rAttr > rowNum) { insertBefore = r; break; }
    }
    if (insertBefore != null) {
      insertBefore.parent!.children.insert(
        insertBefore.parent!.children.indexOf(insertBefore),
        newRow,
      );
    } else {
      sheetData.children.add(newRow);
    }
    return newRow;
  }

  /// Set `<c r="{colLetter}{rowNum}">` to an inline-string value (or remove
  /// the cell's content entirely if [value] is null/empty).
  void _setCell(XmlElement rowEl, int rowNum, int colIndex, String? value) {
    final ref = '${_colLetter(colIndex)}$rowNum';
    final cells = rowEl.findElements('c').toList();

    XmlElement? target;
    for (final c in cells) {
      if (c.getAttribute('r') == ref) { target = c; break; }
    }

    if (target == null) {
      target = XmlElement(XmlName('c'), [XmlAttribute(XmlName('r'), ref)]);
      XmlElement? insertBefore;
      for (final c in cells) {
        final cCol = _colIndexOfRef(c.getAttribute('r') ?? '');
        if (cCol > colIndex) { insertBefore = c; break; }
      }
      if (insertBefore != null) {
        insertBefore.parent!.children.insert(
          insertBefore.parent!.children.indexOf(insertBefore),
          target,
        );
      } else {
        rowEl.children.add(target);
      }
    }

    // Clear existing attributes/children, then set as inline string.
    target.attributes.removeWhere((a) => a.name.local == 't');
    target.children.clear();

    if (value == null || value.isEmpty) return; // empty cell — leave bare <c r="..">

    target.attributes.add(XmlAttribute(XmlName('t'), 'inlineStr'));
    final isEl = XmlElement(XmlName('is'));
    final tEl  = XmlElement(XmlName('t'), [], [XmlText(value)]);
    isEl.children.add(tEl);
    target.children.add(isEl);
  }

  String _colLetter(int index) {
    var i = index;
    var s = '';
    do {
      s = String.fromCharCode(65 + (i % 26)) + s;
      i = (i ~/ 26) - 1;
    } while (i >= 0);
    return s;
  }

  int _colIndexOfRef(String ref) {
    int col = 0;
    for (final ch in ref.runes) {
      final c = String.fromCharCode(ch);
      if (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) {
        col = col * 26 + (ch - 'A'.codeUnitAt(0) + 1);
      } else {
        break;
      }
    }
    return col > 0 ? col - 1 : 0;
  }
}
