/// Application-wide constants.
///
/// Single source of truth for magic numbers, keys, and configuration values.
class AppConstants {
  AppConstants._();

  // ── App Info ──────────────────────────────────────────────────────────────
  static const String appName = 'FormulaDoc';
  static const String appVersion = '1.0.0';

  // ── Supported Formats ─────────────────────────────────────────────────────
  /// File extensions the app can open (Phase 1: DOCX only).
  static const List<String> supportedExtensions = ['docx'];

  /// MIME type registered in AndroidManifest.xml for "Open with".
  static const String docxMimeType =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

  // ── History / Storage ─────────────────────────────────────────────────────
  /// SharedPreferences key for the file history JSON list.
  static const String historyPrefsKey = 'formuladoc_file_history_v1';

  /// Maximum number of recent files to remember.
  static const int maxHistoryItems = 50;

  // ── Rendering ─────────────────────────────────────────────────────────────
  /// Horizontal padding (logical px) applied to document content.
  static const double documentHorizontalPadding = 20.0;

  /// Vertical padding at top/bottom of document scroll area.
  static const double documentVerticalPadding = 24.0;

  /// Maximum content width for readability on large screens.
  static const double documentMaxWidth = 780.0;

  /// Height (logical px) of an empty paragraph block.
  static const double emptyParagraphHeight = 6.0;

  /// Conversion ratio: 1 Word twip → logical pixels.
  /// 1 twip = 1/20 pt, 1 pt ≈ 1.333 logical px at 96 dpi.
  static const double twipToLogicalPx = 0.0667;

  /// Conversion: 1 point → logical pixels.
  static const double ptToLogicalPx = 1.333;

  /// Conversion: 1 EMU (English Metric Unit) → logical pixels.
  /// 914400 EMU = 1 inch = 96 logical px on mdpi.
  static const double emuToLogicalPx = 96.0 / 914400.0;

  // ── Zoom ──────────────────────────────────────────────────────────────────
  static const double minZoom = 0.5;
  static const double maxZoom = 4.0;
  static const double defaultZoom = 1.0;

  // ── Parse ─────────────────────────────────────────────────────────────────
  /// Word XML namespace for 'w:' elements.
  static const String nsW =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

  /// Math XML namespace for 'm:' elements.
  static const String nsM =
      'http://schemas.openxmlformats.org/officeDocument/2006/math';

  /// Relationships namespace.
  static const String nsR =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
}
