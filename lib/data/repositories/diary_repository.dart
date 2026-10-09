import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../models/diary_entry.dart';
import '../../models/local_date.dart';
import '../database/app_database.dart';
import '../database/diary_queries.dart';
import 'record_values.dart';
import 'repository_exception.dart';

final class DiaryRepository {
  DiaryRepository(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DateTime Function() _clock;

  /// Allocate once when a draft starts, then reuse across saves and retries.
  /// Allocating an ID does not create a database row.
  String newId() => const Uuid().v4();

  Future<List<DiaryEntry>> listActive() =>
      DiaryQueries.list(_database.connection, deleted: false);
  Future<List<DiaryEntry>> listDeleted() =>
      DiaryQueries.list(_database.connection, deleted: true);
  Future<DiaryEntry?> findByDate(LocalDate date) =>
      DiaryQueries.forDate(_database.connection, date);

  Future<DiaryEntry?> findById(String id, {bool includeDeleted = false}) async {
    final entry = await DiaryQueries.find(_database.connection, id);
    return entry != null && (includeDeleted || !entry.isDeleted) ? entry : null;
  }

  Future<DiaryEntry> save({
    required String id,
    required LocalDate date,
    String? title,
    required String body,
  }) async {
    validateRecordId(id);
    final normalizedTitle = optionalText(title);
    try {
      return await _database.connection.transaction((tx) async {
        final existing = await DiaryQueries.find(tx, id);
        if (existing?.isDeleted ?? false) {
          throw const RepositoryException(RepositoryError.recordUnavailable);
        }
        if (existing != null &&
            existing.date == date &&
            existing.title == normalizedTitle &&
            existing.body == body) {
          return existing;
        }
        await _ensureDateAvailable(tx, date, id);
        final now = _clock().toUtc();
        if (existing == null) {
          await DiaryQueries.insert(
            tx,
            DiaryEntry(
              id: id,
              title: normalizedTitle,
              body: body,
              date: date,
              createdAt: now,
              updatedAt: now,
            ),
          );
        } else {
          await DiaryQueries.updateContent(
            tx,
            id: id,
            title: normalizedTitle,
            body: body,
            date: date,
            now: now,
          );
        }
        return (await DiaryQueries.find(tx, id))!;
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError('diary_entries.diary_date')) {
        throw const RepositoryException(RepositoryError.diaryDateConflict);
      }
      rethrow;
    }
  }

  /// The editor must flush its latest input before calling this operation.
  Future<void> softDelete(String id) => _database.connection.transaction((
    tx,
  ) async {
    final entry = await DiaryQueries.find(tx, id);
    if (entry == null) {
      throw const RepositoryException(RepositoryError.recordUnavailable);
    }
    if (entry.isDeleted) return;
    await DiaryQueries.setDeleted(tx, id, deleted: true, now: _clock().toUtc());
  });

  Future<DiaryEntry> restore(String id) async {
    try {
      return await _database.connection.transaction((tx) async {
        final entry = await DiaryQueries.find(tx, id);
        if (entry == null) {
          throw const RepositoryException(RepositoryError.recordUnavailable);
        }
        if (!entry.isDeleted) return entry;
        await _ensureDateAvailable(tx, entry.date, id);
        await DiaryQueries.setDeleted(
          tx,
          id,
          deleted: false,
          now: _clock().toUtc(),
        );
        return (await DiaryQueries.find(tx, id))!;
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError('diary_entries.diary_date')) {
        throw const RepositoryException(RepositoryError.diaryDateConflict);
      }
      rethrow;
    }
  }

  Future<void> _ensureDateAvailable(
    DatabaseExecutor db,
    LocalDate date,
    String id,
  ) async {
    final other = await DiaryQueries.forDate(db, date);
    if (other != null && other.id != id) {
      throw const RepositoryException(RepositoryError.diaryDateConflict);
    }
  }
}
