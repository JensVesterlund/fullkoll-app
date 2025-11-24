import 'package:flutter/material.dart';
import '../utils/connectivity.dart';

class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  late final ConnectivityService _connectivity;

  @override
  void initState() {
    super.initState();
    _connectivity = ConnectivityService();
  }

  @override
  void dispose() {
    _connectivity.disposeService();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _connectivity,
      builder: (context, _) {
        if (_connectivity.isOnline) {
          return const SizedBox.shrink();
        }
        final color = Theme.of(context).colorScheme.error;
        return Material(
          color: color.withValues(alpha: 0.08),
          child: SafeArea(
            bottom: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.wifi_off, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Offline – försöker igen',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
