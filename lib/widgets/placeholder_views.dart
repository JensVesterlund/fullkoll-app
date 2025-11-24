import 'package:flutter/material.dart';

class EmptyPlaceholder extends StatelessWidget {
  const EmptyPlaceholder({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.primaryLabel,
    this.onPrimaryPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? primaryLabel;
  final VoidCallback? onPrimaryPressed;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 72, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              if (primaryLabel != null && onPrimaryPressed != null) ...[
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: onPrimaryPressed,
                  child: Text(primaryLabel!),
                ),
              ],
            ],
          ),
        ),
      );
}

class ErrorPlaceholder extends StatelessWidget {
  const ErrorPlaceholder({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel,
  });

  final String message;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    assert(onRetry == null || retryLabel != null, 'retryLabel is required when onRetry is provided');
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                child: Text(retryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LoadingPlaceholder extends StatelessWidget {
  const LoadingPlaceholder({
    super.key,
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}