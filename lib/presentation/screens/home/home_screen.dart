import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/theme_constants.dart';
import '../../../data/models/document_block.dart'
    hide TableRow, TableCell;
import '../../../data/models/file_record.dart';
import '../../providers/document_provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/service_providers.dart';
import '../../../services/document_cache_service.dart';
import '../viewer/viewer_screen.dart';
import 'widgets/empty_state_widget.dart';
import '../settings/settings_screen.dart' show SettingsScreen;
import 'widgets/recent_file_card.dart';

/// Checks whether [record] matches [query] by filename OR by content —
/// content matching only covers documents currently held in the in-memory
/// LRU cache (see [DocumentCacheService], capacity 5), since re-parsing
/// every historical file on every keystroke would be slow and untested for
/// the many different file formats/edge cases in the full history list.
/// Filename matching always covers the FULL history regardless of caching.
({bool matched, bool isContentMatch}) _matchesSearch(
  FileRecord record,
  String query,
  DocumentCacheService cache,
) {
  final q = query.toLowerCase();
  if (record.name.toLowerCase().contains(q)) {
    return (matched: true, isContentMatch: false);
  }

  final model = cache.get(record.path);
  if (model == null) return (matched: false, isContentMatch: false);

  for (final block in model.blocks) {
    final text = switch (block) {
      ParagraphBlock() => block.plainText,
      HeadingBlock()   => block.plainText,
      _                => null,
    };
    if (text != null && text.toLowerCase().contains(q)) {
      return (matched: true, isContentMatch: true);
    }
  }
  return (matched: false, isContentMatch: false);
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ── Batch selection ("Quản lý") ──────────────────────────────────────────
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  void _enterSelectionMode(String firstId) {
    setState(() {
      _selectionMode = true;
      _selectedIds..clear()..add(firstId);
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Xóa $count mục khỏi lịch sử?'),
        content: const Text('File gốc trên thiết bị không bị xóa, chỉ xóa khỏi danh sách này.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (confirm != true) return;

    final notifier = ref.read(historyNotifierProvider.notifier);
    for (final id in _selectedIds.toList()) {
      await notifier.removeRecord(id);
    }
    _exitSelectionMode();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(historyNotifierProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _openRecord(FileRecord record) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ViewerScreen.fromPath(record.path),
      ),
    );
  }

  Future<void> _openFilePicker() async {
    // Pick file THEN navigate — the notifier holds state across navigation
    await ref.read(documentNotifierProvider.notifier).pickAndOpen();
    if (!mounted) return;

    final docState = ref.read(documentNotifierProvider);
    if (docState.isLoaded || docState.isLoading) {
      // Navigate to viewer which will render the already-loaded/loading document
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ViewerScreen(),
        ),
      );
    } else if (docState.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(docState.errorMessage ?? 'Failed to open document'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _buildSliverAppBar(context, innerBoxIsScrolled),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _RecentTab(
              searchQuery: _searchQuery,
              onOpenRecord: _openRecord,
              onOpenPicker: _openFilePicker,
              selectionMode: _selectionMode,
              selectedIds: _selectedIds,
              onEnterSelection: _enterSelectionMode,
              onToggleSelection: _toggleSelection,
            ),
            _FavoritesTab(
              searchQuery: _searchQuery,
              onOpenRecord: _openRecord,
              selectionMode: _selectionMode,
              selectedIds: _selectedIds,
              onEnterSelection: _enterSelectionMode,
              onToggleSelection: _toggleSelection,
            ),
          ],
        ),
      ),
      // ── Batch-selection action bar ────────────────────────────────────────
      bottomNavigationBar: _selectionMode
          ? BottomAppBar(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _exitSelectionMode,
                    icon: const Icon(Icons.close),
                    label: const Text('Hủy'),
                  ),
                  Text('${_selectedIds.length} đã chọn',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextButton.icon(
                    onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                    icon: Icon(Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error),
                    label: Text('Xóa',
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                ],
              ),
            )
          : null,
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: _openFilePicker,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Mở tài liệu'),
              tooltip: 'Mở file từ thiết bị',
            ),
    );
  }

  SliverAppBar _buildSliverAppBar(BuildContext context, bool collapsed) {
    return SliverAppBar(
      expandedHeight: 160,
      floating: false,
      pinned: true,
      elevation: collapsed ? 4 : 0,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: _HeaderBackground(onOpenFile: _openFilePicker),
      ),
      title: AnimatedOpacity(
        opacity: collapsed ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: const Text('FormulaDoc'),
      ),
      actions: [
        IconButton(
          icon:     const Icon(Icons.settings_outlined),
          tooltip:  'Cài đặt',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(100),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Tìm trong lịch sử…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
              ),
            ),
            TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              tabs: const [Tab(text: 'Gần đây'), Tab(text: 'Yêu thích')],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _HeaderBackground extends StatelessWidget {
  final VoidCallback onOpenFile;

  const _HeaderBackground({required this.onOpenFile});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ThemeConstants.primaryBlueDark,
            ThemeConstants.primaryBlue,
            Color(0xFF1976D2),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.functions, color: Colors.white, size: 28),
              const SizedBox(width: 10),
              Text(
                'FormulaDoc',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Word equations rendered correctly',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.white60),
          ),
        ],
      ),
    );
  }
}

// ─── Recent Tab ───────────────────────────────────────────────────────────────

class _RecentTab extends ConsumerWidget {
  final String searchQuery;
  final void Function(FileRecord) onOpenRecord;
  final VoidCallback onOpenPicker;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(String id) onEnterSelection;
  final void Function(String id) onToggleSelection;

  const _RecentTab({
    required this.searchQuery,
    required this.onOpenRecord,
    required this.onOpenPicker,
    required this.selectionMode,
    required this.selectedIds,
    required this.onEnterSelection,
    required this.onToggleSelection,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyState = ref.watch(historyNotifierProvider);
    final notifier = ref.read(historyNotifierProvider.notifier);
    final cache = ref.watch(documentCacheProvider);

    if (historyState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    var records = historyState.recentFiles;
    final contentMatchIds = <String>{};
    if (searchQuery.isNotEmpty) {
      final filtered = <FileRecord>[];
      for (final r in records) {
        final result = _matchesSearch(r, searchQuery, cache);
        if (result.matched) {
          filtered.add(r);
          if (result.isContentMatch) contentMatchIds.add(r.id);
        }
      }
      records = filtered;
    }

    if (records.isEmpty) {
      return EmptyStateWidget(onOpenFile: onOpenPicker);
    }

    return RefreshIndicator(
      onRefresh: notifier.load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: records.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final r = records[i];
          return RecentFileCard(
            record: r,
            matchedByContent: contentMatchIds.contains(r.id),
            selectionMode: selectionMode,
            selected: selectedIds.contains(r.id),
            onTap: () => onOpenRecord(r),
            onFavoriteToggle: () => notifier.toggleFavorite(r.id),
            onRemove: () => notifier.removeRecord(r.id),
            onSelectToggle: () => onToggleSelection(r.id),
            onLongPress: () => onEnterSelection(r.id),
          );
        },
      ),
    );
  }
}

// ─── Favorites Tab ────────────────────────────────────────────────────────────

class _FavoritesTab extends ConsumerWidget {
  final String searchQuery;
  final void Function(FileRecord) onOpenRecord;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(String id) onEnterSelection;
  final void Function(String id) onToggleSelection;

  const _FavoritesTab({
    required this.searchQuery,
    required this.onOpenRecord,
    required this.selectionMode,
    required this.selectedIds,
    required this.onEnterSelection,
    required this.onToggleSelection,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyState = ref.watch(historyNotifierProvider);
    final notifier = ref.read(historyNotifierProvider.notifier);
    final cache = ref.watch(documentCacheProvider);

    if (historyState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    var favorites = historyState.favorites;
    final contentMatchIds = <String>{};
    if (searchQuery.isNotEmpty) {
      final filtered = <FileRecord>[];
      for (final r in favorites) {
        final result = _matchesSearch(r, searchQuery, cache);
        if (result.matched) {
          filtered.add(r);
          if (result.isContentMatch) contentMatchIds.add(r.id);
        }
      }
      favorites = filtered;
    }

    if (favorites.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_outline,
                size: 48,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(
              'Chưa có mục yêu thích',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
            ),
            const SizedBox(height: 6),
            Text('Nhấn ★ trên một tài liệu để thêm vào đây',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: favorites.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = favorites[i];
        return RecentFileCard(
          record: r,
          matchedByContent: contentMatchIds.contains(r.id),
          selectionMode: selectionMode,
          selected: selectedIds.contains(r.id),
          onTap: () => onOpenRecord(r),
          onFavoriteToggle: () => notifier.toggleFavorite(r.id),
          onRemove: () => notifier.removeRecord(r.id),
          onSelectToggle: () => onToggleSelection(r.id),
          onLongPress: () => onEnterSelection(r.id),
        );
      },
    );
  }
}
