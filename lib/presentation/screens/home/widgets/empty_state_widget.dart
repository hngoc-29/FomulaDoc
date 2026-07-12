import 'package:flutter/material.dart';

import '../../../../core/constants/theme_constants.dart';

/// Shown on the home screen when no recent files exist.
class EmptyStateWidget extends StatelessWidget {
  final VoidCallback onOpenFile;

  const EmptyStateWidget({super.key, required this.onOpenFile});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: ThemeConstants.primaryBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.description_outlined,
                size: 48,
                color: ThemeConstants.primaryBlue,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No documents yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              'Open a .docx file to get started.\n'
              'FormulaDoc renders Word equations correctly,\n'
              'unlike other mobile readers.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                    height: 1.6,
                  ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onOpenFile,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Open Document'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 40),
            // Feature highlights
            const _FeatureRow(
              icon: Icons.functions,
              label: 'Correct equation rendering (OMML → LaTeX)',
            ),
            const SizedBox(height: 10),
            const _FeatureRow(
              icon: Icons.table_chart_outlined,
              label: 'Tables with merged cells',
            ),
            const SizedBox(height: 10),
            const _FeatureRow(
              icon: Icons.image_outlined,
              label: 'Embedded images',
            ),
            const SizedBox(height: 10),
            const _FeatureRow(
              icon: Icons.dark_mode_outlined,
              label: 'Dark mode support',
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: ThemeConstants.primaryBlue.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.65),
              ),
        ),
      ],
    );
  }
}
