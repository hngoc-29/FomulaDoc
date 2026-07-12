import 'package:flutter/material.dart';

/// Floating chip in the bottom-right corner showing scroll progress.
///
/// Fades in while scrolling and auto-hides after 2 seconds of inactivity.
class ScrollPositionIndicator extends StatefulWidget {
  final ScrollController controller;

  const ScrollPositionIndicator({super.key, required this.controller});

  @override
  State<ScrollPositionIndicator> createState() =>
      _ScrollPositionIndicatorState();
}

class _ScrollPositionIndicatorState extends State<ScrollPositionIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;

  double _progress = 0.0;
  bool   _visible  = false;
  bool   _atBottom = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!widget.controller.hasClients) return;
    final pos      = widget.controller.position;
    final maxScroll = pos.maxScrollExtent;
    if (maxScroll <= 0) return;

    final frac  = (pos.pixels / maxScroll).clamp(0.0, 1.0);
    final atBot = pos.pixels >= maxScroll - 4;

    setState(() {
      _progress = frac;
      _atBottom = atBot;
    });

    if (!_visible) {
      _visible = true;
      _fadeCtrl.forward();
    }

    // Auto-hide after 2 s of inactivity
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _visible) {
        _fadeCtrl.reverse().then((_) {
          if (mounted) setState(() => _visible = false);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: _Chip(progress: _progress, atBottom: _atBottom),
    );
  }
}

// ─── Chip widget ──────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final double progress;
  final bool   atBottom;

  const _Chip({required this.progress, required this.atBottom});

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final pct      = (progress * 100).round();
    final label    = atBottom ? 'End' : '$pct%';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color:       Colors.black.withValues(alpha: 0.15),
            blurRadius:  4,
            offset:      const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mini progress arc
          SizedBox(
            width:  14,
            height: 14,
            child: CircularProgressIndicator(
              value:      progress,
              strokeWidth: 2,
              color: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize:   12,
              fontWeight: FontWeight.w600,
              color:      Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
