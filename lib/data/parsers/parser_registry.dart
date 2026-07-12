import '../../core/errors/app_exception.dart';
import '../../core/utils/logger.dart';
import '../../domain/abstractions/document_format.dart';
import '../../domain/abstractions/document_parser_interface.dart';
import '../../domain/abstractions/document_source.dart';
import '../models/document_model.dart';
import './docx/docx_parser.dart';
import 'pdf/pdf_parser.dart';
import 'pptx/pptx_parser.dart';
import 'xlsx/xlsx_parser.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DOCUMENT PARSER REGISTRY
// ═══════════════════════════════════════════════════════════════════════════════

/// Central registry mapping [DocumentFormat] → [DocumentParserInterface].
///
/// **Plug-and-play architecture**: adding a new format requires:
///   1. Implement [DocumentParserInterface] with `format` returning the new enum.
///   2. Call `DocumentParserRegistry.instance.register(MyNewParser())`.
///   3. Nothing else changes — [DocumentNotifier] automatically picks it up.
///
/// Parsers are registered at app startup via [DocumentParserRegistry.registerDefaults].
class DocumentParserRegistry {
  DocumentParserRegistry._();

  static final DocumentParserRegistry instance = DocumentParserRegistry._();

  final Map<DocumentFormat, DocumentParserInterface> _parsers = {};

  // ── Registration ──────────────────────────────────────────────────────────

  /// Registers [parser], overwriting any existing entry for the same format.
  void register(DocumentParserInterface parser) {
    _parsers[parser.format] = parser;
    AppLogger.info(
      'Registered parser: ${parser.format.displayName}',
      tag: 'ParserRegistry',
    );
  }

  /// Registers all built-in parsers. Called once in [main].
  void registerDefaults() {
    register(DocxParser());  // ✅ Phase 1-3: fully implemented
    register(PdfParser());   // 🔜 Phase 5+: stub
    register(PptxParser());  // 🔜 Phase 5+: stub
    register(XlsxParser());  // 🔜 Phase 5+: stub

    AppLogger.info(
      'Parser registry ready: ${_parsers.length} formats registered',
      tag: 'ParserRegistry',
    );
  }

  // ── Lookup ────────────────────────────────────────────────────────────────

  /// Returns the parser for [format], or `null` if not registered.
  DocumentParserInterface? forFormat(DocumentFormat format) => _parsers[format];

  /// Detects the format from [source] and returns its parser.
  DocumentParserInterface? forSource(DocumentSource source) {
    // 1. Explicit format set on the source
    if (source.format != null) return forFormat(source.format!);

    // 2. Detect from file extension
    final dot = source.name.lastIndexOf('.');
    if (dot != -1) {
      final ext = source.name.substring(dot + 1).toLowerCase();
      final fmt = DocumentFormatX.fromExtension(ext);
      if (fmt != null) return forFormat(fmt);
    }
    return null;
  }

  // ── Parse ─────────────────────────────────────────────────────────────────

  /// Resolves the correct parser for [source] and runs it.
  ///
  /// Throws [UnsupportedFormatException] if no parser is registered.
  Future<DocumentModel> parse(DocumentSource source) {
    final parser = forSource(source);
    if (parser == null) {
      final ext = source.name.contains('.')
          ? source.name.split('.').last
          : 'unknown';
      throw UnsupportedFormatException(ext);
    }
    return parser.parse(source);
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  /// All file extensions (without dot) that have a registered parser.
  List<String> get supportedExtensions => _parsers.values
      .expand((p) => p.format.extensions)
      .toList();

  /// Formats that are fully implemented and ready for use.
  List<DocumentFormat> get supportedFormats =>
      _parsers.keys.where((f) => f.isSupported).toList();

  /// Formats registered but not yet fully implemented.
  List<DocumentFormat> get plannedFormats =>
      _parsers.keys.where((f) => !f.isSupported).toList();

  int get registeredCount => _parsers.length;
}
