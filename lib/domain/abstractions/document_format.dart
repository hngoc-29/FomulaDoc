/// All document formats FormulaDoc supports (or plans to support).
///
/// Adding a new format here is the first step; the rest follows from the
/// [DocumentParser] + [DocumentRenderer] abstractions.
enum DocumentFormat {
  /// Microsoft Word Open XML (.docx) — Phase 1.
  docx,

  /// Portable Document Format (.pdf) — Phase 5.
  pdf,

  /// PowerPoint Open XML (.pptx) — Phase 5.
  pptx,

  /// Excel Open XML (.xlsx) — Phase 5.
  xlsx,

  /// Legacy Word binary (.doc) — Phase 5.
  doc,
}

extension DocumentFormatX on DocumentFormat {
  /// Human-readable display name.
  String get displayName => switch (this) {
        DocumentFormat.docx => 'Word Document',
        DocumentFormat.pdf  => 'PDF Document',
        DocumentFormat.pptx => 'PowerPoint',
        DocumentFormat.xlsx => 'Excel Spreadsheet',
        DocumentFormat.doc  => 'Word 97-2003',
      };

  /// Registered file extensions (without dot).
  List<String> get extensions => switch (this) {
        DocumentFormat.docx => ['docx'],
        DocumentFormat.pdf  => ['pdf'],
        DocumentFormat.pptx => ['pptx'],
        DocumentFormat.xlsx => ['xlsx'],
        DocumentFormat.doc  => ['doc'],
      };

  /// Whether this format is implemented in the current build.
  bool get isSupported => this == DocumentFormat.docx
      || this == DocumentFormat.pdf
      || this == DocumentFormat.xlsx;

  static DocumentFormat? fromExtension(String ext) {
    final lower = ext.toLowerCase().replaceFirst('.', '');
    for (final format in DocumentFormat.values) {
      if (format.extensions.contains(lower)) return format;
    }
    return null;
  }
}
