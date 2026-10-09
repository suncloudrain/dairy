import 'dart:io';

import 'package:dairy/data/database/app_database.dart';
import 'package:dairy/data/repositories/diary_repository.dart';
import 'package:dairy/data/repositories/repository_exception.dart';
import 'package:dairy/data/repositories/task_repository.dart';
import 'package:dairy/models/local_date.dart';
import 'package:dairy/models/task_period.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_database.dart';

Matcher businessError(RepositoryError code) =>
    isA<RepositoryException>().having((error) => error.code, 'code', code);

void main() {
  late AppDatabase database;
  late DiaryRepository diaries;
  late TaskRepository tasks;
  late DateTime now;
  final date = LocalDate(2026, 10, 7);

  setUp(() async {
    now = DateTime.utc(2026, 10, 7, 12);
    database = await openTestDatabase();
    diaries = DiaryRepository(database, clock: () => now);
    tasks = TaskRepository(database, clock: () => now);
  });
  tearDown(() => database.close());

  test('opening and allocating a draft ID does not create a diary', () async {
    expect(diaries.newId(), matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(await diaries.listActive(), isEmpty);
    expect(await database.connection.getVersion(), 1);
  });

  test(
    'same draft retry is idempotent; clearing content preserves the diary',
    () async {
      final id = diaries.newId();
      final first = await diaries.save(id: id, date: date, body: '中文\n第二行');
      now = now.add(const Duration(hours: 1));
      final unchanged = await diaries.save(
        id: id,
        date: date,
        body: first.body,
      );
      expect(unchanged.updatedAt, first.updatedAt);
      final cleared = await diaries.save(id: id, date: date, body: '');
      expect(cleared.createdAt, first.createdAt);
      expect(cleared.updatedAt, now);
      expect(cleared.isDeleted, isFalse);
      expect(await diaries.listActive(), hasLength(1));
    },
  );

  test(
    'duplicate date and date edits preserve both original records',
    () async {
      final first = await diaries.save(
        id: diaries.newId(),
        date: date,
        body: '第一篇',
      );
      await expectLater(
        diaries.save(id: diaries.newId(), date: date, body: '冲突'),
        throwsA(businessError(RepositoryError.diaryDateConflict)),
      );
      final second = await diaries.save(
        id: diaries.newId(),
        date: date.addDays(1),
        body: '第二篇',
      );
      await expectLater(
        diaries.save(id: second.id, date: date, body: '修改'),
        throwsA(businessError(RepositoryError.diaryDateConflict)),
      );
      expect((await diaries.findById(first.id))!.body, '第一篇');
      expect((await diaries.findById(second.id))!.date, date.addDays(1));
      expect((await diaries.findById(second.id))!.body, '第二篇');
    },
  );

  test(
    'soft delete frees date; conflict restore preserves tombstone and content',
    () async {
      final first = await diaries.save(
        id: diaries.newId(),
        date: date,
        body: '旧内容',
      );
      await diaries.softDelete(first.id);
      final second = await diaries.save(
        id: diaries.newId(),
        date: date,
        body: '新内容',
      );
      await expectLater(
        diaries.restore(first.id),
        throwsA(businessError(RepositoryError.diaryDateConflict)),
      );
      expect(await diaries.findById(first.id), isNull);
      expect((await diaries.listDeleted()).single.body, '旧内容');
      expect((await diaries.listActive()).single.id, second.id);
      await diaries.softDelete(second.id);
      now = now.add(const Duration(days: 1));
      final restored = await diaries.restore(first.id);
      expect(restored.id, first.id);
      expect(restored.createdAt, first.createdAt);
      expect(restored.updatedAt, now);
      expect(restored.deletedAt, isNull);
    },
  );

  test('a late save cannot resurrect a deleted diary', () async {
    final entry = await diaries.save(
      id: diaries.newId(),
      date: date,
      body: '保留',
    );
    await diaries.softDelete(entry.id);
    await expectLater(
      diaries.save(id: entry.id, date: date, body: '延迟写入'),
      throwsA(businessError(RepositoryError.recordUnavailable)),
    );
    expect((await diaries.listDeleted()).single.body, '保留');
  });

  test(
    'concurrent duplicate date writes create only one active diary',
    () async {
      final outcomes = await Future.wait(
        List.generate(2, (_) async {
          try {
            await diaries.save(id: diaries.newId(), date: date, body: '文本');
            return true;
          } on RepositoryException catch (error) {
            expect(error.code, RepositoryError.diaryDateConflict);
            return false;
          }
        }),
      );
      expect(outcomes.where((value) => value), hasLength(1));
      expect(await diaries.listActive(), hasLength(1));
    },
  );

  test(
    'task content saves preserve completion; repeated completion is a no-op',
    () async {
      final period = TaskPeriod.custom(date, 5);
      final first = await tasks.save(
        id: tasks.newId(),
        title: ' 阅读 ',
        period: period,
      );
      final done = await tasks.setCompleted(first.id, true);
      now = now.add(const Duration(hours: 1));
      final repeated = await tasks.setCompleted(first.id, true);
      expect(repeated.completedAt, done.completedAt);
      expect(repeated.updatedAt, done.updatedAt);
      final edited = await tasks.save(
        id: first.id,
        title: '读完一本书',
        period: period,
      );
      expect(edited.isCompleted, isTrue);
      expect(edited.completedAt, done.completedAt);
      final undone = await tasks.setCompleted(first.id, false);
      expect(undone.completedAt, isNull);
      final redone = await tasks.setCompleted(first.id, true);
      expect(redone.completedAt, now);
      expect(redone.createdAt, first.createdAt);
      await tasks.softDelete(first.id);
      expect(await tasks.findById(first.id), isNull);
      expect(await tasks.list(type: TaskType.custom), isEmpty);
      final row = (await database.connection.query('tasks')).single;
      expect(row['is_completed'], 1);
      expect(row['completed_at'], now.millisecondsSinceEpoch);
      await expectLater(
        tasks.save(id: first.id, title: '迟到编辑', period: period),
        throwsA(businessError(RepositoryError.recordUnavailable)),
      );
    },
  );

  test(
    'task validation and type/period filters keep CUSTOM separate',
    () async {
      await expectLater(
        tasks.save(
          id: tasks.newId(),
          title: ' \n\t',
          period: TaskPeriod.day(date),
        ),
        throwsA(businessError(RepositoryError.invalidInput)),
      );
      for (final period in [
        TaskPeriod.day(date),
        TaskPeriod.month(2026, 10),
        TaskPeriod.year(2026),
        TaskPeriod.custom(date, 30),
      ]) {
        await tasks.save(id: tasks.newId(), title: '相同标题', period: period);
      }
      final daily = await tasks.list(
        type: TaskType.day,
        period: TaskPeriod.day(date),
      );
      expect(daily, hasLength(1));
      expect(
        await tasks.list(
          type: TaskType.day,
          period: TaskPeriod.day(date.addDays(1)),
        ),
        isEmpty,
      );
      expect(await tasks.list(type: TaskType.custom), hasLength(1));
      await tasks.setCompleted(daily.single.id, true);
      expect(await tasks.list(type: TaskType.day, completed: false), isEmpty);
      expect(
        await tasks.list(type: TaskType.day, completed: true),
        hasLength(1),
      );
    },
  );

  test('database constraints reject bypassed invalid writes', () async {
    final entry = await diaries.save(
      id: diaries.newId(),
      date: date,
      body: '原文',
    );
    final diaryRow = (await database.connection.query('diary_entries')).single;
    await expectLater(
      database.connection.insert('diary_entries', {
        ...diaryRow,
        'id': diaries.newId(),
      }),
      throwsA(isA<DatabaseException>()),
    );
    final task = await tasks.save(
      id: tasks.newId(),
      title: '测试',
      period: TaskPeriod.day(date),
    );
    for (final values in <Map<String, Object?>>[
      {'is_completed': 1},
      {'task_type': 'WEEK'},
      {'title': ' '},
      {'period_end_exclusive': date.toString()},
      {'is_completed': 2},
    ]) {
      await expectLater(
        database.connection.update(
          'tasks',
          values,
          where: 'id = ?',
          whereArgs: [task.id],
        ),
        throwsA(isA<DatabaseException>()),
      );
    }
    expect((await tasks.findById(task.id))!.isCompleted, isFalse);
    expect((await diaries.findById(entry.id))!.body, '原文');
  });

  test(
    'file database survives reopen and rejects downgrade without deleting data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'dairy-foundation-',
      );
      final file = path.join(directory.path, 'test.sqlite');
      AppDatabase? persistent;
      Database? raw;
      try {
        persistent = await openTestDatabase(path: file);
        var repository = DiaryRepository(persistent);
        final saved = await repository.save(
          id: repository.newId(),
          date: date,
          body: '重启保留',
        );
        await persistent.close();
        persistent = await openTestDatabase(path: file);
        repository = DiaryRepository(persistent);
        expect((await repository.findById(saved.id))!.body, '重启保留');
        await persistent.close();
        persistent = null;
        raw = await databaseFactoryFfiNoIsolate.openDatabase(file);
        await raw.setVersion(2);
        await raw.close();
        raw = null;
        await expectLater(
          openTestDatabase(path: file),
          throwsA(isA<StateError>()),
        );
        raw = await databaseFactoryFfiNoIsolate.openDatabase(file);
        expect(await raw.getVersion(), 2);
        expect((await raw.query('diary_entries')).single['id'], saved.id);
      } finally {
        await persistent?.close();
        await raw?.close();
        // Only the temporary directory created by this test is removed.
        await directory.delete(recursive: true);
      }
    },
  );
}
