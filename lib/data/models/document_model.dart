import 'dart:typed_data';
import 'document_block.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// METADATA
// ═══════════════════════════════════════════════════════════════════════════════

/// Document-level metadata parsed from `docProps/core.xml`.
class DocumentMetadata {
  final String? title;
  final String? author;
  final String? subject;
  final String? description;
  final DateTime? created;
  final DateTime? modified;

  const DocumentMetadata({
    this.title,
    this.author,
    this.subject,
    this.description,
    this.created,
    this.modified,
  });

  static const DocumentMetadata empty = DocumentMetadata();

  @override
  String toString() => 'DocumentMetadata(title: $title, author: $author)';
}

// ═══════════════════════════════════════════════════════════════════════════════
// DOCUMENT MODEL
// ═══════════════════════════════════════════════════════════════════════════════

/// The complete, format-agnostic representation of an opened document.
///
/// Every parser ([DocxParser], future [PdfParser], etc.) produces a
/// [DocumentModel]. Every renderer consumes a [DocumentModel].
///
/// This decoupling is the key architectural invariant:
///   Parser → DocumentModel → Renderer
///
/// The model is pure Dart (no Flutter imports) so it can be built inside
/// a `compute()` isolate without restrictions.
class DocumentModel {
  /// Ordered list of all content blocks.
  final List<DocumentBlock> blocks;

  /// Document-level metadata.
  final DocumentMetadata metadata;

  /// Raw image bytes keyed by relationship ID (e.g. `"rId3"`).
  /// Populated by the parser from `word/media/` entries.
  final Map<String, Uint8List> images;

  /// Non-fatal warnings accumulated during parsing.
  /// Useful for debugging documents that partially fail.
  final List<String> parseWarnings;

  const DocumentModel({
    required this.blocks,
    this.metadata = DocumentMetadata.empty,
    this.images = const {},
    this.parseWarnings = const [],
  });

  DocumentModel copyWith({
    List<DocumentBlock>? blocks,
    DocumentMetadata? metadata,
    Map<String, Uint8List>? images,
    List<String>? parseWarnings,
  }) {
    return DocumentModel(
      blocks: blocks ?? this.blocks,
      metadata: metadata ?? this.metadata,
      images: images ?? this.images,
      parseWarnings: parseWarnings ?? this.parseWarnings,
    );
  }

  // ── Computed properties ──────────────────────────────────────────────────

  int get blockCount => blocks.length;

  bool get isEmpty => blocks.isEmpty;

  bool get hasWarnings => parseWarnings.isNotEmpty;

  /// Number of equation blocks — quick quality metric.
  int get equationCount =>
      blocks.whereType<EquationBlock>().length;

  /// Flat list of all image blocks.
  List<ImageBlock> get imageBlocks =>
      blocks.whereType<ImageBlock>().toList();

  @override
  String toString() =>
      'DocumentModel(blocks: ${blocks.length}, '
      'images: ${images.length}, '
      'equations: $equationCount, '
      'warnings: ${parseWarnings.length})';
}
