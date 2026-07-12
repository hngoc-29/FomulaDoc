import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Calls the native Android [WmfRenderer] via a MethodChannel to convert
/// raw WMF bytes into a PNG [Uint8List].
///
/// Returns null if the platform channel is unavailable (e.g. on non-Android)
/// or if the WMF cannot be rendered.
class WmfRenderService {
  static const _channel = MethodChannel('formuladoc/wmf');

  /// Render [wmfBytes] (a raw WMF file) to PNG bytes.
  /// Returns null on failure.
  Future<Uint8List?> renderToPng(Uint8List wmfBytes) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'renderWmf',
        wmfBytes,
      );
      return result;
    } on PlatformException catch (e) {
      // Log but don't crash — caller will show a placeholder instead
      debugPrint('[WmfRenderService] render failed: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[WmfRenderService] unexpected error: $e');
      return null;
    }
  }
}

void debugPrint(String s) {
  // ignore: avoid_print
  print(s);
}
