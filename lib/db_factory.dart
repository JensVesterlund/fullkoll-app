import 'package:sembast/sembast.dart';

// Delegate to platform-specific implementation via conditional import
import 'db_factory_web.dart' if (dart.library.io) 'db_factory_io.dart' as impl;

Future<Database> openDatabaseCrossPlatform(String name) => impl.openDatabaseCrossPlatform(name);

Future<void> deleteDatabaseCrossPlatform(String name) => impl.deleteDatabaseCrossPlatform(name);
