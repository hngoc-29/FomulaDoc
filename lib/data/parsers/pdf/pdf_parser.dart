import 'dart:typed_data';

import 'package:pdfx/pdfx.dart';

import '../../../core/errors/app_exception.dart';
import '../../../domain/abstractions/document_format.dart';
import '../../../domain/abstractions/document_parser_interface.dart';
import '../../../domain/abstractions/document_source.dart';
import '../../models/document_block.dart';
import '../../models/document_model.dart';

/// PDF parser — uses the platform's native PDF renderer via pdfx.
class PdfParser extends DocumentParserInterface {
  PdfParser();

  @override
  DocumentFormat get format => DocumentFormat.pdf;

  @override
  Future<DocumentModel> parse(DocumentSource source) async {
    Uint8List bytes;
    try {
      bytes = await source.readBytes();
    } catch (e) {
      throw ParseException('Cannot read PDF file: $e');
    }

    // Validate it's actually a PDF (%PDF- magic bytes)
    if (bytes.length < 5 ||
        bytes[0] != 0x25 || // %
        bytes[1] != 0x50 || // P
        bytes[2] != 0x44 || // D
        bytes[3] != 0x46 || // F
        bytes[4] != 0x2D) { // -
      throw const ParseException('File is not a valid PDF.');
    }

    // Open briefly to get page count and title
    int pageCount = 1;
    String? title;
    try {
      final doc = await PdfDocument.openData(bytes);
      pageCount = doc.pagesCount;
      title     = source.name;
      await doc.close();
    } catch (e) {
      throw ParseException('Cannot open PDF: $e');
    }

    return DocumentModel(
      blocks: [
        PdfDocumentBlock(
          id:        'pdf_doc',
          bytes:     bytes,
          pageCount: pageCount,
        ),
      ],
      metadata: DocumentMetadata(
        title:    title ?? 'PDF Document',
        modified: DateTime.now(),
      ),
      images:        const {},
      parseWarnings: const [],
    );
  }
}

