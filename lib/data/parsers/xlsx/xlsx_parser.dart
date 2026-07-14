import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../../core/errors/app_exception.dart';
import '../../../domain/abstractions/document_format.dart';
import '../../../domain/abstractions/document_parser_interface.dart';
import '../../../domain/abstractions/document_source.dart';
import '../../models/document_block.dart';
import '../../models/document_model.dart';

/// XLSX parser — reads the ZIP+XML format directly using the packages already
/// in the project (archive + xml), avoiding any dependency conflicts.
///
/// Handles:
///   • xl/sharedStrings.xml  — string table (inline strings + shared strings)
///   • xl/workbook.xml       — sheet names and order
///   • xl/worksheets/sheet*.xml — cell values (strings, numbers, dates, bools)
class XlsxParser extends DocumentParserInterface {
  XlsxParser();

  @override
  DocumentFormat get format => DocumentFormat.xlsx;

  @override
  Future<DocumentModel> parse(DocumentSource source) async {
    Uint8List bytes;
    try {
      bytes = await source.readBytes();
    } catch (e) {
      throw ParseException('Cannot read XLSX file: $e');
    }

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw ParseException('Not a valid XLSX file (ZIP decode failed): $e');
    }

    // ── Read shared strings ──────────────────────────────────────────────────
    final sharedStrings = <String>[];
    final ssFile = archive.findFile('xl/sharedStrings.xml');
    if (ssFile != null) {
      try {
        // XML files inside XLSX are always UTF-8 encoded. String.fromCharCodes
        // would map each raw byte 0..255 directly to a UTF-16 code unit
        // instead of decoding the UTF-8 sequence — that happens to work for
        // plain ASCII text but corrupts anything with Vietnamese diacritics
        // (or any non-ASCII text), producing mojibake like "TÃªn" instead of
        // "Tên". utf8.decode() does the actual UTF-8 → Dart String decoding.
        final doc = XmlDocument.parse(
            utf8.decode(ssFile.content as List<int>));
        for (final si in doc.findAllElements('si')) {
          // concat all <t> text nodes (handles rich-text runs inside a cell)
          sharedStrings.add(
            si.findAllElements('t').map((t) => t.innerText).join(),
          );
        }
      } catch (_) { /* ignore malformed shared strings */ }
    }

    // ── Read sheet order & names from workbook.xml ──────────────────────────
    final sheetOrder = <String, String>{}; // name → relationship id
    final wbFile = archive.findFile('xl/workbook.xml');
    if (wbFile != null) {
      try {
        final doc = XmlDocument.parse(
            utf8.decode(wbFile.content as List<int>));
        for (final sheet in doc.findAllElements('sheet')) {
          final name = sheet.getAttribute('name') ?? '';
          final rId  = sheet.getAttribute('r:id') ?? '';
          if (name.isNotEmpty && rId.isNotEmpty) sheetOrder[rId] = name;
        }
      } catch (_) {}
    }

    // ── Read sheet relationship → file mapping ───────────────────────────────
    final rIdToPath = <String, String>{}; // rId → xl/worksheets/sheetN.xml
    final relsFile = archive.findFile('xl/_rels/workbook.xml.rels');
    if (relsFile != null) {
      try {
        final doc = XmlDocument.parse(
            utf8.decode(relsFile.content as List<int>));
        for (final rel in doc.findAllElements('Relationship')) {
          final id     = rel.getAttribute('Id') ?? '';
          final target = rel.getAttribute('Target') ?? '';
          if (target.toLowerCase().contains('sheet')) rIdToPath[id] = target;
        }
      } catch (_) {}
    }

    // ── Determine sheets to parse, in workbook order ─────────────────────────
    final orderedSheets = <MapEntry<String, String>>[]; // name → file path
    for (final entry in sheetOrder.entries) {
      final path = rIdToPath[entry.key];
      if (path != null) {
        final full = path.startsWith('xl/') ? path : 'xl/$path';
        orderedSheets.add(MapEntry(entry.value, full));
      }
    }
    // Fallback: if workbook.xml wasn't parseable, add all worksheet files
    if (orderedSheets.isEmpty) {
      for (final f in archive.files) {
        if (f.name.startsWith('xl/worksheets/sheet') &&
            f.name.endsWith('.xml')) {
          orderedSheets.add(MapEntry(f.name.split('/').last, f.name));
        }
      }
    }

    if (orderedSheets.isEmpty) {
      throw const ParseException('XLSX file contains no worksheets.');
    }

    // ── Parse each worksheet ─────────────────────────────────────────────────
    final blocks   = <DocumentBlock>[];
    final warnings = <String>[];
    int   idx      = 0;

    for (final sheet in orderedSheets) {
      final name     = sheet.key;
      final filePath = sheet.value;
      final file     = archive.findFile(filePath);
      if (file == null) {
        warnings.add('Sheet "$name": file "$filePath" not found in archive.');
        continue;
      }

      List<List<String?>> rows;
      List<int> rowNumbers;
      try {
        final parsed = _parseWorksheet(file.content as List<int>, sharedStrings);
        rows        = parsed.rows;
        rowNumbers  = parsed.rowNumbers;
      } catch (e) {
        warnings.add('Sheet "$name" parse error: $e');
        continue;
      }

      // Trim trailing empty rows (keep rowNumbers in sync so rows[i] and
      // rowNumbers[i] always refer to the same physical XLSX row).
      while (rows.isNotEmpty && rows.last.every((c) => c == null || c!.isEmpty)) {
        rows.removeLast();
        rowNumbers.removeLast();
      }
      if (rows.isEmpty) {
        warnings.add('Sheet "$name" is empty after trimming.');
        continue;
      }

      final colCount = rows.fold(0, (m, r) => r.length > m ? r.length : m);

      blocks.add(SpreadsheetBlock(
        id:             'sheet_${idx++}',
        sheetName:      name,
        rows:           rows,
        colCount:       colCount,
        sourceFilePath: filePath,
        rowNumbers:     rowNumbers,
      ));
    }

    if (blocks.isEmpty) {
      throw const ParseException('XLSX file has no renderable sheets.');
    }

    return DocumentModel(
      blocks:        blocks,
      metadata:      DocumentMetadata(
        title:    source.name ?? 'Spreadsheet',
        modified: DateTime.now(),
      ),
      images:        const {},
      parseWarnings: warnings,
    );
  }

  // ── Worksheet parser ────────────────────────────────────────────────────────

  _ParsedSheet _parseWorksheet(
      List<int> bytes, List<String> sharedStrings) {
    final doc  = XmlDocument.parse(utf8.decode(bytes));
    final rows = <List<String?>>[];
    final rowNumbers = <int>[];
    int positionalFallback = 0;

    for (final row in doc.findAllElements('row')) {
      final cells = <String?>[];

      for (final c in row.findAllElements('c')) {
        // Cell reference, e.g. "A1", "B3"
        final ref    = c.getAttribute('r') ?? '';
        final colIdx = _colIndex(ref);

        // Fill gaps with null for missing cells
        while (cells.length < colIdx) cells.add(null);

        cells.add(_cellValue(c, sharedStrings));
      }

      rows.add(cells);

      // Row's own `r` attribute is the authoritative 1-based row number.
      // Rows can be sparse (an entirely blank row is often omitted from the
      // XML entirely), so this must NOT be assumed to equal the row's
      // position in our list — using position instead would cause edits to
      // silently land on the wrong physical row when writing back.
      positionalFallback++;
      final rAttr = row.getAttribute('r');
      final rNum  = rAttr != null ? int.tryParse(rAttr) : null;
      rowNumbers.add(rNum ?? positionalFallback);
    }

    return _ParsedSheet(rows, rowNumbers);
  }

  /// Convert column letter(s) from cell ref (e.g. "AB3") to 0-based index.
  int _colIndex(String ref) {
    int col = 0;
    for (final ch in ref.runes) {
      final c = String.fromCharCode(ch);
      if (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) {
        col = col * 26 + (ch - 'A'.codeUnitAt(0) + 1);
      } else {
        break; // hit digits → done
      }
    }
    return col > 0 ? col - 1 : 0;
  }

  /// Extract a human-readable string from a `<c>` element.
  String? _cellValue(XmlElement c, List<String> sharedStrings) {
    final type = c.getAttribute('t') ?? ''; // s=shared, b=bool, e=error, str=formula
    final vEl  = c.findElements('v').firstOrNull;
    final fEl  = c.findElements('f').firstOrNull;
    final isEl = c.findElements('is').firstOrNull; // inline string

    if (isEl != null) {
      return isEl.findAllElements('t').map((t) => t.innerText).join();
    }

    final raw = vEl?.innerText ?? fEl?.innerText;
    if (raw == null || raw.isEmpty) return null;

    return switch (type) {
      's'   => int.tryParse(raw) != null && int.parse(raw) < sharedStrings.length
                    ? sharedStrings[int.parse(raw)]
                    : raw,
      'b'   => raw == '1' ? 'TRUE' : 'FALSE',
      'e'   => raw,  // error string like #REF!
      'str' => raw,  // formula result as string
      _     => _formatNumber(raw),
    };
  }

  /// Format a numeric string — remove unnecessary trailing zeros.
  String _formatNumber(String raw) {
    final d = double.tryParse(raw);
    if (d == null) return raw;
    if (d == d.truncateToDouble()) return d.truncate().toString();
    return d.toStringAsFixed(10)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}

/// Result of parsing one worksheet's XML: cell values plus the real XLSX
/// row number for each row (see [SpreadsheetBlock.rowNumbers] for why this
/// matters for safe write-back).
class _ParsedSheet {
  final List<List<String?>> rows;
  final List<int> rowNumbers;
  const _ParsedSheet(this.rows, this.rowNumbers);
}

