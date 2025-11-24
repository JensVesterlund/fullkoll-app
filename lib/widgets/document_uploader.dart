import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../document_storage.dart';

class DocumentUploadPayload {
  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final bool isPdf;

  DocumentUploadPayload({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.isPdf,
  });
}

class DocumentUploadState {
  final DocumentUploadPayload? pendingFile;
  final bool removeExisting;

  const DocumentUploadState({this.pendingFile, this.removeExisting = false});

  static const empty = DocumentUploadState();
}

class DocumentUploader extends StatefulWidget {
  final String uploadLabel;
  final String? initialUrl;
  final String? initialFileName;
  final ValueChanged<DocumentUploadState> onChanged;
  final Future<void> Function(Uint8List bytes, String fileName)? onOcr;

  const DocumentUploader({
    super.key,
    required this.uploadLabel,
    required this.onChanged,
    this.initialUrl,
    this.initialFileName,
    this.onOcr,
  });

  @override
  State<DocumentUploader> createState() => _DocumentUploaderState();
}

class _DocumentUploaderState extends State<DocumentUploader> {
  static const List<String> _allowedExtensions = ['jpg', 'jpeg', 'png', 'heic', 'pdf'];

  StoredDocument? _storedDocument;
  DocumentUploadPayload? _pendingPayload;
  bool _removeExisting = false;
  bool _isLoadingInitial = false;
  bool _isOcrRunning = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _loadInitialDocument();
  }

  @override
  void didUpdateWidget(covariant DocumentUploader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialUrl != widget.initialUrl && widget.initialUrl != null) {
      _loadInitialDocument();
    }
  }

  Future<void> _loadInitialDocument() async {
    if (widget.initialUrl == null) return;
    setState(() {
      _isLoadingInitial = true;
    });
    final doc = await DocumentStorage.fetchDocument(widget.initialUrl);
    if (!mounted) return;
    setState(() {
      _storedDocument = doc;
      _isLoadingInitial = false;
    });
  }

  Future<void> _pickFile() async {
    setState(() {
      _statusMessage = null;
      _statusIsError = false;
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      withData: true,
    );

    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.first;
    if (file.bytes == null) {
      _showError('Fildata kunde inte läsas. Försök igen.');
      return;
    }

    final bytes = file.bytes!;
    if (bytes.length > DocumentStorage.maxBytes) {
      _showError('Filen är större än 10 MB.');
      return;
    }

    final ext = _extensionOf(file.name);
    if (!_allowedExtensions.contains(ext)) {
      _showError('Filformatet stöds inte.');
      return;
    }

    final mimeType = _mimeTypeFor(ext);
    final payload = DocumentUploadPayload(
      bytes: bytes,
      fileName: file.name,
      mimeType: mimeType,
      isPdf: ext == 'pdf',
    );

    setState(() {
      _pendingPayload = payload;
      _removeExisting = false;
      _statusMessage = 'Fil uppladdad ✅';
      _statusIsError = false;
    });

    widget.onChanged(DocumentUploadState(pendingFile: payload));

    if (widget.onOcr != null) {
      setState(() => _isOcrRunning = true);
      try {
        await widget.onOcr!(bytes, file.name);
      } finally {
        if (mounted) {
          setState(() => _isOcrRunning = false);
        }
      }
    }
  }

  void _clearPending() {
    setState(() {
      _pendingPayload = null;
      _statusMessage = null;
      _statusIsError = false;
    });
    widget.onChanged(const DocumentUploadState());
  }

  void _removeExistingDocument() {
    setState(() {
      _pendingPayload = null;
      _storedDocument = null;
      _removeExisting = true;
      _statusMessage = 'Fil borttagen – sparas efter bekräftelse';
      _statusIsError = false;
    });
    widget.onChanged(const DocumentUploadState(removeExisting: true));
  }

  void _undoRemoval() {
    setState(() {
      _removeExisting = false;
      _statusMessage = null;
    });
    widget.onChanged(const DocumentUploadState());
    if (widget.initialUrl != null) {
      _loadInitialDocument();
    }
  }

  void _showError(String message) {
    setState(() {
      _statusMessage = 'Fel vid uppladdning ❌ – $message';
      _statusIsError = true;
    });
    widget.onChanged(const DocumentUploadState());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusIsError ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: _pickFile,
          icon: const Icon(Icons.upload_file_outlined),
          label: Text(widget.uploadLabel),
        ),
        const SizedBox(height: 12),
        if (_isLoadingInitial)
          const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
        if (!_isLoadingInitial) _buildPreviewSection(context),
        if (_isOcrRunning) ...[
          const SizedBox(height: 8),
          Row(
            children: const [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Expanded(child: Text('Bearbetar dokument för OCR...')),
            ],
          ),
        ],
        if (_statusMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _statusMessage!,
            style: theme.textTheme.bodySmall?.copyWith(color: statusColor, fontWeight: _statusIsError ? FontWeight.w600 : FontWeight.w500),
          ),
        ],
      ],
    );
  }

  Widget _buildPreviewSection(BuildContext context) {
    final hasPending = _pendingPayload != null;
    final hasExisting = !_removeExisting && _storedDocument != null;

    if (!hasPending && !hasExisting) {
      if (_removeExisting) {
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _undoRemoval,
            icon: const Icon(Icons.undo),
            label: const Text('Ångra borttagning'),
          ),
        );
      }

      if (widget.initialUrl != null && !_removeExisting) {
        // Vi kan inte läsa dokumentet men vill visa att det finns.
        return Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _removeExistingDocument,
            icon: const Icon(Icons.delete_outline),
            label: Text('Ta bort ${widget.initialFileName ?? 'fil'}'),
          ),
        );
      }

      return const SizedBox.shrink();
    }

    final payload = _pendingPayload;
    final stored = hasPending ? null : _storedDocument;
    final fileName = payload?.fileName ?? stored?.name ?? widget.initialFileName ?? 'dokument';
    final isPdf = payload?.isPdf ?? stored?.isPdf ?? false;
    final isImage = payload?.mimeType.startsWith('image/') ?? stored?.isImage ?? false;

    final preview = isImage
        ? Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            clipBehavior: Clip.antiAlias,
            height: 160,
            child: Image.memory(
              payload?.bytes ?? stored!.bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildUnsupportedPreview(fileName),
            ),
          )
        : _buildFileTile(context, fileName, isPdf);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        preview,
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            if (hasPending)
              TextButton.icon(
                onPressed: _clearPending,
                icon: const Icon(Icons.close),
                label: const Text('Rensa val'),
              )
            else
              TextButton.icon(
                onPressed: _removeExistingDocument,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Ta bort fil'),
              ),
            if (_removeExisting)
              TextButton.icon(
                onPressed: _undoRemoval,
                icon: const Icon(Icons.undo),
                label: const Text('Ångra'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildFileTile(BuildContext context, String fileName, bool isPdf) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      tileColor: Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Icon(isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file_outlined, color: Theme.of(context).colorScheme.primary),
      title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: TextButton(
        onPressed: () => _showDocumentDialog(context, fileName, isPdf: isPdf),
        child: const Text('Visa fil'),
      ),
    );
  }

  Widget _buildUnsupportedPreview(String fileName) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image_not_supported_outlined, size: 32),
            const SizedBox(height: 8),
            Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            const Text('Förhandsvisning ej tillgänglig'),
          ],
        ),
      ),
    );
  }

  void _showDocumentDialog(BuildContext context, String fileName, {required bool isPdf}) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final stored = _storedDocument;
        final payload = _pendingPayload;
        final bytes = payload?.bytes ?? stored?.bytes;

        Widget body;
        if (!isPdf && bytes != null) {
          body = Image.memory(bytes, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Text('Kunde inte visa filen.'));
        } else {
          final message = isPdf
              ? 'PDF-förhandsvisning stöds inte i denna version.\nFil: $fileName'
              : 'Kunde inte visa filen.';
          body = Text(message);
        }

        return AlertDialog(
          title: Text(fileName),
          content: SizedBox(width: 320, child: body),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Stäng')),
          ],
        );
      },
    );
  }

  String _extensionOf(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    return dotIndex == -1 ? '' : fileName.substring(dotIndex + 1).toLowerCase();
  }

  String _mimeTypeFor(String extension) {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'heic':
        return 'image/heic';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }
}