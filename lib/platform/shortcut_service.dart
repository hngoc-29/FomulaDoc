import 'package:flutter/services.dart';

/// Reads which static app shortcut (long-press launcher icon) launched the
/// app, if any. See MainActivity.kt's `formuladoc/shortcuts` channel for the
/// native side — this uses a pull model (call once at startup) rather than
/// a native→Dart push, to avoid racing the Flutter engine's readiness.
class ShortcutService {
  static const _channel = MethodChannel('formuladoc/shortcuts');

  /// Returns the pending shortcut action ('open_recent' | 'pick_file') or
  /// null if the app wasn't launched via a shortcut. Consumes the value on
  /// the native side, so calling this twice in a row returns null the
  /// second time.
  Future<String?> getPendingAction() async {
    try {
      final result = await _channel.invokeMethod<String>('getPendingShortcutAction');
      return result;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // Non-Android platforms (iOS, desktop) don't implement this channel.
      return null;
    }
  }
}
