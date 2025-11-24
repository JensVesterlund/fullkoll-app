// Cross-platform StorageService facade using conditional imports.
// Do not import this file from platform implementations.

import 'storage/storage_service_io.dart' if (dart.library.html) 'storage/storage_service_web.dart' as platform;

class StorageService {
  /// Delegates to platform-specific implementation.
  Future<String> upload({
    required Object file,
    required String bucket,
    required String folder,
    String? fileName,
  }) {
    return platform.PlatformStorage().upload(
      file: file,
      bucket: bucket,
      folder: folder,
      fileName: fileName,
    );
  }
}
