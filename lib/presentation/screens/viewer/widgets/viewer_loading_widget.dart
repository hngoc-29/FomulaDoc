import 'package:flutter/material.dart';

import '../../../../core/constants/theme_constants.dart';

/// Full-screen loading overlay shown while the document parser is running.
class ViewerLoadingWidget extends StatefulWidget {
  final String? fileName;
  final double progress;

  const ViewerLoadingWidget({
    super.key,
    this.fileName,
    this.progress = 0.0,
  });

  @override
  State<ViewerLoadingWidget> createState() => _ViewerLoadingWidgetState();
}

class _ViewerLoadingWidgetState extends State<ViewerLoadingWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: isDark
          ? Colors.black.withValues(alpha: 0.7)
          : Colors.white.withValues(alpha: 0.9),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated document icon
            ScaleTransition(
              scale: _pulseAnim,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: ThemeConstants.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  size: 36,
                  color: ThemeConstants.primaryBlue,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Đang mở tài liệu…',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: ThemeConstants.primaryBlue,
                  ),
            ),
            if (widget.fileName != null) ...[
              const SizedBox(height: 6),
              Text(
                widget.fileName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 20),
            // Progress bar
            SizedBox(
              width: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: widget.progress > 0 ? widget.progress : null,
                  backgroundColor:
                      ThemeConstants.primaryBlue.withValues(alpha: 0.15),
                  valueColor: const AlwaysStoppedAnimation(
                    ThemeConstants.primaryBlue,
                  ),
                  minHeight: 4,
                ),
              ),
            ),
            if (widget.progress > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${(widget.progress * 100).round()}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ThemeConstants.primaryBlue,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
