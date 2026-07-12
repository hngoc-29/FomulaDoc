import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/utils/file_utils.dart';
import '../../../../data/models/file_record.dart';

/// A card displaying a [FileRecord] in the recent files / favorites list.
class RecentFileCard extends StatelessWidget {
  final FileRecord record;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onRemove;

  /// True when this record matched the current search by document CONTENT
  /// rather than by filename — shows a small "nội dung" badge so the user
  /// understands why a result with a non-matching-looking name appeared.
  final bool matchedByContent;

  /// Multi-select ("Quản lý" / batch delete) support. When [selectionMode]
  /// is true, tapping the card toggles [selected] via [onSelectToggle]
  /// instead of opening the file, and a checkbox replaces the file icon.
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onSelectToggle;
  final VoidCallback? onLongPress;

  const RecentFileCard({
    super.key,
    required this.record,
    required this.onTap,
    required this.onFavoriteToggle,
    required this.onRemove,
    this.matchedByContent = false,
    this.selectionMode    = false,
    this.selected         = false,
    this.onSelectToggle,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ext    = record.name.split('.').last.toLowerCase();

    return Card(
      color: selected
          ? ThemeConstants.primaryBlue.withValues(alpha: 0.08)
          : null,
      child: InkWell(
        onTap: selectionMode ? onSelectToggle : onTap,
        onLongPress: onLongPress,
        borderRadius: ThemeConstants.cardRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // ── File icon / selection checkbox ───────────────────────────
              if (selectionMode)
                SizedBox(
                  width: 44, height: 44,
                  child: Center(
                    child: Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      color: selected
                          ? ThemeConstants.primaryBlue
                          : Colors.grey.shade400,
                      size: 26,
                    ),
                  ),
                )
              else
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color:        _iconColor(ext).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(ThemeConstants.radiusSm),
                  ),
                  child: Center(
                    child: Text(
                      _iconLabel(ext),
                      style: TextStyle(
                        fontSize:   ext == 'pdf' ? 12 : 18,
                        fontWeight: FontWeight.w800,
                        color:      _iconColor(ext),
                        letterSpacing: ext == 'pdf' ? 0.5 : 0,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 12),

              // ── Info ──────────────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(
                          FileUtils.stemOf(record.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (matchedByContent) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: ThemeConstants.primaryBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('nội dung',
                              style: TextStyle(fontSize: 9.5, color: ThemeConstants.primaryBlue)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          _formatDate(record.lastOpenedAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (record.fileSizeBytes != null) ...[
                          Text(
                            '  ·  ',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            FileUtils.formatSize(record.fileSizeBytes!),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                    // Reading progress bar
                    if (record.lastScrollPosition > 0.01) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: record.lastScrollPosition.clamp(0.0, 1.0),
                          minHeight: 3,
                          backgroundColor: isDark
                              ? const Color(0xFF2A2A2A)
                              : const Color(0xFFE0E0E0),
                          valueColor: const AlwaysStoppedAnimation(
                            ThemeConstants.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Actions (hidden during multi-select) ─────────────────────
              if (!selectionMode) ...[
                IconButton(
                  icon: Icon(
                    record.isFavorite ? Icons.star : Icons.star_outline,
                    size: 20,
                    color: record.isFavorite
                        ? const Color(0xFFFFAB00)
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.4),
                  ),
                  onPressed: onFavoriteToggle,
                  tooltip: record.isFavorite
                      ? 'Bỏ yêu thích'
                      : 'Thêm vào yêu thích',
                ),
                PopupMenuButton<_Action>(
                  icon: Icon(Icons.more_vert, size: 20,
                      color: Theme.of(context)
                          .colorScheme.onSurface.withValues(alpha: 0.5)),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: _Action.open,
                      child: Row(children: [
                        Icon(Icons.open_in_new, size: 18),
                        SizedBox(width: 10),
                        Text('Mở'),
                      ]),
                    ),
                    PopupMenuItem(
                      value: _Action.remove,
                      child: Row(children: [
                        Icon(Icons.delete_outline, size: 18,
                            color: Theme.of(context).colorScheme.error),
                        const SizedBox(width: 10),
                        Text('Xóa khỏi lịch sử',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ]),
                    ),
                  ],
                  onSelected: (action) {
                    if (action == _Action.open)   onTap();
                    if (action == _Action.remove) onRemove();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now  = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inHours   < 1) return '${diff.inMinutes} phút trước';
    if (diff.inDays    < 1) return '${diff.inHours} giờ trước';
    if (diff.inDays   == 1) return 'Hôm qua';
    if (diff.inDays    < 7) return '${diff.inDays} ngày trước';
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  static String _iconLabel(String ext) => switch (ext) {
    'pdf'              => 'PDF',
    'xlsx' || 'xls'   => 'XLS',
    'pptx' || 'ppt'   => 'PPT',
    _                  => 'W',   // docx / doc
  };

  static Color _iconColor(String ext) => switch (ext) {
    'pdf'              => const Color(0xFFE53935),  // red
    'xlsx' || 'xls'   => const Color(0xFF1E8E3E),  // green
    'pptx' || 'ppt'   => const Color(0xFFE65100),  // orange
    _                  => ThemeConstants.primaryBlue,
  };
}

enum _Action { open, remove }
