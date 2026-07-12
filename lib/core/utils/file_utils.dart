import 'dart:io';
import 'package:path/path.dart' as p;
import '../constants/app_constants.dart';

/// Stateless utility functions for file operations.
class FileUtils {
  FileUtils._();

  /// Returns `true` if [path] points to a supported document format.
  static bool isSupportedExtension(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    return AppConstants.supportedExtensions.contains(ext);
  }

  /// Returns the lowercase extension without the dot, e.g. `'docx'`.
  static String extensionOf(String path) =>
      p.extension(path).toLowerCase().replaceFirst('.', '');

  /// Extracts a human-readable file name (including extension) from [path].
  static String nameOf(String path) => p.basename(path);

  /// Extracts the file name without its extension.
  static String stemOf(String path) => p.basenameWithoutExtension(path);

  /// Returns a human-readable file size string.
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Returns the size of [file] in bytes, or `null` if unavailable.
  static int? fileSizeOf(String path) {
    try {
      return File(path).lengthSync();
    } catch (_) {
      return null;
    }
  }

  /// Returns `true` if the file at [path] currently exists on disk.
  static bool exists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Sanitizes a content:// URI or raw path into a canonical form.
  ///
  /// Some file managers provide paths with `file://` prefix — strip it.
  static String sanitizePath(String raw) {
    if (raw.startsWith('file://')) return Uri.parse(raw).toFilePath();
    return raw;
  }
}
