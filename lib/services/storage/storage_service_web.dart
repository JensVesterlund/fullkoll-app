import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';

class PlatformStorage {
  /// Web-friendly upload that accepts bytes and optional [fileName].
  /// Returns a signed URL valid for 7 days.
  Future<String> upload({
    required Object file,
    required String bucket,
    required String folder,
    String? fileName,
  }) async {
    if (file is! Uint8List) {
      throw ArgumentError('On web, file must be Uint8List. Got: ${file.runtimeType}');
    }
    final userId = supa.auth.currentUser!.id;
    final now = DateTime.now().millisecondsSinceEpoch;
    final resolvedName = (fileName != null && fileName.isNotEmpty) ? fileName : 'upload_$now.bin';
    final ext = _extensionOf(resolvedName);
    final objectPath = '$folder/${now}$ext';

    // ignore: avoid_print
    print('[SB][storage][web] upload -> bucket=$bucket path=$objectPath bytes=${file.length} by=$userId');

    await supa.storage.from(bucket).uploadBinary(objectPath, file);

    final signed = await supa.storage.from(bucket).createSignedUrl(objectPath, 60 * 60 * 24 * 7);
    // ignore: avoid_print
    print('[SB][storage][web] signed-url ok -> ${signed.substring(0, signed.length > 60 ? 60 : signed.length)}...');
    return signed;
  }

  String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot == -1 ? '' : fileName.substring(dot);
  }
}
