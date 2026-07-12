import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/constants/theme_constants.dart';
import '../../../data/models/document_block.dart'
    hide TableRow, TableCell;
import '../../../data/models/document_model.dart';
import '../../../data/serializers/xlsx_serializer.dart';

/// MVP Excel cell editor. Tap a cell to edit its text value; edits are
/// tracked in memory and written back to the file only when the user taps
/// Lưu (Save). See [XlsxSerializer] for the safety design of the write-back.
class XlsxEditorScreen extends StatefulWidget {
  final DocumentModel model;
  final String        filePath;
  final String        fileName;

  const XlsxEditorScreen({
    super.key,
    required this.model,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<XlsxEditorScreen> createState() => _XlsxEditorScreenState();
}

class _XlsxEditorScreenState extends State<XlsxEditorScreen> {
  late List<SpreadsheetBlock> _sheets;
  int _activeSheet = 0;

  /// Pending edits, keyed by "sheetFilePath:rowNumber:colIndex".
  final Map<String, String?> _pending = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _sheets = widget.model.blocks.whereType<SpreadsheetBlock>().toList();
  }

  String _key(String sheetPath, int row, int col) => '$sheetPath:$row:$col';

  String? _valueAt(SpreadsheetBlock sheet, int rowIdx, int colIdx) {
    final k = sheet.sourceFilePath == null
        ? null
        : _key(sheet.sourceFilePath!,
            rowIdx < sheet.rowNumbers.length ? sheet.rowNumbers[rowIdx] : rowIdx + 1,
            colIdx);
    if (k != null && _pending.containsKey(k)) return _pending[k];
    final row = sheet.rows[rowIdx];
    return colIdx < row.length ? row[colIdx] : null;
  }

  Future<void> _editCell(SpreadsheetBlock sheet, int rowIdx, int colIdx) async {
    if (sheet.sourceFilePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Không xác định được vị trí sheet để lưu — không thể sửa ô này'),
      ));
      return;
    }
    final current = _valueAt(sheet, rowIdx, colIdx) ?? '';
    final ctrl = TextEditingController(text: current);

    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Sửa ô ${_cellRefLabel(rowIdx, colIdx, sheet)}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result == null) return;

    final rowNum = rowIdx < sheet.rowNumbers.length
        ? sheet.rowNumbers[rowIdx] : rowIdx + 1;
    setState(() {
      _pending[_key(sheet.sourceFilePath!, rowNum, colIdx)] =
          result.isEmpty ? null : result;
    });
  }

  String _cellRefLabel(int rowIdx, int colIdx, SpreadsheetBlock sheet) {
    var i = colIdx;
    var s = '';
    do { s = String.fromCharCode(65 + (i % 26)) + s; i = (i ~/ 26) - 1; } while (i >= 0);
    final rowNum = rowIdx < sheet.rowNumbers.length ? sheet.rowNumbers[rowIdx] : rowIdx + 1;
    return '$s$rowNum';
  }

  Future<void> _save() async {
    if (_pending.isEmpty) return;
    setState(() => _saving = true);
    try {
      final edits = <XlsxCellEdit>[];
      for (final entry in _pending.entries) {
        final parts = entry.key.split(':');
        edits.add(XlsxCellEdit(
          sheetFilePath: parts[0],
          rowNumber:     int.parse(parts[1]),
          colIndex:      int.parse(parts[2]),
          value:         entry.value,
        ));
      }

      final originalBytes = await File(widget.filePath).readAsBytes();
      final newBytes = await XlsxSerializer().applyEdits(
        originalBytes: originalBytes,
        edits: edits,
      );
      await File(widget.filePath).writeAsBytes(newBytes);

      if (!mounted) return;
      setState(() => _pending.clear());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Đã lưu thay đổi'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Lỗi khi lưu: $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (_pending.isEmpty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Thoát mà không lưu?'),
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
    if (_sheets.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.fileName)),
        body: const Center(child: Text('Không có sheet nào để chỉnh sửa')),
      );
    }
    final sheet = _sheets[_activeSheet];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: ThemeConstants.paperLight,
        appBar: AppBar(
          title: Text(widget.fileName, overflow: TextOverflow.ellipsis),
          // A plain chip row instead of TabBar: TabBar requires a
          // TabController (either explicit or via an ancestor
          // DefaultTabController), which this screen doesn't set up since
          // sheet switching is just plain int state (_activeSheet), not an
          // animated TabBarView. Using TabBar here without a controller
          // would throw at runtime ("No TabController for TabBar").
          bottom: _sheets.length > 1
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(44),
                  child: Container(
                    height: 44,
                    alignment: Alignment.centerLeft,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        for (int i = 0; i < _sheets.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            child: ChoiceChip(
                              label: Text(_sheets[i].sheetName),
                              selected: _activeSheet == i,
                              onSelected: (_) => setState(() => _activeSheet = i),
                              selectedColor: Colors.white,
                              labelStyle: TextStyle(
                                color: _activeSheet == i
                                    ? const Color(0xFF1565C0)
                                    : Colors.white,
                                fontWeight: _activeSheet == i ? FontWeight.w700 : FontWeight.normal,
                              ),
                              backgroundColor: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                      ],
                    ),
                  ),
                )
              : null,
          actions: [
            if (_pending.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Center(child: Text('${_pending.length} ô đã sửa',
                    style: const TextStyle(fontSize: 12, color: Colors.white70))),
              ),
            TextButton.icon(
              onPressed: _pending.isEmpty || _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined, color: Colors.white),
              label: const Text('Lưu', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 110.0 * sheet.colCount,
            child: ListView.builder(
              itemCount: sheet.rows.length,
              itemBuilder: (context, rowIdx) {
                final isHeader = rowIdx == 0;
                return Row(
                  children: List.generate(sheet.colCount, (colIdx) {
                    final value = _valueAt(sheet, rowIdx, colIdx) ?? '';
                    final edited = sheet.sourceFilePath != null &&
                        _pending.containsKey(_key(
                          sheet.sourceFilePath!,
                          rowIdx < sheet.rowNumbers.length ? sheet.rowNumbers[rowIdx] : rowIdx + 1,
                          colIdx,
                        ));
                    return InkWell(
                      onTap: () => _editCell(sheet, rowIdx, colIdx),
                      child: Container(
                        width: 110, height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: edited
                              ? Colors.amber.withValues(alpha: 0.25)
                              : (isHeader ? const Color(0xFF1565C0) : Colors.white),
                          border: Border.all(color: const Color(0xFFCFD8DC), width: 0.5),
                        ),
                        child: Text(value,
                            style: TextStyle(
                              fontSize: 12,
                              color: isHeader ? Colors.white : Colors.black87,
                              fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
