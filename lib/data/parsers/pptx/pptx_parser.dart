import '../../../core/errors/app_exception.dart';
import '../../../domain/abstractions/document_format.dart';
import '../../../domain/abstractions/document_parser_interface.dart';
import '../../../domain/abstractions/document_source.dart';
import '../../models/document_model.dart';

/// PowerPoint PPTX parser — Phase 5+ stub.
///
/// Like DOCX, PPTX is a ZIP archive. Implementation plan:
///   Parse `ppt/slides/slide*.xml` for slide content.
///   Map slides to a [SlideBlock] block type (Phase 5+).
///   Render slide thumbnails and full-screen slide view.
class PptxParser extends DocumentParserInterface {
  PptxParser();

  @override
  DocumentFormat get format => DocumentFormat.pptx;

  @override
  Future<DocumentModel> parse(DocumentSource source) async {
    throw const ParseException(
      'Định dạng PowerPoint (.pptx) chưa được hỗ trợ.\n'
      'FormulaDoc hiện hỗ trợ: Word (.docx), PDF (.pdf), Excel (.xlsx).',
    );
  }
}
