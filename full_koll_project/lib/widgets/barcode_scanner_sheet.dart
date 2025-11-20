import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_dart_scan/qr_code_dart_scan.dart';

import '../theme.dart';
import '../i18n/app_localizations.dart';

class BarcodeScannerSheet extends StatefulWidget {
  final String title;
  final String description;
  final String confirmLabel;

  const BarcodeScannerSheet({
    super.key,
    required this.title,
    required this.description,
    this.confirmLabel = 'Använd resultat',
  });

  @override
  State<BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<BarcodeScannerSheet> {
  bool _isProcessing = false;
  String? _error;
  bool _hasPermission = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    final status = await Permission.camera.status;
    if (status.isGranted) return;
    final result = await Permission.camera.request();
    setState(() => _hasPermission = result.isGranted);
  }

  void _handleCapture(Result result) {
    if (_isProcessing || result.text == null || result.text!.isEmpty) return;
    setState(() => _isProcessing = true);
    Navigator.of(context).pop(result.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.description,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 16),
            if (!_hasPermission)
              _buildMessage(
                context,
                icon: Icons.lock_outline,
                color: Colors.orange,
                text: l10n.translate('scanner.permission.cameraBlocked'),
              )
            else if (_error != null)
              _buildMessage(
                context,
                icon: Icons.videocam_off_outlined,
                color: Colors.orange,
                text: _error!,
              )
            else if (kIsWeb)
              _buildMessage(
                context,
                icon: Icons.desktop_windows_outlined,
                color: AppColors.warning,
                text: l10n.translate('scanner.web.unsupported'),
              )
            else
              AspectRatio(
                aspectRatio: 3 / 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      QRCodeDartScanView(
                        typeScan: TypeScan.live,
                        resolutionPreset: QRCodeDartScanResolutionPreset.high,
                        onCapture: _handleCapture,
                        onCameraError: (error) {
                          final friendly = _mapCameraError(context, error);
                          setState(() => _error = friendly);
                        },
                      ),
                      if (_isProcessing)
                        Container(
                          color: Colors.black45,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(null),
              icon: const Icon(Icons.image_search_outlined),
              label: Text(l10n.translate('scanner.pickImageInstead')),
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop('7350091234567'),
                icon: const Icon(Icons.qr_code_2),
                label: Text(l10n.translate('scanner.useDemoCode')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(BuildContext context, {required IconData icon, required Color color, required String text}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color))),
        ],
      ),
    );
  }

  String _mapCameraError(BuildContext context, String error) {
    final l10n = AppLocalizations.of(context);
    if (error.contains('No camera found')) {
      return l10n.translate('scanner.permission.cameraBlocked');
    }
    if (error.contains('NotAllowedError')) {
      return l10n.translate('scanner.permission.cameraBlocked');
    }
    return error;
  }
}
