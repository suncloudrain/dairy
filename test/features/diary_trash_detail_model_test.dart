import 'dart:async';
import 'dart:io';

import 'package:dairy/data/repositories/diary_repository.dart';
import 'package:dairy/features/diary/diary_editor_model.dart';
import 'package:dairy/features/diary/diary_trash_detail_model.dart';
import 'package:dairy/models/local_date.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import '../support/test_database.dart';

void main() {
  final date = LocalDate(2026, 10, 17);

  test('deleted content and restored identity survive file reopen', () async {
    final directory = await Directory.systemTemp.createTemp('dairy-trash-');
    final file = path.join(directory.path, 'diary.sqlite');
    var database = await openTestDatabase(path: file);
    var now = DateTime.utc(2026, 10, 17, 1);
    try {
      var repository = DiaryRepository(database, clock: () => now);
      final original = await repository.save(
        id: repository.newId(),
        date: date,
        title: '标题',
        body: '原正文',
      );
      final editor = DiaryEditorModel(
        id: original.id,
        date: date,
        entry: original,
        save: repository.save,
        delete: repository.softDelete,
      );
      editor.setBody('删除时的最新正文\n第二行');
      now = now.add(const Duration(hours: 1));
      expect(await editor.deleteEntry(), isTrue);
      editor.dispose();
      await database.close();
      database = await openTestDatabase(path: file);
      repository = DiaryRepository(database, clock: () => now);
      expect(await repository.listActive(), isEmpty);
      final deleted = (await repository.listDeleted()).single;
      expect(deleted.deletedAt, now);
      expect(deleted.body, '删除时的最新正文\n第二行');
      now = now.add(const Duration(hours: 1));
      final model = DiaryTrashDetailModel(repository, entry: deleted);
      expect(await model.restore(), isTrue);
      model.dispose();
      await database.close();
      database = await openTestDatabase(path: file);
      repository = DiaryRepository(database);
      final restored = (await repository.listActive()).single;
      expect(restored.id, original.id);
      expect(restored.createdAt, original.createdAt);
      expect(restored.date, original.date);
      expect(restored.title, original.title);
      expect(restored.body, deleted.body);
      expect(restored.deletedAt, isNull);
      expect(restored.updatedAt, now);
      expect(await repository.listDeleted(), isEmpty);
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });

  test('conflict preserves both records and lookup is read only', () async {
    final database = await openTestDatabase();
    addTearDown(database.close);
    final repository = DiaryRepository(database);
    final first = await repository.save(
      id: repository.newId(),
      date: date,
      body: '已删除正文',
    );
    await repository.softDelete(first.id);
    final deleted = (await repository.listDeleted()).single;
    final other = await repository.save(
      id: repository.newId(),
      date: date,
      body: '现有正文',
    );
    final model = DiaryTrashDetailModel(repository, entry: deleted);
    addTearDown(model.dispose);
    expect(await model.restore(), isFalse);
    expect(model.conflict, isTrue);
    expect((await model.findExisting())!.id, other.id);
    expect((await repository.findById(other.id))!.updatedAt, other.updatedAt);
    final stillDeleted = (await repository.listDeleted()).single;
    expect(stillDeleted.body, deleted.body);
    expect(stillDeleted.deletedAt, deleted.deletedAt);
    await repository.softDelete(other.id);
    expect(await model.restore(), isTrue);
    expect(model.conflict, isFalse);
  });

  test(
    'restore write failure leaves the entry recoverable for retry',
    () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final repository = DiaryRepository(database);
      final first = await repository.save(
        id: repository.newId(),
        date: date,
        body: '正文',
      );
      await repository.softDelete(first.id);
      final model = DiaryTrashDetailModel(
        repository,
        entry: (await repository.listDeleted()).single,
      );
      addTearDown(model.dispose);
      await database.connection.execute('''
      CREATE TRIGGER reject_restore BEFORE UPDATE OF deleted_at ON diary_entries
      WHEN NEW.deleted_at IS NULL
      BEGIN SELECT RAISE(ABORT, 'simulated restore failure'); END;
    ''');
      expect(await model.restore(), isFalse);
      expect(model.conflict, isFalse);
      expect(model.error, isNotNull);
      expect(await repository.listDeleted(), hasLength(1));
      await database.connection.execute('DROP TRIGGER reject_restore');
      expect(await model.restore(), isTrue);
    },
  );

  test(
    'missing current diary leaves detail available and recovery still works',
    () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final repository = DiaryRepository(database);
      final first = await repository.save(
        id: repository.newId(),
        date: date,
        body: '正文',
      );
      await repository.softDelete(first.id);
      final model = DiaryTrashDetailModel(
        repository,
        entry: (await repository.listDeleted()).single,
      );
      addTearDown(model.dispose);
      expect(await model.findExisting(), isNull);
      expect(model.error, '原日期当前没有日记，可以重试恢复。');
      expect(await repository.listDeleted(), hasLength(1));
      expect(await model.restore(), isTrue);
    },
  );

  test('pending restore rejects duplicates and suppresses late notification on disposal', () async {
    final database = await openTestDatabase();
    addTearDown(database.close);
    final repository = DiaryRepository(database);
    final first = await repository.save(
      id: repository.newId(),
      date: date,
      body: '正文',
    );
    await repository.softDelete(first.id);
    final model = DiaryTrashDetailModel(
      repository,
      entry: (await repository.listDeleted()).single,
    );
    final entered = Completer<void>();
    final release = Completer<void>();
    final transaction = database.connection.transaction((tx) async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final restoring = model.restore();
    expect(model.busy, isTrue);
    expect(await model.restore(), isFalse);
    expect(await model.findExisting(), isNull);
    model.dispose();
    release.complete();
    await transaction;
    expect(await restoring, isFalse);
    expect((await repository.findById(first.id))!.deletedAt, isNull);
  });
}
