import 'package:dairy/app/app_dependencies.dart';
import 'package:dairy/app/dairy_app.dart';
import 'package:dairy/data/database/app_database.dart';
import 'package:dairy/models/local_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  late AppDatabase database;
  late AppDependencies dependencies;
  setUp(() async {
    database = await openTestDatabase();
    dependencies = AppDependencies(database);
  });
  tearDown(() => database.close());

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(DairyApp(initialize: () async => dependencies));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'opening empty editor creates nothing; typing auto saves and reloads',
    (tester) async {
      await start(tester);
      await tester.tap(find.text('写今天'));
      await tester.pumpAndSettle();
      expect(await dependencies.diaries.listActive(), isEmpty);
      expect(find.text('输入后自动保存'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('diary-title')), '新日记');
      await tester.enterText(
        find.byKey(const ValueKey('diary-body')),
        '正文\n第二行',
      );
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(find.text('已保存'), findsOneWidget);
      final entry = (await dependencies.diaries.listActive()).single;
      expect(entry.title, '新日记');
      expect(entry.body, '正文\n第二行');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('新日记'), findsOneWidget);
      await tester.tap(find.text('新日记'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('diary-body')))
            .controller!
            .text,
        entry.body,
      );
      expect(find.text('选择日期'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('diary-body')),
        '修改后的正文',
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      final edited = (await dependencies.diaries.findById(entry.id))!;
      expect(edited.body, '修改后的正文');
      expect(edited.createdAt, entry.createdAt);
      expect(edited.date, entry.date);
    },
  );

  testWidgets(
    'system back flushes immediately and today reopens the same diary',
    (tester) async {
      await start(tester);
      await tester.tap(find.text('写今天'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('diary-body')),
        '返回前的最后一句',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final first = (await dependencies.diaries.listActive()).single;
      expect(first.body, '返回前的最后一句');
      await tester.tap(find.text('写今天'));
      await tester.pumpAndSettle();
      expect(find.text('编辑日记'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('diary-body')), '');
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      final entries = await dependencies.diaries.listActive();
      expect(entries, hasLength(1));
      expect(entries.single.id, first.id);
      expect(entries.single.body, '');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'late duplicate date alerts and preserves both existing data and draft input',
    (tester) async {
      await start(tester);
      await tester.tap(find.text('写今天'));
      await tester.pumpAndSettle();
      final original = await dependencies.diaries.save(
        id: dependencies.diaries.newId(),
        date: LocalDate.fromDateTime(DateTime.now()),
        body: '原有日记',
      );
      await tester.enterText(
        find.byKey(const ValueKey('diary-body')),
        '新的草稿内容',
      );
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(find.text('该日期已有日记'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('diary-body')))
            .controller!
            .text,
        '新的草稿内容',
      );
      expect((await dependencies.diaries.findById(original.id))!.body, '原有日记');
      expect(await dependencies.diaries.listActive(), hasLength(1));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('新建日记'), findsOneWidget);
      expect(find.byKey(const ValueKey('diary-body')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('background transition submits pending content before debounce', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.text('写今天'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('diary-body')),
      '进入后台前的输入',
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect((await dependencies.diaries.listActive()).single.body, '进入后台前的输入');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'storage failure blocks leaving and retry persists retained input',
    (tester) async {
      await start(tester);
      await tester.tap(find.text('写今天'));
      await tester.pumpAndSettle();
      await database.connection.execute('''
      CREATE TRIGGER reject_test_save BEFORE INSERT ON diary_entries
      BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END;
    ''');
      await tester.enterText(
        find.byKey(const ValueKey('diary-body')),
        '失败后要保留的正文',
      );
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(find.text('保存失败，当前输入已保留，请重试。'), findsOneWidget);
      expect(find.text('已保存'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('新建日记'), findsOneWidget);
      expect(await dependencies.diaries.listActive(), isEmpty);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('diary-body')))
            .controller!
            .text,
        '失败后要保留的正文',
      );
      await database.connection.execute('DROP TRIGGER reject_test_save');
      await tester.ensureVisible(find.text('重试保存'));
      await tester.tap(find.text('重试保存'));
      await tester.pumpAndSettle();
      expect(find.text('已保存'), findsOneWidget);
      expect(
        (await dependencies.diaries.listActive()).single.body,
        '失败后要保留的正文',
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('暂无日记'), findsNothing);
    },
  );
}
