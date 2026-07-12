import 'package:flutter/material.dart';

import '../../core/constants/theme_constants.dart';
import '../../data/models/document_block.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// EQUATION RENDERER
// ═══════════════════════════════════════════════════════════════════════════════
//
// This renderer is dependency-free so the app can compile even when external
// math-rendering packages are unavailable in the local cache.
// It still preserves the existing UI states:
//   - inline equations
//   - block equations
//   - LaTeX/OMML fallbacks
//
// When a real math renderer is added back later, only this file needs to change.

class EquationRenderer extends StatelessWidget {
  final EquationBlock block;

  const EquationRenderer({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    if (!block.hasLatex) return _OmmlPlaceholder(block: block);

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: block.isInline ? 0 : 14,
        horizontal: 4,
      ),
      child: block.isInline
          ? _InlineEquation(latex: block.latex!)
          : _BlockEquation(latex: block.latex!, rawOmml: block.rawOmml),
    );
  }
}

class _BlockEquation extends StatelessWidget {
  final String latex;
  final String rawOmml;

  const _BlockEquation({required this.latex, required this.rawOmml});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark
            ? ThemeConstants.equationBgDark
            : ThemeConstants.equationBgLight,
        borderRadius: BorderRadius.circular(ThemeConstants.radiusSm),
        border: Border.all(
          color: isDark
              ? ThemeConstants.equationBorderDark
              : ThemeConstants.equationBorderLight,
          width: 1.5,
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(
            latex,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              height: 1.2,
              fontFamily: 'monospace',
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineEquation extends StatelessWidget {
  final String latex;

  const _InlineEquation({required this.latex});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark
            ? ThemeConstants.equationBgDark
            : ThemeConstants.equationBgLight,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDark
              ? ThemeConstants.equationBorderDark
              : ThemeConstants.equationBorderLight,
          width: 1,
        ),
      ),
      child: SelectableText(
        latex,
        style: TextStyle(
          fontSize: 13,
          height: 1.1,
          fontFamily: 'monospace',
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _LatexErrorFallback extends StatefulWidget {
  final String latex;
  final String error;
  final bool isInline;

  const _LatexErrorFallback({
    required this.latex,
    required this.error,
    this.isInline = false,
  });

  @override
  State<_LatexErrorFallback> createState() => _LatexErrorFallbackState();
}

class _LatexErrorFallbackState extends State<_LatexErrorFallback> {
  bool _showLatex = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (widget.isInline) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          '⚠ equation',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.error,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(ThemeConstants.radiusSm),
        border: Border.all(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Equation render error',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _showLatex = !_showLatex),
                child: Text(
                  _showLatex ? 'Hide LaTeX' : 'Show LaTeX',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? ThemeConstants.primaryBlueLight
                        : ThemeConstants.primaryBlue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
          if (_showLatex) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  widget.latex,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.error,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OmmlPlaceholder extends StatefulWidget {
  final EquationBlock block;

  const _OmmlPlaceholder({required this.block});

  @override
  State<_OmmlPlaceholder> createState() => _OmmlPlaceholderState();
}

class _OmmlPlaceholderState extends State<_OmmlPlaceholder> {
  bool _showOmml = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? ThemeConstants.equationBgDark : ThemeConstants.equationBgLight,
          border: Border.all(
            color: isDark ? ThemeConstants.equationBorderDark : ThemeConstants.equationBorderLight,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(ThemeConstants.radiusSm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('⚗', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.block.isInline
                        ? 'Inline equation (conversion pending)'
                        : 'Mathematical equation (conversion pending)',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? ThemeConstants.primaryBlueLight : ThemeConstants.primaryBlue,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _showOmml = !_showOmml),
                  child: Text(
                    _showOmml ? 'Hide' : 'OMML',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
            if (_showOmml) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText(
                    widget.block.rawOmml,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
