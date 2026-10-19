import 'dart:async';
import 'dart:io';

import 'package:dairy/data/repositories/task_repository.dart';
import 'package:dairy/features/tasks/task_editor_model.dart';
import 'package:dairy/features/tasks/task_list_model.dart';
import 'package:dairy/models/local_date.dart';
import 'package:dairy/models/task.dart';
import 'package:dairy/models/task_period.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import '../support/test_database.dart';

void main() {
  final date = LocalDate(2026, 12, 30);
  final now = DateTime.utc(2026, 10, 11);
  Task record({String id = 'draft', String title = '任务', TaskPeriod? period}) =>
      Task(
        id: id,
        title: title,
        period: period ?? TaskPeriod.day(date),
        isCompleted: false,
        createdAt: now,
        updatedAt: now,
      );

  test(
    'typing is memory-only; invalid title or custom duration never writes',
    () async {
      var writes = 0;
      final model = TaskEditorModel(
        id: 'draft',
        initialPeriod: TaskPeriod.custom(date, 5),
        save: ({required id, required title, notes, required period}) async {
          writes++;
          return record();
        },
        delete: (_) async {},
      );
      addTearDown(model.dispose);
      expect(model.dirty, isFalse);
      expect(await model.saveTask(), isNull);
      model.setTitle('新任务');
      model.setNotes('备注');
      expect(model.dirty, isTrue);
      expect(writes, 0);
      for (final days in [
        '0',
        '-1',
        '2.5',
        'abc',
        '999999999999999999999999',
      ]) {
        model.setDays(days);
        expect(await model.saveTask(), isNull);
      }
      expect(writes, 0);
    },
  );

  test(
    'four periods use natural boundaries and custom counts the first day',
    () {
      final model = TaskEditorModel(
        id: 'draft',
        initialPeriod: TaskPeriod.day(date),
        save: ({required id, required title, notes, required period}) async =>
            record(),
        delete: (_) async {},
      );
      addTearDown(model.dispose);
      expect(model.period!.endExclusive, LocalDate(2026, 12, 31));
      model.setType(TaskType.month);
      expect(model.period!.start, LocalDate(2026, 12, 1));
      expect(model.period!.endExclusive, LocalDate(2027, 1, 1));
      model.setType(TaskType.year);
      expect(model.period!.start, LocalDate(2026, 1, 1));
      expect(model.period!.endExclusive, LocalDate(2027, 1, 1));
      model.setType(TaskType.custom);
      model.setDays('5');
      expect(model.period!.start, date);
      expect(model.period!.lastDay, LocalDate(2027, 1, 3));
      model.setDate(LocalDate(9999, 12, 30));
      expect(model.period, isNull);
    },
  );

  test('failed save keeps the draft and retry reuses its ID', () async {
    final ids = <String>[];
    final model = TaskEditorModel(
      id: 'draft',
      initialPeriod: TaskPeriod.day(date),
      save: ({required id, required title, notes, required period}) async {
        ids.add(id);
        if (ids.length == 1) throw StateError('storage failure');
        return record(id: id, title: title, period: period);
      },
      delete: (_) async {},
    );
    addTearDown(model.dispose);
    model.setTitle('保留内容');
    expect(await model.saveTask(), isNull);
    expect(model.title, '保留内容');
    expect(model.dirty, isTrue);
    expect(model.error, isNotNull);
    expect((await model.saveTask())!.title, '保留内容');
    expect(ids, ['draft', 'draft']);
    expect(model.dirty, isFalse);
  });

  test(
    'in-flight save blocks repeated writes and changing the snapshot',
    () async {
      final completion = Completer<Task>();
      var writes = 0;
      final model = TaskEditorModel(
        id: 'draft',
        initialPeriod: TaskPeriod.day(date),
        save: ({required id, required title, notes, required period}) {
          writes++;
          return completion.future;
        },
        delete: (_) async {},
      );
      addTearDown(model.dispose);
      model.setTitle('提交中的内容');
      final saving = model.saveTask();
      expect(model.busy, isTrue);
      model.setTitle('不应替换');
      expect(model.title, '提交中的内容');
      expect(await model.saveTask(), isNull);
      completion.complete(record(title: '提交中的内容'));
      expect((await saving)!.title, '提交中的内容');
      expect(writes, 1);
      expect(model.busy, isFalse);
    },
  );

  test('disposing during a save suppresses late notifications', () async {
    final completion = Completer<Task>();
    final model = TaskEditorModel(
      id: 'draft',
      initialPeriod: TaskPeriod.day(date),
      save: ({required id, required title, notes, required period}) =>
          completion.future,
      delete: (_) async {},
    );
    model.setTitle('任务');
    final saving = model.saveTask();
    model.dispose();
    completion.complete(record());
    expect(await saving, isNull);
  });

  test('failed deletion keeps the existing task and unsaved edits', () async {
    final existing = record();
    final model = TaskEditorModel(
      id: existing.id,
      initialPeriod: existing.period,
      entry: existing,
      save: ({required id, required title, notes, required period}) async =>
          record(),
      delete: (_) async {
        throw StateError('storage failure');
      },
    );
    addTearDown(model.dispose);
    model.setNotes('未保存备注');
    expect(await model.deleteTask(), isFalse);
    expect(model.entry, same(existing));
    expect(model.notes, '未保存备注');
    expect(model.error, isNotNull);
  });

  test('list selects periods/status and focuses saved future tasks', () async {
    final database = await openTestDatabase();
    addTearDown(database.close);
    final repository = TaskRepository(database);
    final today = LocalDate(2026, 10, 11);
    final daily = await repository.save(
      id: repository.newId(),
      title: '今天',
      period: TaskPeriod.day(today),
    );
    final future = await repository.save(
      id: repository.newId(),
      title: '未来月份',
      period: TaskPeriod.month(2028, 2),
    );
    final custom = await repository.save(
      id: repository.newId(),
      title: '跨年',
      period: TaskPeriod.custom(date, 5),
    );
    final model = TaskListModel(
      repository,
      clock: () => DateTime(2026, 10, 11),
    );
    addTearDown(model.dispose);
    await model.load();
    expect(model.tasks.single.id, daily.id);
    await model.setCompleted(daily, true);
    await model.selectCompleted(false);
    expect(model.tasks, isEmpty);
    await model.focusTask(future);
    expect(model.type, TaskType.month);
    expect(model.completed, isNull);
    expect(model.tasks.single.id, future.id);
    await model.selectType(TaskType.custom);
    expect(model.tasks.single.id, custom.id);
    await model.deleteTask(custom);
    expect(model.tasks, isEmpty);
    expect(
      (await database.connection.query(
        'tasks',
        where: 'id = ?',
        whereArgs: [custom.id],
      )).single['deleted_at'],
      isNotNull,
    );
  });

  test(
    'task content/status/deletion survive file reopen and preserve metadata',
    () async {
      final directory = await Directory.systemTemp.createTemp('dairy-task-');
      final file = path.join(directory.path, 'tasks.sqlite');
      var database = await openTestDatabase(path: file);
      var repository = TaskRepository(database, clock: () => now);
      try {
        final model = TaskEditorModel(
          id: repository.newId(),
          initialPeriod: TaskPeriod.custom(date, 5),
          save: repository.save,
          delete: repository.softDelete,
        );
        model.setTitle('文件持久化');
        model.setNotes('多行\n备注');
        final first = (await model.saveTask())!;
        model.dispose();
        await repository.setCompleted(first.id, true);
        await database.close();
        database = await openTestDatabase(path: file);
        repository = TaskRepository(
          database,
          clock: () => now.add(const Duration(days: 1)),
        );
        final loaded = (await repository.findById(first.id))!;
        expect(loaded.notes, '多行\n备注');
        expect(loaded.period.lastDay, LocalDate(2027, 1, 3));
        expect(loaded.completedAt, now);
        final edited = await repository.save(
          id: first.id,
          title: '修改标题',
          period: loaded.period,
        );
        expect(edited.createdAt, first.createdAt);
        expect(edited.isCompleted, isTrue);
        expect(edited.completedAt, now);
        expect(
          (await repository.setCompleted(first.id, false)).completedAt,
          isNull,
        );
        await repository.softDelete(first.id);
        await database.close();
        database = await openTestDatabase(path: file);
        repository = TaskRepository(database);
        expect(await repository.findById(first.id), isNull);
        final deleted = (await database.connection.query('tasks')).single;
        expect(deleted['id'], first.id);
        expect(deleted['deleted_at'], isNotNull);
      } finally {
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
