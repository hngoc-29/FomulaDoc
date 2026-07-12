import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'data/parsers/parser_registry.dart';
import 'platform/shortcut_service.dart';
import 'presentation/providers/document_provider.dart';
import 'presentation/providers/history_provider.dart';
import 'presentation/providers/service_providers.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/viewer/viewer_screen.dart';
import 'presentation/theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ENTRY POINT
// ═══════════════════════════════════════════════════════════════════════════════

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Phase 5: register all format parsers before the app starts
  DocumentParserRegistry.instance.registerDefaults();

  runApp(
    const ProviderScope(
      child: FormulaDocApp(),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// ROOT APPLICATION
// ═══════════════════════════════════════════════════════════════════════════════

class FormulaDocApp extends ConsumerStatefulWidget {
  const FormulaDocApp({super.key});

  @override
  ConsumerState<FormulaDocApp> createState() => _FormulaDocAppState();
}

class _FormulaDocAppState extends ConsumerState<FormulaDocApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<String>? _intentSub;
  bool _handlerReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initIntentHandler();
      _initShortcutHandler();
    });
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    super.dispose();
  }

  // ── Intent / "Open with" handling ─────────────────────────────────────────

  Future<void> _initIntentHandler() async {
    if (_handlerReady) return;
    _handlerReady = true;

    try {
      final handler = ref.read(intentHandlerProvider);

      // Subscribe BEFORE initialize() so cold-start paths emitted during
      // getInitialMedia() are not lost (broadcast stream drops events
      // with no listeners).
      _intentSub = handler.fileStream.listen(
        _handleIncomingFile,
        onError: (Object e) =>
            debugPrint('[FormulaDocApp] Intent stream error: $e'),
      );

      await handler.initialize();
    } catch (e) {
      debugPrint('[FormulaDocApp] Intent handler init failed: $e');
    }
  }

  void _handleIncomingFile(String path) {
    if (path.isEmpty) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    // Pass path directly to ViewerScreen so it loads via its own notifier
    // instance (documentNotifierProvider is autoDispose — calling openFromPath
    // on a separate read would create a provider that gets disposed before
    // ViewerScreen subscribes to it).
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => ViewerScreen.fromPath(path)),
      (route) => route.isFirst,
    );
  }

  // ── App shortcuts (long-press launcher icon) ──────────────────────────────

  Future<void> _initShortcutHandler() async {
    final action = await ShortcutService().getPendingAction();
    if (action == null || !mounted) return;

    switch (action) {
      case 'open_recent':
        await _openMostRecentFile();
      case 'pick_file':
        await _pickAndOpenFile();
    }
  }

  Future<void> _openMostRecentFile() async {
    final historyNotifier = ref.read(historyNotifierProvider.notifier);
    await historyNotifier.load();
    if (!mounted) return;

    final recent = ref.read(historyNotifierProvider).recentFiles;
    final navigator = _navigatorKey.currentState;
    if (recent.isEmpty || navigator == null) return;

    navigator.push(MaterialPageRoute<void>(
      builder: (_) => ViewerScreen.fromPath(recent.first.path),
    ));
  }

  Future<void> _pickAndOpenFile() async {
    await ref.read(documentNotifierProvider.notifier).pickAndOpen();
    if (!mounted) return;

    final docState = ref.read(documentNotifierProvider);
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    if (docState.isLoaded || docState.isLoading) {
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => const ViewerScreen(),
      ));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                    AppConstants.appName,
      navigatorKey:             _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme:      AppTheme.light,
      darkTheme:  AppTheme.dark,
      themeMode:  ref.watch(themeModeProvider),
      home:       const HomeScreen(),
    );
  }
}
