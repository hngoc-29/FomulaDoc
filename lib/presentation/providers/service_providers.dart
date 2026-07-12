import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/parsers/parser_registry.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/serializers/docx_serializer.dart';
import '../../platform/platform_intent_handler.dart';
import '../../services/document_cache_service.dart';
import '../../services/document_search_service.dart';
import '../../services/file_service.dart';
import '../../services/history_service.dart';
import '../../services/hyperlink_service.dart';

// ── Repositories ──────────────────────────────────────────────────────────────

final historyRepositoryProvider = Provider<HistoryRepository>(
  (_) => const HistoryRepository(),
  name: 'historyRepositoryProvider',
);

// ── Services ──────────────────────────────────────────────────────────────────

final fileServiceProvider = Provider<FileService>(
  (_) => const FileService(),
  name: 'fileServiceProvider',
);

final historyServiceProvider = Provider<HistoryService>(
  (ref) => HistoryService(ref.read(historyRepositoryProvider)),
  name: 'historyServiceProvider',
);

final hyperlinkServiceProvider = Provider<HyperlinkService>(
  (_) => const HyperlinkService(),
  name: 'hyperlinkServiceProvider',
);

// ── Phase 4 ───────────────────────────────────────────────────────────────────

final documentCacheProvider = Provider<DocumentCacheService>(
  (_) => DocumentCacheService(maxEntries: 5),
  name: 'documentCacheProvider',
);

final documentSearchServiceProvider = Provider<DocumentSearchService>(
  (_) => const DocumentSearchService(),
  name: 'documentSearchServiceProvider',
);

// ── Phase 5 ───────────────────────────────────────────────────────────────────

/// Global parser registry — populated at startup via [main.dart].
final parserRegistryProvider = Provider<DocumentParserRegistry>(
  (_) => DocumentParserRegistry.instance,
  name: 'parserRegistryProvider',
);

/// DOCX serializer for round-trip editing and export.
final docxSerializerProvider = Provider<DocxSerializer>(
  (_) => const DocxSerializer(),
  name: 'docxSerializerProvider',
);

// ── Platform ──────────────────────────────────────────────────────────────────

final intentHandlerProvider = Provider<PlatformIntentHandler>(
  (ref) {
    final handler = PlatformIntentHandler();
    ref.onDispose(handler.dispose);
    return handler;
  },
  name: 'intentHandlerProvider',
);
