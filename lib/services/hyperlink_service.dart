import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/utils/logger.dart';

/// Opens external hyperlinks from document content.
///
/// Wraps [url_launcher] so it can be mocked in tests and swapped for
/// in-app browser or other implementations in future phases.
class HyperlinkService {
  const HyperlinkService();

  /// Launches [url] in the device's default browser or appropriate handler.
  ///
  /// Returns `true` if the URL was successfully launched.
  /// Logs a warning and returns `false` on failure.
  Future<bool> open(String url) async {
    if (url.isEmpty) return false;

    try {
      final uri = _parseUri(url);
      if (uri == null) {
        AppLogger.warning('Invalid URL: $url', tag: 'HyperlinkService');
        return false;
      }

      if (!await canLaunchUrl(uri)) {
        AppLogger.warning('Cannot launch: $url', tag: 'HyperlinkService');
        return false;
      }

      await launchUrl(uri, mode: LaunchMode.externalApplication);
      AppLogger.info('Opened URL: $url', tag: 'HyperlinkService');
      return true;
    } on PlatformException catch (e) {
      AppLogger.error(
        'Failed to open URL: $url',
        tag: 'HyperlinkService',
        error: e,
      );
      return false;
    } catch (e) {
      AppLogger.error(
        'Unexpected error opening URL: $url',
        tag: 'HyperlinkService',
        error: e,
      );
      return false;
    }
  }

  /// Copies [url] to clipboard and returns `true` on success.
  Future<bool> copyToClipboard(String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      AppLogger.debug('Copied to clipboard: $url', tag: 'HyperlinkService');
      return true;
    } catch (e) {
      AppLogger.warning('Clipboard copy failed: $e', tag: 'HyperlinkService');
      return false;
    }
  }

  Uri? _parseUri(String url) {
    // Prepend https:// if the URL has no scheme
    final normalized = url.contains('://') ? url : 'https://$url';
    return Uri.tryParse(normalized);
  }
}
