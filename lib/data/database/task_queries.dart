import 'package:sqflite_common/sqlite_api.dart';

import '../../models/local_date.dart';
import '../../models/task.dart';
import '../../models/task_period.dart';

abstract final class TaskQueries {
  static Task decode(Map<String, Object?> row) => Task(
    id: row['id']! as String,
    title: row['title']! as String,
    notes: row['notes'] as String?,
    period: TaskPeriod(
      type: TaskType.fromDatabase(row['task_type']! as String),
      start: LocalDate.parse(row['period_start']! as String),
      endExclusive: LocalDate.parse(row['period_end_exclusive']! as String),
    ),
    isCompleted: row['is_completed'] == 1,
    completedAt: _time(row['completed_at']),
    createdAt: _time(row['created_at'])!,
    updatedAt: _time(row['updated_at'])!,
    deletedAt: _time(row['deleted_at']),
  );

  static DateTime? _time(Object? value) => value == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(value as int, isUtc: true);

  static Future<Task?> find(DatabaseExecutor db, String id) async {
    final rows = await db.query('tasks', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : decode(rows.single);
  }

  static Future<List<Task>> list(
    DatabaseExecutor db, {
    required TaskType type,
    TaskPeriod? period,
    bool? completed,
  }) async {
    final clauses = ['deleted_at IS NULL', 'task_type = ?'];
    final args = <Object?>[type.databaseValue];
    if (period != null) {
      clauses.add('period_start = ? AND period_end_exclusive = ?');
      args.addAll([period.start.toString(), period.endExclusive.toString()]);
    }
    if (completed != null) {
      clauses.add('is_completed = ?');
      args.add(completed ? 1 : 0);
    }
    final rows = await db.query(
      'tasks',
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'is_completed ASC, created_at ASC, id ASC',
    );
    return rows.map(decode).toList(growable: false);
  }

  static Map<String, Object?> _content(
    String title,
    String? notes,
    TaskPeriod period,
    DateTime now,
  ) => {
    'title': title,
    'notes': notes,
    'task_type': period.type.databaseValue,
    'period_start': period.start.toString(),
    'period_end_exclusive': period.endExclusive.toString(),
    'updated_at': now.millisecondsSinceEpoch,
  };

  static Future<void> insert(DatabaseExecutor db, Task task) async {
    await db.insert('tasks', {
      ..._content(task.title, task.notes, task.period, task.updatedAt),
      'id': task.id,
      'created_at': task.createdAt.millisecondsSinceEpoch,
      'is_completed': task.isCompleted ? 1 : 0,
      'completed_at': task.completedAt?.millisecondsSinceEpoch,
      'deleted_at': task.deletedAt?.millisecondsSinceEpoch,
    });
  }

  static Future<void> updateContent(
    DatabaseExecutor db, {
    required String id,
    required String title,
    required String? notes,
    required TaskPeriod period,
    required DateTime now,
  }) async {
    await db.update(
      'tasks',
      _content(title, notes, period, now),
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
  }

  static Future<void> setCompleted(
    DatabaseExecutor db,
    String id, {
    required bool completed,
    required DateTime now,
  }) async {
    await db.update(
      'tasks',
      {
        'is_completed': completed ? 1 : 0,
        'completed_at': completed ? now.millisecondsSinceEpoch : null,
        'updated_at': now.millisecondsSinceEpoch,
      },
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
  }

  static Future<void> softDelete(
    DatabaseExecutor db,
    String id,
    DateTime now,
  ) async {
    await db.update(
      'tasks',
      {
        'deleted_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
      },
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
  }
}
