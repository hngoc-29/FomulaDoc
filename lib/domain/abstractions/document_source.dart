import 'dart:io';
import 'dart:typed_data';
import 'document_format.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ABSTRACT SOURCE
// ═══════════════════════════════════════════════════════════════════════════════

/// Abstraction over where document bytes come from.
///
/// Implementations:
///   [FileDocumentSource]    — local file path (file picker, "Open with")
///   [BytesDocumentSource]   — raw bytes (cloud download, test fixtures)
///
/// Future additions: [CloudDocumentSource], [NetworkDocumentSource].
abstract class DocumentSource {
  /// Human-readable document name (usually the file name with extension).
  String get name;

  /// Absolute local path, or null if this source has no file backing.
  String? get path;

  /// Detected document format derived from the name / extension.
  DocumentFormat? get format;

  /// Reads and returns the full document bytes.
  ///
  /// May be called multiple times; implementations must be idempotent.
  Future<Uint8List> readBytes();
}

// ═══════════════════════════════════════════════════════════════════════════════
// FILE SOURCE
// ═══════════════════════════════════════════════════════════════════════════════

/// Document source backed by a file on the device.
class FileDocumentSource extends DocumentSource {
  final String filePath;

  FileDocumentSource(String rawPath) : filePath = _sanitize(rawPath);

  @override
  String get name {
    final parts = filePath.replaceAll('\\', '/').split('/');
    return parts.last;
  }

  @override
  String? get path => filePath;

  @override
  DocumentFormat? get format {
    final ext = name.contains('.') ? name.split('.').last : '';
    return DocumentFormatX.fromExtension(ext);
  }

  @override
  Future<Uint8List> readBytes() async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', filePath);
    }
    return file.readAsBytes();
  }

  static String _sanitize(String raw) {
    if (raw.startsWith('file://')) return Uri.parse(raw).toFilePath();
    return raw;
  }

  @override
  String toString() => 'FileDocumentSource($filePath)';
}

// ═══════════════════════════════════════════════════════════════════════════════
// BYTES SOURCE
// ═══════════════════════════════════════════════════════════════════════════════

/// Document source backed by raw in-memory bytes.
///
/// Used for: test fixtures, cloud downloads, attachment previews.
class BytesDocumentSource extends DocumentSource {
  final Uint8List _bytes;

  @override
  final String name;

  @override
  final String? path;

  @override
  final DocumentFormat? format;

  BytesDocumentSource({
    required Uint8List bytes,
    required this.name,
    this.path,
    this.format,
  }) : _bytes = bytes;

  @override
  Future<Uint8List> readBytes() async => _bytes;

  @override
  String toString() => 'BytesDocumentSource($name, ${_bytes.length} bytes)';
}
