import 'dart:io' as io;
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';

class PlatformStorage {
  /// Uploads a file (binary) to the given bucket/folder and returns a signed URL (7 days).
  ///
  /// file can be:
  /// - io.File (preferred on mobile/desktop)
  /// - Uint8List (we'll upload bytes directly)
  ///
  /// If [file] is Uint8List you should provide a [fileName] so we can preserve extension.
  Future<String> upload({
    required Object file,
    required String bucket,
    required String folder,
    String? fileName,
  }) async {
    final userId = supa.auth.currentUser!.id;
    final now = DateTime.now().millisecondsSinceEpoch;

    String resolvedName;
    Uint8List bytes;

    if (file is io.File) {
      resolvedName = _basename(file.path);
      bytes = await file.readAsBytes();
    } else if (file is Uint8List) {
      resolvedName = (fileName != null && fileName.isNotEmpty) ? fileName : 'upload_$now.bin';
      bytes = file;
    } else {
      throw ArgumentError('Unsupported file type: ${file.runtimeType}. Provide io.File or Uint8List.');
    }

    final ext = _extensionOf(resolvedName);
    final objectPath = '$folder/${now}$ext';

    // ignore: avoid_print
    print('[SB][storage] upload -> bucket=$bucket path=$objectPath bytes=${bytes.length} by=$userId');

    await supa.storage.from(bucket).uploadBinary(objectPath, bytes);

    final signed = await supa.storage.from(bucket).createSignedUrl(objectPath, 60 * 60 * 24 * 7);

    // ignore: avoid_print
    print('[SB][storage] signed-url ok -> ${signed.substring(0, signed.length > 60 ? 60 : signed.length)}...');
    return signed;
  }

  String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot == -1 ? '' : fileName.substring(dot);
  }

  String _basename(String path) {
    final sep = path.lastIndexOf(io.Platform.pathSeparator);
    return sep == -1 ? path : path.substring(sep + 1);
  }
}
