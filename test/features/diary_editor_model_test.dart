import 'dart:async';
import 'dart:io';

import 'package:dairy/data/repositories/diary_repository.dart';
import 'package:dairy/data/repositories/repository_exception.dart';
import 'package:dairy/features/diary/diary_editor_model.dart';
import 'package:dairy/models/diary_entry.dart';
import 'package:dairy/models/local_date.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import '../support/test_database.dart';

void main() {
  deletionTests();
  const id = '7418dceb-ec80-4b20-9eb7-8f4c508a2aba';
  final date = LocalDate(2026, 10, 9);
  final created = DateTime.utc(2026, 10, 9, 8);
  DiaryEntry record(String body, {String? title, LocalDate? selected}) =>
      DiaryEntry(
        id: id,
        date: selected ?? date,
        body: body,
        title: title,
        createdAt: created,
        updatedAt: created,
      );

  test('empty editor and date selection do not create a row', () async {
    var calls = 0;
    final model = DiaryEditorModel(
      id: id,
      date: date,
      save: ({required id, required date, title, required body}) async {
        calls++;
        return record(body, title: title, selected: date);
      },
    );
    addTearDown(model.dispose);
    model.chooseDate(date.addDays(-1));
    expect(await model.flush(), isTrue);
    expect(calls, 0);
    expect(model.status, DiarySaveStatus.empty);
  });

  testWidgets('debounce saves title-only input after a pause', (tester) async {
    final writes = <DiaryEntry>[];
    final model = DiaryEditorModel(
      id: id,
      date: date,
      save: ({required id, required date, title, required body}) async {
        final entry = record(body, title: title, selected: date);
        writes.add(entry);
        return entry;
      },
    );
    addTearDown(model.dispose);
    model.setTitle('只写标题');
    await tester.pump(const Duration(milliseconds: 799));
    expect(writes, isEmpty);
    expect(model.status, DiarySaveStatus.pending);
    await tester.pump(const Duration(milliseconds: 1));
    expect(writes.single.title, '只写标题');
    expect(writes.single.body, '');
    expect(model.status, DiarySaveStatus.saved);
    await tester.pump(const Duration(seconds: 5));
    expect(writes, hasLength(1));
  });

  testWidgets('continuous typing saves at the maximum interval', (
    tester,
  ) async {
    final writes = <String>[];
    final model = DiaryEditorModel(
      id: id,
      date: date,
      save: ({required id, required date, title, required body}) async {
        writes.add(body);
        return record(body);
      },
    );
    addTearDown(model.dispose);
    model.setBody('0');
    for (var i = 1; i <= 9; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      model.setBody('$i');
    }
    expect(writes, isEmpty);
    await tester.pump(const Duration(milliseconds: 500));
    expect(writes, ['9']);
    expect(model.status, DiarySaveStatus.saved);
  });

  test('overlapping saves are serialized and merge pending input', () async {
    final writes = <String>[];
    final completions = <Completer<DiaryEntry>>[];
    final model = DiaryEditorModel(
      id: id,
      date: date,
      save: ({required id, required date, title, required body}) {
        expect(id, mainId);
        writes.add(body);
        final completion = Completer<DiaryEntry>();
        completions.add(completion);
        return completion.future;
      },
    );
    addTearDown(model.dispose);
    model.setBody('旧内容');
    final first = model.flush();
    model.setBody('中间内容');
    model.setBody('最新内容');
    expect(identical(first, model.flush()), isTrue);
    expect(writes, ['旧内容']);
    completions[0].complete(record('旧内容'));
    await Future<void>.delayed(Duration.zero);
    expect(writes, ['旧内容', '最新内容']);
    expect(model.status, DiarySaveStatus.saving);
    expect(model.hasPendingChanges, isTrue);
    completions[1].complete(record('最新内容'));
    expect(await first, isTrue);
    expect(model.entry!.body, '最新内容');
    expect(model.status, DiarySaveStatus.saved);
  });

  test(
    'failed save retains input and retry reuses the same identity',
    () async {
      final ids = <String>[];
      final model = DiaryEditorModel(
        id: id,
        date: date,
        save: ({required id, required date, title, required body}) async {
          ids.add(id);
          if (ids.length == 1) throw StateError('Simulated write failure');
          return record(body, title: title);
        },
      );
      addTearDown(model.dispose);
      model.setBody('不能丢失的输入');
      expect(await model.flush(), isFalse);
      expect(model.body, '不能丢失的输入');
      expect(model.hasPendingChanges, isTrue);
      expect(model.status, DiarySaveStatus.failed);
      expect(await model.flush(), isTrue);
      expect(ids, [id, id]);
      expect(model.status, DiarySaveStatus.saved);
    },
  );

  test(
    'conflict keeps input; draft can choose another date before persisting',
    () async {
      final model = DiaryEditorModel(
        id: id,
        date: date,
        save: ({required id, required date, title, required body}) async {
          if (date == LocalDate(2026, 10, 9)) {
            throw const RepositoryException(RepositoryError.diaryDateConflict);
          }
          return record(body, selected: date);
        },
      );
      addTearDown(model.dispose);
      model.setBody('冲突草稿');
      expect(await model.flush(), isFalse);
      expect(model.businessError, RepositoryError.diaryDateConflict);
      expect(model.body, '冲突草稿');
      model.chooseDate(date.addDays(-1));
      expect(await model.flush(), isTrue);
      expect(model.entry!.date, date.addDays(-1));
      model.chooseDate(date.addDays(1));
      expect(model.date, date.addDays(-1));
      expect(model.canChooseDate, isFalse);
    },
  );

  testWidgets('dispose cancels timers and cannot enqueue more writes', (
    tester,
  ) async {
    var calls = 0;
    final model = DiaryEditorModel(
      id: id,
      date: date,
      save: ({required id, required date, title, required body}) async {
        calls++;
        return record(body);
      },
    );
    model.setBody('未提交');
    model.dispose();
    await tester.pump(const Duration(seconds: 6));
    expect(calls, 0);
    expect(await model.flush(), isFalse);
  });

  test(
    'ordinary edits preserve date; explicit date change survives file reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp('dairy-editor-');
      final file = path.join(directory.path, 'editor.sqlite');
      var database = await openTestDatabase(path: file);
      var now = created;
      try {
        var repository = DiaryRepository(database, clock: () => now);
        final first = DiaryEditorModel(
          id: repository.newId(),
          date: date,
          save: repository.save,
        );
        first.setTitle('中文日记');
        first.setBody('第一行\n第二行');
        expect(await first.flush(), isTrue);
        final saved = first.entry!;
        first.dispose();
        await database.close();
        database = await openTestDatabase(path: file);
        repository = DiaryRepository(database, clock: () => now);
        final reopened = (await repository.findById(saved.id))!;
        expect(reopened.body, '第一行\n第二行');
        now = created.add(const Duration(days: 1));
        final editor = DiaryEditorModel(
          id: reopened.id,
          date: date.addDays(1),
          entry: reopened,
          save: repository.save,
        );
        editor.chooseDate(date.addDays(2));
        editor.setBody('修改后');
        expect(await editor.flush(), isTrue);
        expect(editor.entry!.id, saved.id);
        expect(editor.entry!.createdAt, created);
        expect(editor.entry!.date, date);
        expect(editor.entry!.updatedAt, now);
        editor.setTitle('');
        editor.setBody('');
        expect(await editor.flush(), isTrue);
        expect(await editor.changeDate(date.addDays(2)), isTrue);
        editor.dispose();
        await database.close();
        database = await openTestDatabase(path: file);
        final entries = await DiaryRepository(database).listActive();
        expect(entries, hasLength(1));
        expect(entries.single.body, '');
        expect(entries.single.title, isNull);
        expect(entries.single.createdAt, created);
        expect(entries.single.date, date.addDays(2));
      } finally {
        await database.close();
        // Directory is the unique temporary directory created by this test.
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'date change commits pending content and keeps record identity',
    () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      var now = created;
      final repository = DiaryRepository(database, clock: () => now);
      final original = await repository.save(id: id, date: date, body: '原正文');
      final model = DiaryEditorModel(
        id: id,
        date: date,
        entry: original,
        save: repository.save,
      );
      addTearDown(model.dispose);
      now = created.add(const Duration(days: 1));
      model.setTitle('保留标题');
      model.setBody('改期前最后输入');
      final target = date.addDays(5);
      expect(await model.changeDate(target), isTrue);
      expect(await repository.findByDate(date), isNull);
      final moved = (await repository.findByDate(target))!;
      expect(moved.id, original.id);
      expect(moved.createdAt, original.createdAt);
      expect(moved.updatedAt, now);
      expect(moved.title, '保留标题');
      expect(moved.body, '改期前最后输入');
      expect(model.date, target);
      expect(model.status, DiarySaveStatus.saved);
      model.setBody('改期后继续写');
      expect(await model.flush(), isTrue);
      expect((await repository.findById(id))!.date, target);
      expect((await repository.findById(id))!.body, '改期后继续写');
      expect(await repository.listActive(), hasLength(1));
    },
  );

  test('date conflict keeps both entries and saves pending content at the original date', () async {
    final database = await openTestDatabase();
    addTearDown(database.close);
    final repository = DiaryRepository(database);
    final original = await repository.save(id: id, date: date, body: '原正文');
    final target = date.addDays(1);
    final other = await repository.save(
      id: repository.newId(),
      date: target,
      body: '另一篇正文',
    );
    final model = DiaryEditorModel(
      id: id,
      date: date,
      entry: original,
      save: repository.save,
    );
    addTearDown(model.dispose);
    model.setBody('未保存的新输入');
    expect(await model.changeDate(target), isFalse);
    expect(model.date, date);
    expect(model.failedDate, target);
    expect(model.businessError, RepositoryError.diaryDateConflict);
    expect((await repository.findById(id))!.body, '未保存的新输入');
    expect((await repository.findById(other.id))!.body, other.body);
    model.setBody('冲突后继续编辑');
    expect(model.failedDate, isNull);
    expect(await model.flush(), isTrue);
    expect((await repository.findById(id))!.date, date);
    expect(await repository.listActive(), hasLength(2));
    expect(await model.changeDate(target.addDays(1)), isTrue);
  });

  test(
    'date change waits for old snapshots and blocks competing writes',
    () async {
      final writes = <({LocalDate date, String body})>[];
      final completions = <Completer<DiaryEntry>>[];
      final model = DiaryEditorModel(
        id: id,
        date: date,
        entry: record('原正文'),
        save: ({required id, required date, title, required body}) {
          writes.add((date: date, body: body));
          final completion = Completer<DiaryEntry>();
          completions.add(completion);
          return completion.future;
        },
      );
      addTearDown(model.dispose);
      model.setBody('正在保存的旧快照');
      final first = model.flush();
      model.setBody('最新输入');
      final target = date.addDays(3);
      final changing = model.changeDate(target);
      expect(model.changingDate, isTrue);
      expect(identical(model.flush(), changing), isTrue);
      model.setBody('改期期间应阻止的输入');
      model.setTitle('应阻止的标题');
      expect(model.body, '最新输入');
      expect(model.title, '');
      expect(await model.changeDate(target.addDays(1)), isFalse);
      expect(writes, [(date: date, body: '正在保存的旧快照')]);
      completions[0].complete(record(writes[0].body));
      await Future<void>.delayed(Duration.zero);
      expect(writes[1], (date: date, body: '最新输入'));
      completions[1].complete(record(writes[1].body));
      await Future<void>.delayed(Duration.zero);
      expect(writes[2], (date: target, body: '最新输入'));
      expect(model.date, date);
      completions[2].complete(record(writes[2].body, selected: target));
      expect(await changing, isTrue);
      expect(await first, isTrue);
      expect(model.date, target);
      expect(await model.flush(), isTrue);
      expect(writes, hasLength(3));
      expect(model.status, DiarySaveStatus.saved);
    },
  );

  test(
    'failed content save prevents date change and retains inputs for retry',
    () async {
      var fail = true;
      final dates = <LocalDate>[];
      final model = DiaryEditorModel(
        id: id,
        date: date,
        entry: record('原正文'),
        save: ({required id, required date, title, required body}) async {
          dates.add(date);
          if (fail) throw StateError('storage failure');
          return record(body, selected: date);
        },
      );
      addTearDown(model.dispose);
      model.setBody('不能丢的输入');
      final target = date.addDays(1);
      expect(await model.changeDate(target), isFalse);
      expect(dates, [date]);
      expect(model.date, date);
      expect(model.body, '不能丢的输入');
      expect(model.hasPendingChanges, isTrue);
      expect(model.failedDate, isNull);
      fail = false;
      expect(await model.changeDate(target), isTrue);
      expect(dates, [date, date, target]);
    },
  );

  test(
    'failed date write keeps the committed date and retries the same ID',
    () async {
      var writes = 0;
      final ids = <String>[];
      final target = date.addDays(1);
      final model = DiaryEditorModel(
        id: id,
        date: date,
        entry: record('原正文'),
        save: ({required id, required date, title, required body}) async {
          ids.add(id);
          if (++writes == 1) throw StateError('storage failure');
          return record(body, selected: date);
        },
      );
      addTearDown(model.dispose);
      expect(await model.changeDate(target), isFalse);
      expect(model.date, date);
      expect(model.entry!.date, date);
      expect(model.failedDate, target);
      expect(model.status, DiarySaveStatus.failed);
      expect(await model.changeDate(model.failedDate!), isTrue);
      expect(model.failedDate, isNull);
      expect(model.date, target);
      expect(ids, [id, id]);
    },
  );

  test('unchanged dates and unpersisted drafts cause no date writes', () async {
    var writes = 0;
    Future<DiaryEntry> save({
      required String id,
      required LocalDate date,
      String? title,
      required String body,
    }) async {
      writes++;
      return record(body, selected: date);
    }

    final existing = DiaryEditorModel(
      id: id,
      date: date,
      entry: record('正文'),
      save: save,
    );
    final draft = DiaryEditorModel(id: id, date: date, save: save);
    addTearDown(existing.dispose);
    addTearDown(draft.dispose);
    expect(await existing.changeDate(date), isTrue);
    expect(await draft.changeDate(date.addDays(1)), isFalse);
    expect(writes, 0);
  });

  test(
    'disposing during date change prevents late state notifications',
    () async {
      final completion = Completer<DiaryEntry>();
      final target = date.addDays(1);
      final model = DiaryEditorModel(
        id: id,
        date: date,
        entry: record('正文'),
        save: ({required id, required date, title, required body}) =>
            completion.future,
      );
      final changing = model.changeDate(target);
      await Future<void>.delayed(Duration.zero);
      model.dispose();
      completion.complete(record('正文', selected: target));
      expect(await changing, isFalse);
      expect(model.date, date);
    },
  );
}

void deletionTests() {
  const id = mainId;
  final date = LocalDate(2026, 10, 9);
  final created = DateTime.utc(2026, 10, 9, 8);
  DiaryEntry record(String body, {LocalDate? selected}) => DiaryEntry(
    id: id,
    date: selected ?? date,
    body: body,
    createdAt: created,
    updatedAt: created,
  );

  test(
    'delete saves latest content and old editor cannot write after restore',
    () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final repository = DiaryRepository(database);
      final original = await repository.save(id: id, date: date, body: '原正文');
      final model = DiaryEditorModel(
        id: id,
        date: date,
        entry: original,
        save: repository.save,
        delete: repository.softDelete,
      );
      addTearDown(model.dispose);
      model.setTitle('保留标题');
      model.setBody('删除前最后一句');
      expect(await model.deleteEntry(), isTrue);
      expect(model.status, DiarySaveStatus.deleted);
      expect(await repository.listActive(), isEmpty);
      final deleted = (await repository.listDeleted()).single;
      expect(deleted.body, '删除前最后一句');
      expect(deleted.title, '保留标题');
      expect(deleted.createdAt, original.createdAt);
      await repository.restore(id);
      model.setBody('旧会话不允许写入');
      expect(await model.flush(), isFalse);
      expect(await model.changeDate(date.addDays(1)), isFalse);
      expect(await model.deleteEntry(), isFalse);
      expect((await repository.findById(id))!.body, deleted.body);
    },
  );

  test(
    'delete drains slow snapshots and shares its pending operation with flush',
    () async {
      final writes = <String>[];
      final completions = <Completer<DiaryEntry>>[];
      final deletion = Completer<void>();
      var deletes = 0;
      final model = DiaryEditorModel(
        id: id,
        date: date,
        entry: record('正文'),
        save: ({required id, required date, title, required body}) {
          writes.add(body);
          final completion = Completer<DiaryEntry>();
          completions.add(completion);
          return completion.future;
        },
        delete: (_) {
          deletes++;
          return deletion.future;
        },
      );
      addTearDown(model.dispose);
      model.setBody('旧快照');
      final first = model.flush();
      model.setBody('最新输入');
      final removing = model.deleteEntry();
      expect(identical(removing, model.flush()), isTrue);
      expect(await model.deleteEntry(), isFalse);
      expect(await model.changeDate(date.addDays(1)), isFalse);
      model.setBody('阻止删除期间的输入');
      expect(model.body, '最新输入');
      completions[0].complete(record('旧快照'));
      await Future<void>.delayed(Duration.zero);
      expect(writes, ['旧快照', '最新输入']);
      expect(deletes, 0);
      completions[1].complete(record('最新输入'));
      await Future<void>.delayed(Duration.zero);
      expect(deletes, 1);
      expect(model.deleting, isTrue);
      deletion.complete();
      expect(await removing, isTrue);
      expect(await first, isTrue);
      expect(await model.flush(), isFalse);
      expect(writes, hasLength(2));
    },
  );

  test(
    'failed content save prevents deletion and retry preserves input',
    () async {
      var fail = true;
      var deletes = 0;
      final model = DiaryEditorModel(
        id: id,
        date: date,
        entry: record('正文'),
        save: ({required id, required date, title, required body}) async {
          if (fail) throw StateError('save failure');
          return record(body);
        },
        delete: (_) async {
          deletes++;
        },
      );
      addTearDown(model.dispose);
      model.setBody('不能丢的输入');
      expect(await model.deleteEntry(), isFalse);
      expect(deletes, 0);
      expect(model.body, '不能丢的输入');
      expect(model.deleteFailed, isFalse);
      expect(model.hasPendingChanges, isTrue);
      fail = false;
      expect(await model.deleteEntry(), isTrue);
      expect(deletes, 1);
    },
  );

  test(
    'failed delete leaves saved content editable and can be retried',
    () async {
      var deletes = 0;
      final model = DiaryEditorModel(
        id: id,
        date: date,
        entry: record('正文'),
        save: ({required id, required date, title, required body}) async =>
            record(body),
        delete: (_) async {
          if (++deletes == 1) throw StateError('delete failure');
        },
      );
      addTearDown(model.dispose);
      model.setBody('先保存的正文');
      expect(await model.deleteEntry(), isFalse);
      expect(model.entry!.body, '先保存的正文');
      expect(model.deleted, isFalse);
      expect(model.deleteFailed, isTrue);
      model.setBody('失败后继续编辑');
      expect(model.deleteFailed, isFalse);
      expect(await model.deleteEntry(), isTrue);
      expect(model.entry!.body, '失败后继续编辑');
      expect(deletes, 2);
    },
  );

  test('date change and deletion cannot run concurrently', () async {
    final completion = Completer<DiaryEntry>();
    var deletes = 0;
    final model = DiaryEditorModel(
      id: id,
      date: date,
      entry: record('正文'),
      save: ({required id, required date, title, required body}) =>
          completion.future,
      delete: (_) async {
        deletes++;
      },
    );
    addTearDown(model.dispose);
    final target = date.addDays(1);
    final moving = model.changeDate(target);
    await Future<void>.delayed(Duration.zero);
    expect(await model.deleteEntry(), isFalse);
    expect(deletes, 0);
    completion.complete(record('正文', selected: target));
    expect(await moving, isTrue);
    expect(await model.deleteEntry(), isTrue);
    expect(deletes, 1);
  });

  test(
    'disposing during pending content save cancels subsequent deletion',
    () async {
      final completion = Completer<DiaryEntry>();
      var deletes = 0;
      final model = DiaryEditorModel(
        id: id,
        date: date,
        entry: record('正文'),
        save: ({required id, required date, title, required body}) =>
            completion.future,
        delete: (_) async {
          deletes++;
        },
      );
      model.setBody('待保存');
      final removing = model.deleteEntry();
      model.dispose();
      completion.complete(record('待保存'));
      expect(await removing, isFalse);
      expect(deletes, 0);
    },
  );

  test('blank draft cannot create a record through deletion', () async {
    var calls = 0;
    final model = DiaryEditorModel(
      id: id,
      date: date,
      save: ({required id, required date, title, required body}) async {
        calls++;
        return record(body);
      },
      delete: (_) async {
        calls++;
      },
    );
    addTearDown(model.dispose);
    expect(await model.deleteEntry(), isFalse);
    expect(calls, 0);
  });
}

const mainId = '7418dceb-ec80-4b20-9eb7-8f4c508a2aba';
