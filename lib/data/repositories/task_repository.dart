import 'package:uuid/uuid.dart';

import '../../models/task.dart';
import '../../models/task_period.dart';
import '../database/app_database.dart';
import '../database/task_queries.dart';
import 'record_values.dart';
import 'repository_exception.dart';

final class TaskRepository {
  TaskRepository(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DateTime Function() _clock;
  String newId() => const Uuid().v4();

  Future<Task?> findById(String id) async {
    final task = await TaskQueries.find(_database.connection, id);
    return task != null && !task.isDeleted ? task : null;
  }

  Future<List<Task>> list({
    required TaskType type,
    TaskPeriod? period,
    bool? completed,
  }) {
    if (period != null && period.type != type) {
      throw const RepositoryException(RepositoryError.invalidInput);
    }
    return TaskQueries.list(
      _database.connection,
      type: type,
      period: period,
      completed: completed,
    );
  }

  /// Reuse the draft ID on retry; editing content never changes completion state.
  Future<Task> save({
    required String id,
    required String title,
    String? notes,
    required TaskPeriod period,
  }) async {
    validateRecordId(id);
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw const RepositoryException(RepositoryError.invalidInput);
    }
    final normalizedNotes = optionalText(notes);
    return _database.connection.transaction((tx) async {
      final existing = await TaskQueries.find(tx, id);
      if (existing?.isDeleted ?? false) {
        throw const RepositoryException(RepositoryError.recordUnavailable);
      }
      if (existing != null &&
          existing.title == normalizedTitle &&
          existing.notes == normalizedNotes &&
          existing.period.type == period.type &&
          existing.period.start == period.start &&
          existing.period.endExclusive == period.endExclusive) {
        return existing;
      }
      final now = _clock().toUtc();
      if (existing == null) {
        await TaskQueries.insert(
          tx,
          Task(
            id: id,
            title: normalizedTitle,
            notes: normalizedNotes,
            period: period,
            isCompleted: false,
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else {
        await TaskQueries.updateContent(
          tx,
          id: id,
          title: normalizedTitle,
          notes: normalizedNotes,
          period: period,
          now: now,
        );
      }
      return (await TaskQueries.find(tx, id))!;
    });
  }

  Future<Task> setCompleted(String id, bool completed) =>
      _database.connection.transaction((tx) async {
        final task = await TaskQueries.find(tx, id);
        if (task == null || task.isDeleted) {
          throw const RepositoryException(RepositoryError.recordUnavailable);
        }
        if (task.isCompleted == completed) return task;
        await TaskQueries.setCompleted(
          tx,
          id,
          completed: completed,
          now: _clock().toUtc(),
        );
        return (await TaskQueries.find(tx, id))!;
      });

  Future<void> softDelete(String id) =>
      _database.connection.transaction((tx) async {
        final task = await TaskQueries.find(tx, id);
        if (task == null) {
          throw const RepositoryException(RepositoryError.recordUnavailable);
        }
        if (task.isDeleted) return;
        await TaskQueries.softDelete(tx, id, _clock().toUtc());
      });
}
