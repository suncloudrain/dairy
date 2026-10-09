import 'package:sqflite_common/sqlite_api.dart';

import 'schema.dart';

final class AppDatabase {
  AppDatabase._(this.connection);

  /// Infrastructure only. UI receives repositories, never this connection.
  final Database connection;

  static Future<AppDatabase> open({
    required DatabaseFactory factory,
    required String path,
  }) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: Schema.version,
        singleInstance: false,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: Schema.create,
        onUpgrade: Schema.upgrade,
        onDowngrade: Schema.downgrade,
      ),
    );
    return AppDatabase._(db);
  }

  Future<void> close() => connection.close();
}
