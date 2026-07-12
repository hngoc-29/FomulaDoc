import 'dart:async';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../core/utils/logger.dart';

/// Handles Android "Open with" intents and iOS Share Extension file delivery.
///
/// Wraps [receive_sharing_intent] to provide a clean broadcast stream
/// of file paths received from external applications.
///
/// Compatible with receive_sharing_intent ^1.8.x.
///
/// Usage:
/// ```dart
/// final handler = PlatformIntentHandler();
/// await handler.initialize();
/// handler.fileStream.listen((path) => openDocument(path));
/// ```
class PlatformIntentHandler {
  final _controller = StreamController<String>.broadcast();
  StreamSubscription<List<SharedMediaFile>>? _liveSubscription;
  bool _initialized = false;

  /// Emits absolute file paths received from external apps.
  Stream<String> get fileStream => _controller.stream;

  /// Call once before listening to [fileStream].
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // ── Files shared while the app is already running ─────────────────────
    try {
      _liveSubscription = ReceiveSharingIntent.instance
          .getMediaStream()
          .listen(
            _handleFiles,
            onError: (Object e) {
              AppLogger.error(
                'Intent media stream error',
                tag: 'PlatformIntentHandler',
                error: e,
              );
            },
          );
    } catch (e) {
      AppLogger.warning(
        'Could not subscribe to live intent stream: $e',
        tag: 'PlatformIntentHandler',
      );
    }

    // ── Files shared on cold start (app was launched via "Open with") ─────
    try {
      final initialFiles =
          await ReceiveSharingIntent.instance.getInitialMedia();
      if (initialFiles.isNotEmpty) {
        AppLogger.info(
          'Cold-start: ${initialFiles.length} file(s) from intent',
          tag: 'PlatformIntentHandler',
        );
        _handleFiles(initialFiles);
        // Reset so intent isn't replayed on hot restart
        ReceiveSharingIntent.instance.reset();
      }
    } catch (e) {
      AppLogger.warning(
        'Could not retrieve initial media intent: $e',
        tag: 'PlatformIntentHandler',
      );
    }
  }

  void _handleFiles(List<SharedMediaFile> files) {
    for (final file in files) {
      final path = file.path.trim();
      if (path.isEmpty) continue;

      final ext = path.toLowerCase();
      final supported = ext.endsWith('.docx') ||
          ext.endsWith('.doc')  ||
          ext.endsWith('.pdf')  ||
          ext.endsWith('.xlsx') ||
          ext.endsWith('.xls');

      if (!supported) {
        AppLogger.debug(
          'Ignoring unsupported file from intent: $path',
          tag: 'PlatformIntentHandler',
        );
        continue;
      }

      AppLogger.info(
        'Received document from intent: $path',
        tag: 'PlatformIntentHandler',
      );

      if (!_controller.isClosed) _controller.add(path);
    }
  }

  Future<void> dispose() async {
    await _liveSubscription?.cancel();
    await _controller.close();
  }
}
