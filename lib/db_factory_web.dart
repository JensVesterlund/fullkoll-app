import 'package:sembast/sembast.dart';
import 'package:sembast_web/sembast_web.dart';

Future<Database> openDatabaseCrossPlatform(String name) async {
  // Web IndexedDB
  // ignore: avoid_print
  print('[DB] Using sembast_web (IndexedDB)');
  return await databaseFactoryWeb.openDatabase(name);
}

Future<void> deleteDatabaseCrossPlatform(String name) async {
  await databaseFactoryWeb.deleteDatabase(name);
}
