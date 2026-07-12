import 'package:flutter/material.dart';

import '../../../../core/constants/theme_constants.dart';

/// Shown when a document fails to load or parse.
class ViewerErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onPickAnother;

  const ViewerErrorWidget({
    super.key,
    required this.message,
    this.onRetry,
    this.onPickAnother,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.error_outline,
                size: 36,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Không thể mở tài liệu',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            if (onRetry != null)
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            if (onPickAnother != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onPickAnother,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Mở file khác'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ThemeConstants.primaryBlue,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
