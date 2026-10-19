import 'dart:async';

import 'package:dairy/app/app_dependencies.dart';
import 'package:dairy/app/dairy_app.dart';
import 'package:dairy/data/database/app_database.dart';
import 'package:dairy/models/diary_entry.dart';
import 'package:dairy/models/local_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  late AppDatabase database;
  late AppDependencies dependencies;
  late List<String> clipboardWrites;
  var failClipboard = false;
  final date = LocalDate(2026, 10, 9);

  setUp(() async {
    database = await openTestDatabase();
    dependencies = AppDependencies(database);
    clipboardWrites = [];
    failClipboard = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            if (failClipboard) throw PlatformException(code: 'copy-failed');
            clipboardWrites.add((call.arguments as Map)['text'] as String);
          }
          if (call.method == 'Clipboard.hasStrings') {
            return {'value': clipboardWrites.isNotEmpty};
          }
          if (call.method == 'Clipboard.getData') {
            return {
              'text': clipboardWrites.isEmpty ? '' : clipboardWrites.last,
            };
          }
          return null;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await database.close();
  });

  Future<DiaryEntry> seed({bool deleted = false}) async {
    final entry = await dependencies.diaries.save(
      id: dependencies.diaries.newId(),
      date: date,
      title: '测试日记',
      body: '原正文\n第二行',
    );
    if (deleted) await dependencies.diaries.softDelete(entry.id);
    return entry;
  }

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(DairyApp(initialize: () async => dependencies));
    await tester.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.text('测试日记'));
    await tester.pumpAndSettle();
  }

  Future<void> openTrash(WidgetTester tester) async {
    await tester.tap(find.byTooltip('回收站'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试日记'));
    await tester.pumpAndSettle();
  }

  Future<void> confirmDelete(WidgetTester tester) async {
    await tester.tap(find.text('移入回收站'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'delete cancel preserves diary; confirmed deletion stores latest content in read-only trash',
    (tester) async {
      final original = await seed();
      await start(tester);
      await openEditor(tester);
      await tester.tap(find.byTooltip('删除日记'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await dependencies.diaries.findById(original.id), isNotNull);
      await tester.enterText(
        find.byKey(const ValueKey('diary-body')),
        '删除前最后输入\n不丢失',
      );
      await tester.tap(find.byTooltip('删除日记'));
      await tester.pumpAndSettle();
      await confirmDelete(tester);
      expect(find.text('暂无日记'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      expect(await dependencies.diaries.listActive(), isEmpty);
      final deleted = (await dependencies.diaries.listDeleted()).single;
      expect(deleted.body, '删除前最后输入\n不丢失');
      expect(deleted.createdAt, original.createdAt);
      await tester.tap(find.byTooltip('回收站'));
      await tester.pumpAndSettle();
      expect(find.textContaining('删除于：'), findsOneWidget);
      await tester.tap(find.text('测试日记'));
      await tester.pumpAndSettle();
      expect(find.text('已删除日记'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('diary-trash-body')),
            )
            .data,
        deleted.body,
      );
      expect(find.text('恢复'), findsOneWidget);
      expect(find.text('复制正文'), findsOneWidget);
      expect(clipboardWrites, isEmpty);
      tester.view.physicalSize = const Size(360, 640);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'restore returns to refreshed trash and main list with original identity',
    (tester) async {
      final original = await seed(deleted: true);
      await start(tester);
      await openTrash(tester);
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();
      expect(find.text('回收站为空'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('测试日记'), findsOneWidget);
      final restored = (await dependencies.diaries.listActive()).single;
      expect(restored.id, original.id);
      expect(restored.date, original.date);
      expect(restored.createdAt, original.createdAt);
      expect(restored.body, original.body);
      expect(restored.deletedAt, isNull);
      expect(clipboardWrites, isEmpty);
    },
  );

  testWidgets(
    'restore conflict never copies automatically and opening existing diary does not merge',
    (tester) async {
      final original = await seed(deleted: true);
      final deletedBefore = (await dependencies.diaries.listDeleted()).single;
      final existing = await dependencies.diaries.save(
        id: dependencies.diaries.newId(),
        date: date,
        title: '现有日记',
        body: '不能覆盖的正文',
      );
      await start(tester);
      await openTrash(tester);
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();
      expect(find.text('原日期已有日记'), findsOneWidget);
      expect(clipboardWrites, isEmpty);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制正文'));
      await tester.pumpAndSettle();
      expect(clipboardWrites, [original.body]);
      expect(find.text('正文已复制'), findsOneWidget);
      await tester.tap(find.text('打开现有日记'));
      await tester.pumpAndSettle();
      expect(find.text('编辑日记'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('diary-body')))
            .controller!
            .text,
        existing.body,
      );
      await tester.tap(find.text('保存并返回'));
      await tester.pumpAndSettle();
      expect(find.text('已删除日记'), findsOneWidget);
      expect(
        (await dependencies.diaries.findById(existing.id))!.updatedAt,
        existing.updatedAt,
      );
      final stillDeleted = (await dependencies.diaries.listDeleted()).single;
      expect(stillDeleted.deletedAt, deletedBefore.deletedAt);
      expect(stillDeleted.body, original.body);
    },
  );

  testWidgets(
    'restore failure keeps detail and retry succeeds without clipboard writes',
    (tester) async {
      await seed(deleted: true);
      await database.connection.execute('''
      CREATE TRIGGER reject_restore BEFORE UPDATE OF deleted_at ON diary_entries
      WHEN NEW.deleted_at IS NULL
      BEGIN SELECT RAISE(ABORT, 'simulated restore failure'); END;
    ''');
      await start(tester);
      await openTrash(tester);
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();
      expect(find.text('恢复失败，日记仍保留在回收站，请重试。'), findsOneWidget);
      expect(find.text('已删除日记'), findsOneWidget);
      expect(await dependencies.diaries.listDeleted(), hasLength(1));
      await database.connection.execute('DROP TRIGGER reject_restore');
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();
      expect(find.text('回收站为空'), findsOneWidget);
      expect(clipboardWrites, isEmpty);
    },
  );

  testWidgets(
    'clipboard failure is retryable and never changes database metadata',
    (tester) async {
      await seed(deleted: true);
      final before = (await dependencies.diaries.listDeleted()).single;
      await start(tester);
      await openTrash(tester);
      failClipboard = true;
      await tester.tap(find.text('复制正文'));
      await tester.pumpAndSettle();
      expect(find.text('复制失败，请重试。'), findsOneWidget);
      expect(clipboardWrites, isEmpty);
      failClipboard = false;
      await tester.tap(find.text('复制正文'));
      await tester.pumpAndSettle();
      expect(clipboardWrites, [before.body]);
      final after = (await dependencies.diaries.listDeleted()).single;
      expect(after.updatedAt, before.updatedAt);
      expect(after.deletedAt, before.deletedAt);
    },
  );

  testWidgets('content save failure prevents deletion and keeps editor input', (
    tester,
  ) async {
    final original = await seed();
    await database.connection.execute('''
      CREATE TRIGGER reject_content BEFORE UPDATE ON diary_entries
      BEGIN SELECT RAISE(ABORT, 'simulated content save failure'); END;
    ''');
    await start(tester);
    await openEditor(tester);
    await tester.enterText(find.byKey(const ValueKey('diary-body')), '必须保留的输入');
    await tester.tap(find.byTooltip('删除日记'));
    await tester.pumpAndSettle();
    await confirmDelete(tester);
    expect(find.text('编辑日记'), findsOneWidget);
    expect(find.text('保存失败，当前输入已保留，请重试。'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('diary-body')))
          .controller!
          .text,
      '必须保留的输入',
    );
    expect(await dependencies.diaries.findById(original.id), isNotNull);
    await database.connection.execute('DROP TRIGGER reject_content');
    await tester.tap(find.byTooltip('删除日记'));
    await tester.pumpAndSettle();
    await confirmDelete(tester);
    expect((await dependencies.diaries.listDeleted()).single.body, '必须保留的输入');
  });

  testWidgets(
    'delete write failure preserves saved content and supports explicit retry',
    (tester) async {
      final original = await seed();
      await database.connection.execute('''
      CREATE TRIGGER reject_delete BEFORE UPDATE OF deleted_at ON diary_entries
      WHEN NEW.deleted_at IS NOT NULL
      BEGIN SELECT RAISE(ABORT, 'simulated delete failure'); END;
    ''');
      await start(tester);
      await openEditor(tester);
      await tester.enterText(
        find.byKey(const ValueKey('diary-body')),
        '先保存成功的正文',
      );
      await tester.tap(find.byTooltip('删除日记'));
      await tester.pumpAndSettle();
      await confirmDelete(tester);
      expect(find.text('删除失败，日记仍保留，请重试。'), findsOneWidget);
      expect(
        (await dependencies.diaries.findById(original.id))!.body,
        '先保存成功的正文',
      );
      await database.connection.execute('DROP TRIGGER reject_delete');
      await tester.ensureVisible(find.text('重试删除'));
      await tester.tap(find.text('重试删除'));
      await tester.pumpAndSettle();
      await confirmDelete(tester);
      expect(find.text('暂无日记'), findsOneWidget);
      expect(
        (await dependencies.diaries.listDeleted()).single.body,
        '先保存成功的正文',
      );
    },
  );

  testWidgets(
    'pending delete disables leaving and duplicate actions until success',
    (tester) async {
      await seed();
      await start(tester);
      await openEditor(tester);
      await tester.tap(find.byTooltip('删除日记'));
      await tester.pumpAndSettle();
      final entered = Completer<void>();
      final release = Completer<void>();
      final transaction = database.connection.transaction((tx) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      try {
        await tester.tap(find.text('移入回收站'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.delete_outline),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '保存并返回'))
              .onPressed,
          isNull,
        );
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.text('编辑日记'), findsOneWidget);
      } finally {
        release.complete();
        await transaction;
      }
      await tester.pumpAndSettle();
      expect(find.text('暂无日记'), findsOneWidget);
      expect(await dependencies.diaries.listDeleted(), hasLength(1));
    },
  );
}
