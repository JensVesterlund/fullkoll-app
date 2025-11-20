import 'dart:io' show Directory;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openDatabaseCrossPlatform(String name) async {
  // Mobile/Desktop file-based database
  // ignore: avoid_print
  print('[DB] Using sembast_io (file)');
  final Directory dir = await getApplicationDocumentsDirectory();
  final String dbPath = '${dir.path}/$name.db';
  return await databaseFactoryIo.openDatabase(dbPath);
}

Future<void> deleteDatabaseCrossPlatform(String name) async {
  final Directory dir = await getApplicationDocumentsDirectory();
  final String dbPath = '${dir.path}/$name.db';
  await databaseFactoryIo.deleteDatabase(dbPath);
}
