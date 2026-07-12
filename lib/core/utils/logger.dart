import 'package:flutter/foundation.dart';

/// Lightweight structured logger for FormulaDoc.
///
/// In release builds only error-level messages are emitted.
/// Swap the sink to a crash-reporting SDK (Sentry, Firebase Crashlytics)
/// by replacing [_writeLine].
class AppLogger {
  AppLogger._();

  static void debug(String message, {String? tag}) =>
      _log(_Level.debug, message, tag: tag);

  static void info(String message, {String? tag}) =>
      _log(_Level.info, message, tag: tag);

  static void warning(String message, {String? tag, Object? error}) =>
      _log(_Level.warning, message, tag: tag, error: error);

  static void error(String message, {String? tag, Object? error, StackTrace? stack}) =>
      _log(_Level.error, message, tag: tag, error: error, stack: stack);

  // ── Internal ──────────────────────────────────────────────────────────────

  static void _log(
    _Level level,
    String message, {
    String? tag,
    Object? error,
    StackTrace? stack,
  }) {
    if (!kDebugMode && level == _Level.debug) return;

    final prefix = switch (level) {
      _Level.debug   => '🔍',
      _Level.info    => 'ℹ️ ',
      _Level.warning => '⚠️ ',
      _Level.error   => '🔴',
    };
    final tagStr = tag != null ? '[$tag] ' : '';
    final errorStr = error != null ? '\n  ↳ $error' : '';
    final stackStr =
        stack != null && level == _Level.error ? '\n$stack' : '';

    _writeLine('$prefix $tagStr$message$errorStr$stackStr');
  }

  static void _writeLine(String line) {
    // ignore: avoid_print
    print(line);
  }
}

enum _Level { debug, info, warning, error }
