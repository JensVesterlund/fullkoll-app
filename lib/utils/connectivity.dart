// Platform-conditional import for connectivity service.
import 'connectivity_stub.dart'
    if (dart.library.html) 'connectivity_web.dart';

export 'connectivity_stub.dart'
    if (dart.library.html) 'connectivity_web.dart';
