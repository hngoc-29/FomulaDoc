import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/theme_constants.dart';
import '../../providers/history_provider.dart';
import '../../providers/service_providers.dart';
import '../../providers/font_size_provider.dart';
import '../../providers/reading_prefs_provider.dart';
import '../../providers/theme_provider.dart';
import '../../../services/reading_stats_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SETTINGS SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt'),
        centerTitle: false,
      ),
      body: ListView(
        children: [

          // ── App header ────────────────────────────────────────────────────
          _AppHeader(),
          const SizedBox(height: 4),

          // ── Giao diện ─────────────────────────────────────────────────────
          _SectionCard(
            title: 'Giao diện',
            icon:  Icons.palette_outlined,
            children: [
              ListTile(
                title:    const Text('Chủ đề'),
                subtitle: Text(_themeName(themeMode)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showThemePicker(context, ref, themeMode),
              ),
              // ── Font size slider ──────────────────────────────────────────
              Consumer(builder: (context, ref, _) {
                final fontSize = ref.watch(fontSizeProvider);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Cỡ chữ tài liệu'),
                          Text(
                            '${fontSize.round()}pt',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color:      ThemeConstants.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Slider(
                      value:    fontSize,
                      min:      kMinFontSize,
                      max:      kMaxFontSize,
                      divisions: ((kMaxFontSize - kMinFontSize) / 1).round(),
                      label:    '${fontSize.round()}pt',
                      onChanged: (v) =>
                          ref.read(fontSizeProvider.notifier).setSize(v),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('A', style: TextStyle(
                            fontSize: kMinFontSize,
                            color: Theme.of(context).colorScheme.onSurface
                                .withValues(alpha: 0.45),
                          )),
                          TextButton(
                            onPressed: () =>
                                ref.read(fontSizeProvider.notifier).reset(),
                            child: const Text('Đặt lại'),
                          ),
                          Text('A', style: TextStyle(
                            fontSize: kMaxFontSize * 0.8,
                            color: Theme.of(context).colorScheme.onSurface
                                .withValues(alpha: 0.45),
                          )),
                        ],
                      ),
                    ),
                  ],
                );
              }),

              // ── Line spacing slider ────────────────────────────────────────
              Consumer(builder: (context, ref, _) {
                final spacing = ref.watch(lineSpacingProvider);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Giãn dòng'),
                          Text(
                            spacing.toStringAsFixed(1),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color:      ThemeConstants.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Slider(
                      value: spacing,
                      min: kMinLineSpacing,
                      max: kMaxLineSpacing,
                      divisions: 10,
                      label: spacing.toStringAsFixed(1),
                      onChanged: (v) =>
                          ref.read(lineSpacingProvider.notifier).setValue(v),
                    ),
                  ],
                );
              }),

              // ── Margin slider ───────────────────────────────────────────────
              Consumer(builder: (context, ref, _) {
                final margin = ref.watch(readingMarginProvider);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Lề trái/phải'),
                          Text(
                            '${margin.round()}px',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color:      ThemeConstants.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Slider(
                      value: margin,
                      min: kMinMargin,
                      max: kMaxMargin,
                      divisions: 8,
                      label: '${margin.round()}px',
                      onChanged: (v) =>
                          ref.read(readingMarginProvider.notifier).setValue(v),
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              }),
            ],
          ),

          // ── Bộ nhớ đệm ───────────────────────────────────────────────────
          _SectionCard(
            title: 'Bộ nhớ đệm',
            icon:  Icons.storage_outlined,
            children: [
              Consumer(builder: (context, ref, _) {
                final cache = ref.watch(documentCacheProvider);
                return Column(children: [
                  _InfoRow(
                    label: 'Tài liệu đã lưu',
                    value: '${cache.size} / ${cache.maxEntries}',
                  ),
                  _InfoRow(
                    label: 'Dung lượng',
                    value: _formatSize(cache.estimatedSizeKb()),
                  ),
                  _ActionButton(
                    label: 'Xóa bộ nhớ đệm',
                    icon:  Icons.delete_sweep_outlined,
                    onTap: () => _clearCache(context, ref),
                  ),
                ]);
              }),
            ],
          ),

          // ── Lịch sử ───────────────────────────────────────────────────────
          _SectionCard(
            title: 'Lịch sử tài liệu',
            icon:  Icons.history_outlined,
            children: [
              Consumer(builder: (context, ref, _) {
                final hist = ref.watch(historyNotifierProvider);
                return Column(children: [
                  _InfoRow(
                    label: 'Đã mở gần đây',
                    value: '${hist.recentFiles.length}',
                  ),
                  _InfoRow(
                    label: 'Yêu thích',
                    value: '${hist.favorites.length}',
                  ),
                  _ActionButton(
                    label: 'Xóa lịch sử',
                    icon:  Icons.clear_all,
                    onTap: () => _clearHistory(context, ref),
                  ),
                ]);
              }),
            ],
          ),

          // ── Thống kê đọc ──────────────────────────────────────────────────
          _SectionCard(
            title: 'Thống kê đọc',
            icon:  Icons.insights_outlined,
            children: [
              FutureBuilder<ReadingStats>(
                future: ReadingStatsService().getStats(),
                builder: (context, snapshot) {
                  final stats = snapshot.data;
                  if (stats == null) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(child: _StatTile(
                          icon:  Icons.schedule,
                          value: _formatDuration(stats.totalReadTime),
                          label: 'Thời gian đọc',
                        )),
                        Expanded(child: _StatTile(
                          icon:  Icons.menu_book,
                          value: '${stats.documentsOpened}',
                          label: 'Tài liệu đã mở',
                        )),
                        Expanded(child: _StatTile(
                          icon:  Icons.local_fire_department,
                          value: '${stats.currentStreak}',
                          label: 'Ngày liên tiếp',
                        )),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),

          // ── Định dạng hỗ trợ ──────────────────────────────────────────────
          _SectionCard(
            title: 'Định dạng hỗ trợ',
            icon:  Icons.folder_open_outlined,
            children: [
              _FormatRow(label: 'Word',       ext: '.docx',  ok: true),
              _FormatRow(label: 'PDF',        ext: '.pdf',   ok: true),
              _FormatRow(label: 'Excel',      ext: '.xlsx',  ok: true),
            ],
          ),

          // ── Thông tin ─────────────────────────────────────────────────────
          _SectionCard(
            title: 'Thông tin ứng dụng',
            icon:  Icons.info_outline,
            children: [
              _InfoRow(label: 'Phiên bản', value: 'v${AppConstants.appVersion}'),
              const ListTile(
                leading:  Icon(Icons.functions_outlined),
                title:    Text('Hỗ trợ công thức toán'),
                subtitle: Text('OMML, MathType, LaTeX'),
                dense:    true,
              ),
              const ListTile(
                leading:  Icon(Icons.image_outlined),
                title:    Text('Render phương trình WMF'),
                subtitle: Text('Hiển thị bằng renderer native Android'),
                dense:    true,
              ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Theme picker ───────────────────────────────────────────────────────────

  void _showThemePicker(
      BuildContext context, WidgetRef ref, ThemeMode current) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Chọn chủ đề',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          for (final mode in ThemeMode.values)
            RadioListTile<ThemeMode>(
              title:      Text(_themeName(mode)),
              value:      mode,
              groupValue: current,
              onChanged: (v) {
                // Update the GLOBAL provider → MaterialApp rebuilds immediately
                ref.read(themeModeProvider.notifier).state = v!;
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    if (!await _confirm(context,
        title:   'Xóa bộ nhớ đệm?',
        message: 'Tài liệu đã lưu sẽ được tải lại lần sau.')) return;
    ref.read(documentCacheProvider).clear();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đã xóa bộ nhớ đệm')));
    }
  }

  Future<void> _clearHistory(BuildContext context, WidgetRef ref) async {
    if (!await _confirm(context,
        title:   'Xóa lịch sử?',
        message: 'Tất cả tài liệu gần đây và yêu thích sẽ bị xóa.')) return;
    await ref.read(historyNotifierProvider.notifier).clearAll();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đã xóa lịch sử')));
    }
  }

  Future<bool> _confirm(BuildContext context,
      {required String title, required String message}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title:   Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Xóa')),
        ],
      ),
    );
    return result == true;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _themeName(ThemeMode m) => switch (m) {
        ThemeMode.system => 'Theo hệ thống',
        ThemeMode.light  => 'Sáng',
        ThemeMode.dark   => 'Tối',
      };

  static String _formatSize(int kb) {
    if (kb < 1024) return '$kb KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  static String _formatDuration(Duration d) {
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}p';
    if (d.inMinutes >= 1) return '${d.inMinutes} phút';
    return '${d.inSeconds}s';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _AppHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color:        ThemeConstants.primaryBlue,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.functions, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppConstants.appName,
              style: Theme.of(context)
                  .textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              'Xem tài liệu Word · PDF · Excel',
              style: TextStyle(
                fontSize: 12,
                color:    ThemeConstants.primaryBlue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String       title;
  final IconData     icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Row(children: [
              Icon(icon, size: 14,
                  color: ThemeConstants.primaryBlue.withValues(alpha: 0.8)),
              const SizedBox(width: 5),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize:      10,
                  fontWeight:    FontWeight.w700,
                  letterSpacing: 1.1,
                  color:         Theme.of(context)
                      .colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ]),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            Text(value,
                style: TextStyle(
                  fontSize:   13,
                  fontWeight: FontWeight.w600,
                  color:      ThemeConstants.primaryBlue,
                )),
          ],
        ),
      );
}

class _ActionButton extends StatelessWidget {
  final String   label;
  final IconData icon;
  final VoidCallback onTap;
  const _ActionButton(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon:  Icon(icon, size: 17),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
            side: BorderSide(
                color: Theme.of(context)
                    .colorScheme.error.withValues(alpha: 0.5)),
          ),
        ),
      );
}

class _FormatRow extends StatelessWidget {
  final String label;
  final String ext;
  final bool   ok;
  const _FormatRow({required this.label, required this.ext, required this.ok});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Container(
          width: 9, height: 9,
          decoration: BoxDecoration(
            color: ok ? Colors.green : Colors.grey.shade400,
            shape: BoxShape.circle,
          ),
        ),
        title:    Text(label),
        trailing: Text(ext,
            style: TextStyle(
              fontSize:   12,
              color:      Theme.of(context)
                  .colorScheme.onSurface.withValues(alpha: 0.5),
              fontFamily: 'monospace',
            )),
        dense: true,
      );
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String   value;
  final String   label;
  const _StatTile({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Icon(icon, size: 20, color: ThemeConstants.primaryBlue),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                fontSize: 10.5,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
              ),
              textAlign: TextAlign.center),
        ],
      );
}
