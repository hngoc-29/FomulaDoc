import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../../core/utils/logger.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// EXTRACTED DOCX CONTAINER
// ═══════════════════════════════════════════════════════════════════════════════

/// All raw XML/binary content extracted from a DOCX ZIP archive.
///
/// This is an intermediate representation between raw bytes and the parsed
/// [DocumentModel]. It is pure Dart and isolate-safe.
class ExtractedDocx {
  /// Contents of `word/document.xml` — the main body of the document.
  final String documentXml;

  /// Contents of `word/styles.xml` — paragraph and character style definitions.
  final String? stylesXml;

  /// Contents of `word/_rels/document.xml.rels` — relationship map.
  final String? relationshipsXml;

  /// Contents of `word/numbering.xml` — list / numbering definitions.
  final String? numberingXml;

  /// Contents of `docProps/core.xml` — document metadata (author, title, …).
  final String? corePropsXml;

  /// Binary content of all `word/media/*` files, keyed by their ZIP entry name
  /// (e.g. `"word/media/image1.png"` → raw PNG bytes).
  final Map<String, Uint8List> mediaFiles;

  const ExtractedDocx({
    required this.documentXml,
    this.stylesXml,
    this.relationshipsXml,
    this.numberingXml,
    this.corePropsXml,
    this.mediaFiles = const {},
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXTRACTOR
// ═══════════════════════════════════════════════════════════════════════════════

/// Extracts raw content from the DOCX ZIP archive.
///
/// Runs synchronously; call from within a `compute()` isolate via [DocxParser].
class DocxExtractor {
  static const String _docEntry = 'word/document.xml';
  static const String _stylesEntry = 'word/styles.xml';
  static const String _relsEntry = 'word/_rels/document.xml.rels';
  static const String _numberingEntry = 'word/numbering.xml';
  static const String _corePropsEntry = 'docProps/core.xml';
  static const String _mediaPrefix = 'word/media/';

  /// Extracts a [DOCX] archive from [bytes].
  ///
  /// Throws [FormatException] if the mandatory `word/document.xml` is missing.
  ExtractedDocx extract(Uint8List bytes) {
    late final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw FormatException('Cannot decode ZIP archive: $e');
    }

    // ── Mandatory entry ──────────────────────────────────────────────────────
    final docEntry = _findFile(archive, _docEntry);
    if (docEntry == null) {
      throw const FormatException(
        'Not a valid DOCX file: missing word/document.xml',
      );
    }
    final documentXml = _readString(docEntry);

    // ── Optional entries ─────────────────────────────────────────────────────
    final stylesXml = _readStringOptional(archive, _stylesEntry);
    final relsXml = _readStringOptional(archive, _relsEntry);
    final numberingXml = _readStringOptional(archive, _numberingEntry);
    final corePropsXml = _readStringOptional(archive, _corePropsEntry);

    // ── Media files ──────────────────────────────────────────────────────────
    final mediaFiles = <String, Uint8List>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (!file.name.startsWith(_mediaPrefix)) continue;
      try {
        mediaFiles[file.name] = _readBytes(file);
      } catch (e) {
        AppLogger.warning(
          'Skipping unreadable media file "${file.name}": $e',
          tag: 'DocxExtractor',
        );
      }
    }

    AppLogger.debug(
      'Extracted DOCX: '
      'doc=${documentXml.length}ch, '
      'styles=${stylesXml?.length ?? 0}ch, '
      'media=${mediaFiles.length} files',
      tag: 'DocxExtractor',
    );

    return ExtractedDocx(
      documentXml: documentXml,
      stylesXml: stylesXml,
      relationshipsXml: relsXml,
      numberingXml: numberingXml,
      corePropsXml: corePropsXml,
      mediaFiles: mediaFiles,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  ArchiveFile? _findFile(Archive archive, String name) {
    for (final file in archive.files) {
      if (file.name == name) return file;
    }
    // Some tools use backslashes on Windows-generated DOCXs
    final normalized = name.replaceAll('/', '\\');
    for (final file in archive.files) {
      if (file.name == normalized) return file;
    }
    return null;
  }

  String _readString(ArchiveFile file) {
    final bytes = _readBytes(file);
    // Strip UTF-8 BOM if present
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  String? _readStringOptional(Archive archive, String path) {
    try {
      final file = _findFile(archive, path);
      if (file == null) return null;
      return _readString(file);
    } catch (e) {
      AppLogger.warning(
        'Failed to read optional entry "$path": $e',
        tag: 'DocxExtractor',
      );
      return null;
    }
  }

  Uint8List _readBytes(ArchiveFile file) {
    final content = file.content;
    if (content is Uint8List) return content;
    if (content is List<int>) return Uint8List.fromList(content);
    throw FormatException(
      'Unexpected content type for "${file.name}": ${content.runtimeType}',
    );
  }
}
