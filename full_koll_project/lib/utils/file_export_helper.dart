import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import 'file_export_helper_stub.dart'
    if (dart.library.html) 'file_export_helper_web.dart';

class FileExportHelper {
  const FileExportHelper._();

  static Future<void> deliver({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (kIsWeb) {
      await downloadWebFile(bytes: bytes, fileName: fileName, mimeType: mimeType);
      return;
    }

    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
      subject: 'Full Koll export',
      text: 'Export från Full Koll',
    );
  }
}