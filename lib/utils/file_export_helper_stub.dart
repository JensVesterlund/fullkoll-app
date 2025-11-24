import 'dart:typed_data';

Future<void> downloadWebFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  throw UnsupportedError('Web file export is not supported on this platform');
}