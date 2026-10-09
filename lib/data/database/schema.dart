import 'package:sqflite_common/sqlite_api.dart';

/// New versions must add a migration; never recreate a user's database.
abstract final class Schema {
  static const version = 1;

  static Future<void> create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE diary_entries (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT,
        body TEXT NOT NULL,
        diary_date TEXT NOT NULL CHECK (
          diary_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX diary_active_date ON diary_entries(diary_date)
      WHERE deleted_at IS NULL
    ''');
    await db.execute('''
      CREATE INDEX diary_deleted_at ON diary_entries(deleted_at DESC)
      WHERE deleted_at IS NOT NULL
    ''');
    await db.execute('''
      CREATE TABLE tasks (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL CHECK (length(trim(title)) > 0),
        notes TEXT,
        task_type TEXT NOT NULL CHECK (
          task_type IN ('DAY', 'MONTH', 'YEAR', 'CUSTOM')),
        period_start TEXT NOT NULL CHECK (
          period_start GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
        period_end_exclusive TEXT NOT NULL CHECK (
          period_end_exclusive GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
        is_completed INTEGER NOT NULL DEFAULT 0 CHECK (is_completed IN (0, 1)),
        completed_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        CHECK (period_start < period_end_exclusive),
        CHECK ((is_completed = 0 AND completed_at IS NULL)
          OR (is_completed = 1 AND completed_at IS NOT NULL))
      )
    ''');
    await db.execute('''
      CREATE INDEX tasks_active_period ON tasks(task_type, period_start)
      WHERE deleted_at IS NULL
    ''');
  }

  static Future<void> upgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // Add sequential, transactional migrations here when version 2 is defined.
    // Failing explicitly is safer than silently advancing an unknown schema.
    throw StateError('No migration from $oldVersion to $newVersion');
  }

  static Future<void> downgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    throw StateError(
      'Database downgrade is not supported: $oldVersion → $newVersion',
    );
  }
}
