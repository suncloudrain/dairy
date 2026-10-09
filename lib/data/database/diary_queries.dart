import 'package:sqflite_common/sqlite_api.dart';

import '../../models/diary_entry.dart';
import '../../models/local_date.dart';

abstract final class DiaryQueries {
  static DiaryEntry decode(Map<String, Object?> row) => DiaryEntry(
    id: row['id']! as String,
    title: row['title'] as String?,
    body: row['body']! as String,
    date: LocalDate.parse(row['diary_date']! as String),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row['created_at']! as int,
      isUtc: true,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      row['updated_at']! as int,
      isUtc: true,
    ),
    deletedAt: row['deleted_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            row['deleted_at']! as int,
            isUtc: true,
          ),
  );

  static Future<DiaryEntry?> find(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      'diary_entries',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : decode(rows.single);
  }

  static Future<DiaryEntry?> forDate(
    DatabaseExecutor db,
    LocalDate date,
  ) async {
    final rows = await db.query(
      'diary_entries',
      where: 'diary_date = ? AND deleted_at IS NULL',
      whereArgs: [date.toString()],
    );
    return rows.isEmpty ? null : decode(rows.single);
  }

  static Future<List<DiaryEntry>> list(
    DatabaseExecutor db, {
    required bool deleted,
  }) async {
    final rows = await db.query(
      'diary_entries',
      where: deleted ? 'deleted_at IS NOT NULL' : 'deleted_at IS NULL',
      orderBy: deleted ? 'deleted_at DESC, id ASC' : 'diary_date DESC, id ASC',
    );
    return rows.map(decode).toList(growable: false);
  }

  static Future<void> insert(DatabaseExecutor db, DiaryEntry entry) async {
    await db.insert('diary_entries', {
      'id': entry.id,
      'title': entry.title,
      'body': entry.body,
      'diary_date': entry.date.toString(),
      'created_at': entry.createdAt.millisecondsSinceEpoch,
      'updated_at': entry.updatedAt.millisecondsSinceEpoch,
      'deleted_at': entry.deletedAt?.millisecondsSinceEpoch,
    });
  }

  static Future<void> updateContent(
    DatabaseExecutor db, {
    required String id,
    required String? title,
    required String body,
    required LocalDate date,
    required DateTime now,
  }) async {
    await db.update(
      'diary_entries',
      {
        'title': title,
        'body': body,
        'diary_date': date.toString(),
        'updated_at': now.millisecondsSinceEpoch,
      },
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
  }

  static Future<void> setDeleted(
    DatabaseExecutor db,
    String id, {
    required bool deleted,
    required DateTime now,
  }) async {
    await db.update(
      'diary_entries',
      {
        'deleted_at': deleted ? now.millisecondsSinceEpoch : null,
        'updated_at': now.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
