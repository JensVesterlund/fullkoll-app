import 'dart:async';
import 'package:sembast/sembast.dart';
import 'db_factory.dart';

class AppDatabase {
  static Database? _db;
  static const String _dbName = 'full_koll';

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    // Cross-platform opening using conditional import implementation
    // ignore: avoid_print
    print('[DB] Opening Sembast (cross-platform)');
    return await openDatabaseCrossPlatform(_dbName);
  }

  // Convenience accessor for stores
  static StoreRef<String, Map<String, dynamic>> store(String name) => stringMapStoreFactory.store(name);

  // Helpers for common queries
  static Future<List<Map<String, dynamic>>> findAll(
    String storeName, {
    Filter? filter,
    List<SortOrder>? sortOrders,
  }) async {
    final db = await instance;
    final store = AppDatabase.store(storeName);
    final records = await store.find(db, finder: Finder(filter: filter, sortOrders: sortOrders));
    return records.map((e) => e.value).toList();
  }

  static Future<Map<String, dynamic>?> getById(String storeName, String id) async {
    final db = await instance;
    final store = AppDatabase.store(storeName);
    return await store.record(id).get(db);
  }

  static Future<void> put(String storeName, String id, Map<String, dynamic> value) async {
    final db = await instance;
    final store = AppDatabase.store(storeName);
    await store.record(id).put(db, value);
  }

  static Future<void> delete(String storeName, String id) async {
    final db = await instance;
    final store = AppDatabase.store(storeName);
    await store.record(id).delete(db);
  }

  static Future<int> deleteWhere(String storeName, Filter filter) async {
    final db = await instance;
    final store = AppDatabase.store(storeName);
    return await store.delete(db, finder: Finder(filter: filter));
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static Future<void> reset() async {
    await close();
    await deleteDatabaseCrossPlatform(_dbName);
  }
}
