import 'dart:async';

import 'package:flutter/material.dart';

import '../services/analytics.dart';

/// Wraps the app with a lightweight boundary that surfaces fatal errors to the user
/// while still letting the underlying screen remain visible for context.
class GlobalErrorBoundary extends StatefulWidget {
  final Widget child;
  final Duration autoDismissAfter;

  const GlobalErrorBoundary({
    super.key,
    required this.child,
    this.autoDismissAfter = const Duration(seconds: 8),
  });

  @override
  State<GlobalErrorBoundary> createState() => _GlobalErrorBoundaryState();
}

class _GlobalErrorBoundaryState extends State<GlobalErrorBoundary> {
  LoggedError? _current;
  Timer? _autoDismissTimer;

  void _listen() {
    final active = ErrorReporter.instance.current;
    if (mounted) {
      setState(() => _current = active);
    }
    _autoDismissTimer?.cancel();
    if (active != null) {
      _autoDismissTimer = Timer(widget.autoDismissAfter, () {
        ErrorReporter.instance.dismissCurrent();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    ErrorReporter.instance.addListener(_listen);
    _listen();
  }

  @override
  void dispose() {
    ErrorReporter.instance.removeListener(_listen);
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overlay = _current == null
        ? const SizedBox.shrink()
        : SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Ett oväntat fel inträffade',
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _current!.displayHint,
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _current!.error.toString(),
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Stäng',
                                onPressed: ErrorReporter.instance.dismissCurrent,
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (BreadcrumbBuffer.instance.items.isNotEmpty)
                            TextButton.icon(
                              onPressed: () {
                                final entries = BreadcrumbBuffer.instance.items
                                    .map((e) => '${e.timestamp.toIso8601String()} – ${e.message} ${e.context}')
                                    .join('\n');
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('Senaste händelser'),
                                    content: SingleChildScrollView(child: Text(entries)),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Stäng')),
                                    ],
                                  ),
                                );
                              },
                              icon: const Icon(Icons.list_alt_outlined),
                              label: const Text('Visa händelselogg'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        overlay,
      ],
    );
  }
}