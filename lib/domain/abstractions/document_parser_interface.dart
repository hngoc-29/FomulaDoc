import '../../data/models/document_model.dart';
import 'document_format.dart';
import 'document_source.dart';

/// Contract every document parser must fulfil.
///
/// The [DocxParser] implements this for Phase 1.
/// Future parsers ([PdfParser], [PptxParser]) implement it for later phases.
///
/// Usage:
/// ```dart
/// final parser = DocxParser();
/// final model  = await parser.parse(FileDocumentSource('/path/to/file.docx'));
/// ```
abstract class DocumentParserInterface {
  /// The format this parser handles.
  DocumentFormat get format;

  /// Parses [source] into a format-agnostic [DocumentModel].
  ///
  /// Heavy work (ZIP extraction, XML parsing) is offloaded to an isolate.
  /// Never throws synchronously; wraps errors in [ParseException] or rethrows.
  Future<DocumentModel> parse(DocumentSource source);

  /// Returns `true` when [source] appears to be a file this parser can handle.
  bool canParse(DocumentSource source) =>
      source.format == format || (source.name.isNotEmpty &&
      format.extensions.any(
        (ext) => source.name.toLowerCase().endsWith('.$ext'),
      ));
}
