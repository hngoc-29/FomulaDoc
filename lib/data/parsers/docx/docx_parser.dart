import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/logger.dart';
import '../../../domain/abstractions/document_format.dart';
import '../../../domain/abstractions/document_parser_interface.dart';
import '../../../domain/abstractions/document_source.dart';
import '../../models/document_model.dart';
import '../../../platform/wmf_render_service.dart';
import 'docx_extractor.dart';
import 'numbering_parser.dart';
import 'xml_body_parser.dart';

// ─── Isolate payload ──────────────────────────────────────────────────────────

class _DocxParsePayload {
  final Uint8List bytes;
  const _DocxParsePayload(this.bytes);
}

// ─── Top-level isolate function ───────────────────────────────────────────────

/// Must be top-level for `compute()` to spawn it in a separate Dart isolate.
DocumentModel _parseDocxInIsolate(_DocxParsePayload payload) {
  // Step 1: Extract ZIP
  final extractor = DocxExtractor();
  final extracted = extractor.extract(payload.bytes);

  // Step 2: Build numbering resolver (Phase 2)
  final numbering = NumberingParser(extracted.numberingXml);

  // Step 3: Parse XML body into DocumentModel
  final bodyParser = XmlBodyParser(extracted, numberingParser: numbering);
  return bodyParser.parse();
}

// ═══════════════════════════════════════════════════════════════════════════════
// DOCX PARSER
// ═══════════════════════════════════════════════════════════════════════════════

/// Parses Microsoft Word DOCX files into a [DocumentModel].
///
/// Offloads all CPU-heavy work (ZIP extraction + XML parsing) to a background
/// isolate via [compute], keeping the UI thread free during large document loads.
class DocxParser extends DocumentParserInterface {
  DocxParser();

  @override
  DocumentFormat get format => DocumentFormat.docx;

  @override
  Future<DocumentModel> parse(DocumentSource source) async {
    AppLogger.info('Parsing DOCX: ${source.name}', tag: 'DocxParser');

    // Read bytes (may involve I/O)
    final Uint8List bytes;
    try {
      bytes = await source.readBytes();
    } catch (e) {
      throw ParseException(
        'Failed to read document bytes from ${source.name}',
        cause: e,
        source: source.path,
      );
    }

    if (bytes.isEmpty) {
      throw ParseException(
        'Document file is empty: ${source.name}',
        source: source.path,
      );
    }

    AppLogger.debug(
      'Read ${bytes.length} bytes — offloading to isolate',
      tag: 'DocxParser',
    );

    // Parse in background isolate
    try {
      DocumentModel model = await compute(
          _parseDocxInIsolate, _DocxParsePayload(bytes));

      // ── Post-process: render WMF images via native Android channel ─────────
      // compute() runs in a background Dart isolate where MethodChannels are
      // unavailable. Back on the main isolate here, we convert any raw WMF
      // bytes (magic 0xD7 0xCD 0xC6 0x9A) to PNG so Image.memory() can render
      // them directly — no more grey placeholder boxes for equations.
      model = await _renderWmfImages(model);

      AppLogger.info(
        'Parse complete: ${model.blockCount} blocks, '
        '${model.equationCount} equations, '
        '${model.images.length} images, '
        '${model.parseWarnings.length} warnings',
        tag: 'DocxParser',
      );

      return model;
    } on FormatException catch (e) {
      throw ParseException(
        'Invalid DOCX format: ${e.message}',
        cause: e,
        source: source.path,
      );
    } catch (e) {
      throw ParseException(
        'Unexpected error parsing ${source.name}',
        cause: e,
        source: source.path,
      );
    }
  }

  // ─── WMF post-processing ─────────────────────────────────────────────────

  static const _wmfMagic = [0xD7, 0xCD, 0xC6, 0x9A]; // placeable WMF magic LE

  static bool _isWmf(Uint8List bytes) =>
      bytes.length > 4 &&
      bytes[0] == _wmfMagic[0] &&
      bytes[1] == _wmfMagic[1] &&
      bytes[2] == _wmfMagic[2] &&
      bytes[3] == _wmfMagic[3];

  Future<DocumentModel> _renderWmfImages(DocumentModel model) async {
    final wmfEntries =
        model.images.entries.where((e) => _isWmf(e.value)).toList();
    if (wmfEntries.isEmpty) return model;

    AppLogger.info(
      'Rendering ${wmfEntries.length} WMF equation image(s) via native channel',
      tag: 'DocxParser',
    );

    final service = WmfRenderService();
    final updated = Map<String, Uint8List>.from(model.images);

    for (final entry in wmfEntries) {
      try {
        final png = await service.renderToPng(entry.value);
        if (png != null) {
          updated[entry.key] = png;
          AppLogger.debug(
              'WMF ${entry.key} → PNG ${png.length}B', tag: 'DocxParser');
        }
      } catch (e) {
        AppLogger.warning(
            'WMF render failed for ${entry.key}: $e', tag: 'DocxParser');
      }
    }

    return model.copyWith(images: updated);
  }
}
