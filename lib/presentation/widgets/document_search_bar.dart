import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/theme_constants.dart';
import '../providers/search_provider.dart';

/// An animated search bar that slides in below the AppBar.
///
/// Pressing the search icon opens it; pressing ✕ or the back button closes it.
/// Shows the current match count ("3 / 12") and prev/next navigation buttons.
class DocumentSearchBar extends ConsumerStatefulWidget {
  /// Called when the user navigates to a result — the viewer scrolls to it.
  final void Function(int resultIndex)? onNavigate;

  const DocumentSearchBar({super.key, this.onNavigate});

  @override
  ConsumerState<DocumentSearchBar> createState() => _DocumentSearchBarState();
}

class _DocumentSearchBarState extends ConsumerState<DocumentSearchBar>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  late final AnimationController   _animController;
  late final Animation<double>      _slideAnim;
  late final FocusNode             _focusNode;

  @override
  void initState() {
    super.initState();
    _controller    = TextEditingController();
    _focusNode     = FocusNode();
    _focusNode.addListener(() => setState(() {}));
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _slideAnim = CurvedAnimation(
      parent: _animController,
      curve:  Curves.easeOut,
    );

    // Listen to provider to sync open/close animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final isOpen = ref.read(searchNotifierProvider).isOpen;
      if (isOpen) {
        _animController.forward();
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _close() {
    ref.read(searchNotifierProvider.notifier).submitQuery();
    _animController.reverse().then((_) {
      ref.read(searchNotifierProvider.notifier).close();
      _controller.clear();
    });
  }

  void _onQueryChanged(String text) {
    ref.read(searchNotifierProvider.notifier).updateQuery(text);
  }

  void _navigate(bool forward) {
    final notifier = ref.read(searchNotifierProvider.notifier);
    if (forward) {
      notifier.next();
    } else {
      notifier.previous();
    }
    final state = ref.read(searchNotifierProvider);
    widget.onNavigate?.call(state.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchNotifierProvider);

    // Keep animation in sync with open state
    if (searchState.isOpen && !_animController.isAnimating &&
        _animController.value == 0) {
      _animController.forward();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }

    return SizeTransition(
      sizeFactor: _slideAnim,
      axisAlignment: -1,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) {
          if (event.logicalKey == LogicalKeyboardKey.escape) _close();
          if (event.logicalKey == LogicalKeyboardKey.enter) _navigate(true);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SearchBarContent(
              controller:   _controller,
              focusNode:    _focusNode,
              searchState:  searchState,
              onChanged:    _onQueryChanged,
              onClose:      _close,
              onNext:       () => _navigate(true),
              onPrev:       () => _navigate(false),
            ),
            // ── Recent search chips ──────────────────────────────────────
            // Shown only while the field is empty and focused, so returning
            // users don't have to retype common queries.
            if (searchState.query.isEmpty &&
                searchState.recentQueries.isNotEmpty &&
                _focusNode.hasFocus)
              _RecentQueriesRow(
                queries: searchState.recentQueries,
                onTap: (q) {
                  _controller.text = q;
                  _onQueryChanged(q);
                },
                onClear: () =>
                    ref.read(searchNotifierProvider.notifier).clearHistory(),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Bar content ──────────────────────────────────────────────────────────────

class _SearchBarContent extends ConsumerWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final SearchState searchState;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final VoidCallback onNext;
  final VoidCallback onPrev;

  const _SearchBarContent({
    required this.controller,
    required this.focusNode,
    required this.searchState,
    required this.onChanged,
    required this.onClose,
    required this.onNext,
    required this.onPrev,
  });

  @override
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final barColor = isDark ? const Color(0xFF1A2340) : Colors.white;
    final noMatch  = searchState.query.isNotEmpty && !searchState.hasResults;

    return Material(
      elevation: 4,
      color: barColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // ── Search field ──────────────────────────────────────────────
            Expanded(
              child: TextField(
                controller:  controller,
                focusNode:   focusNode,
                onChanged:   onChanged,
                onSubmitted: (_) => onNext(),
                style:       const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  hintText:      'Search in document…',
                  prefixIcon:    const Icon(Icons.search, size: 20),
                  suffixIcon:    controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            controller.clear();
                            onChanged('');
                          },
                        )
                      : null,
                  filled:        true,
                  fillColor:     isDark
                      ? const Color(0xFF252525)
                      : const Color(0xFFF5F5F5),
                  border:        OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:  BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: noMatch
                          ? Theme.of(context).colorScheme.error.withValues(alpha: 0.6)
                          : Colors.transparent,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                ),
              ),
            ),

            const SizedBox(width: 6),

            // ── Match count ──────────────────────────────────────────────
            if (searchState.query.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: searchState.hasResults
                      ? ThemeConstants.primaryBlue.withValues(alpha: 0.12)
                      : Theme.of(context).colorScheme.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  searchState.statusText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: searchState.hasResults
                        ? ThemeConstants.primaryBlue
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),

            // ── Aa toggle (case-sensitive) ────────────────────────────────
            _SearchToggle(
              label:   'Aa',
              active:  searchState.caseSensitive,
              tooltip: 'Phân biệt hoa/thường',
              onTap:   () => ref.read(searchNotifierProvider.notifier)
                  .toggleCaseSensitive(),
            ),

            // ── W toggle (whole word) ─────────────────────────────────────
            _SearchToggle(
              label:   'W',
              active:  searchState.wholeWord,
              tooltip: 'Toàn từ',
              onTap:   () => ref.read(searchNotifierProvider.notifier)
                  .toggleWholeWord(),
            ),

            // ── Navigation buttons ────────────────────────────────────────
            IconButton(
              icon:     const Icon(Icons.keyboard_arrow_up, size: 20),
              onPressed: searchState.hasResults ? onPrev : null,
              tooltip:  'Kết quả trước',
              padding:  EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            IconButton(
              icon:     const Icon(Icons.keyboard_arrow_down, size: 20),
              onPressed: searchState.hasResults ? onNext : null,
              tooltip:  'Kết quả tiếp',
              padding:  EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),

            // ── Close ────────────────────────────────────────────────────
            IconButton(
              icon:     const Icon(Icons.close, size: 20),
              onPressed: onClose,
              tooltip:  'Đóng tìm kiếm',
              padding:  EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Toggle button ─────────────────────────────────────────────────────────────

class _SearchToggle extends StatelessWidget {
  final String       label;
  final bool         active;
  final String       tooltip;
  final VoidCallback onTap;
  const _SearchToggle({
    required this.label, required this.active,
    required this.tooltip, required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin:  const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: active
              ? ThemeConstants.primaryBlue.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: active ? ThemeConstants.primaryBlue : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(label,
          style: TextStyle(
            fontSize:   12,
            fontWeight: FontWeight.w700,
            color: active
                ? ThemeConstants.primaryBlue
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ),
    ),
  );
}

// ─── Recent search history chips ───────────────────────────────────────────────

class _RecentQueriesRow extends StatelessWidget {
  final List<String>            queries;
  final void Function(String q) onTap;
  final VoidCallback            onClear;

  const _RecentQueriesRow({
    required this.queries,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      color: isDark ? const Color(0xFF1A2340) : Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Tìm gần đây',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  )),
              InkWell(
                onTap: onClear,
                child: Text('Xóa',
                    style: TextStyle(fontSize: 11, color: ThemeConstants.primaryBlue)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: queries.map((q) => InkWell(
              onTap: () => onTap(q),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: ThemeConstants.primaryBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.history, size: 13, color: ThemeConstants.primaryBlue),
                    const SizedBox(width: 4),
                    Text(q, style: const TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }
}
