import 'package:file_picker/file_picker.dart';

import '../core/errors/app_exception.dart';
import '../core/utils/file_utils.dart';
import '../core/utils/logger.dart';
import '../data/parsers/parser_registry.dart';
import '../domain/abstractions/document_source.dart';

/// Handles user-initiated file selection via the system file picker.
class FileService {
  const FileService();

  /// Opens the system file picker for all supported document types.
  ///
  /// Returns a [DocumentSource] for the selected file, or `null` if cancelled.
  Future<DocumentSource?> pickDocument() async {
    // Phase 5: list all registered extensions (docx, pdf, pptx, xlsx…)
    final extensions = DocumentParserRegistry.instance.supportedExtensions;

    try {
      final result = await FilePicker.platform.pickFiles(
        type:               FileType.custom,
        allowedExtensions:  extensions,
        allowMultiple:      false,
        withData:           false,
        withReadStream:     false,
      );

      if (result == null || result.files.isEmpty) {
        AppLogger.debug('File picker cancelled', tag: 'FileService');
        return null;
      }

      final file = result.files.first;
      final path = file.path;

      if (path == null) {
        final bytes = file.bytes;
        if (bytes == null) {
          throw const PlatformException('File picker returned no path or bytes');
        }
        return BytesDocumentSource(bytes: bytes, name: file.name);
      }

      AppLogger.info('Picked file: $path', tag: 'FileService');
      return FileDocumentSource(path);
    } on PlatformException {
      rethrow;
    } catch (e) {
      throw PlatformException('Failed to open file picker', cause: e);
    }
  }

  /// Creates a [DocumentSource] from an intent-delivered file path.
  DocumentSource sourceFromPath(String path) {
    final sanitized = FileUtils.sanitizePath(path);
    AppLogger.info('Source from path: $sanitized', tag: 'FileService');
    return FileDocumentSource(sanitized);
  }
}
