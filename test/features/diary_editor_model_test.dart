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
    'editor commits survive file reopen; edits preserve date and created time',
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
        editor.dispose();
        await database.close();
        database = await openTestDatabase(path: file);
        final entries = await DiaryRepository(database).listActive();
        expect(entries, hasLength(1));
        expect(entries.single.body, '');
        expect(entries.single.title, isNull);
        expect(entries.single.createdAt, created);
        expect(entries.single.date, date);
      } finally {
        await database.close();
        // Directory is the unique temporary directory created by this test.
        await directory.delete(recursive: true);
      }
    },
  );
}

const mainId = '7418dceb-ec80-4b20-9eb7-8f4c508a2aba';
