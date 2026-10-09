import 'package:dairy/data/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<AppDatabase> openTestDatabase({String path = inMemoryDatabasePath}) {
  sqfliteFfiInit();
  return AppDatabase.open(factory: databaseFactoryFfiNoIsolate, path: path);
}
