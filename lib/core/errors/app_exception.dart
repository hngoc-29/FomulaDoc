/// Base exception for all FormulaDoc errors.
sealed class AppException implements Exception {
  final String message;
  final Object? cause;

  const AppException(this.message, {this.cause});

  @override
  String toString() => '$runtimeType: $message${cause != null ? ' (caused by: $cause)' : ''}';
}

/// Thrown when a document cannot be parsed.
final class ParseException extends AppException {
  /// The file or XML path that caused the failure.
  final String? source;

  const ParseException(super.message, {super.cause, this.source});
}

/// Thrown when a requested file cannot be found or read.
final class FileNotFoundException extends AppException {
  final String path;

  const FileNotFoundException(this.path)
      : super('File not found: $path');
}

/// Thrown when an unsupported document format is provided.
final class UnsupportedFormatException extends AppException {
  final String extension;

  const UnsupportedFormatException(this.extension)
      : super('Unsupported document format: $extension');
}

/// Thrown for storage / persistence failures.
final class StorageException extends AppException {
  const StorageException(super.message, {super.cause});
}

/// Thrown when a platform-specific operation fails.
final class PlatformException extends AppException {
  const PlatformException(super.message, {super.cause});
}
