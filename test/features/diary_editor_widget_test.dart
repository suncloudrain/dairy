import 'dart:async';

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

  Future<void> pickNewDate(
    WidgetTester tester,
    int day, {
    bool submit = true,
  }) async {
    await tester.ensureVisible(find.byKey(const ValueKey('diary-date')));
    await tester.tap(find.byKey(const ValueKey('diary-date')));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(DatePickerDialog),
            matching: find.text('$day'),
          )
          .last,
    );
    if (submit) {
      await tester.tap(find.text('确认修改'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'opening empty editor creates nothing; typing auto saves and reloads',
    (tester) async {
      await start(tester);
      await tester.tap(find.byTooltip('写今天'));
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
      await tester.tap(find.byTooltip('写今天'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('diary-body')),
        '返回前的最后一句',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final first = (await dependencies.diaries.listActive()).single;
      expect(first.body, '返回前的最后一句');
      await tester.tap(find.byTooltip('写今天'));
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
      await tester.tap(find.byTooltip('写今天'));
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
    await tester.tap(find.byTooltip('写今天'));
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
      await tester.tap(find.byTooltip('写今天'));
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
      await tester.tap(find.text('保存并返回'));
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
      await tester.tap(find.text('保存并返回'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('diary-body')), findsNothing);
      expect(find.text('暂无日记'), findsNothing);
    },
  );

  testWidgets('save and return from an untouched editor creates no record', (
    tester,
  ) async {
    await start(tester);
    expect(find.text('写今天'), findsNothing);
    final pencil = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(pencil.tooltip, '写今天');
    expect((pencil.child! as Icon).icon, Icons.edit_outlined);
    await tester.tap(find.byTooltip('写今天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存并返回'));
    await tester.pumpAndSettle();
    expect(find.text('暂无日记'), findsOneWidget);
    expect(find.byKey(const ValueKey('diary-body')), findsNothing);
    expect(await dependencies.diaries.listActive(), isEmpty);
  });

  testWidgets('save and return flushes the latest input and reuses its diary', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.byTooltip('写今天'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('diary-title')), '完成写作');
    await tester.enterText(find.byKey(const ValueKey('diary-body')), '立即保存的正文');
    await tester.tap(find.text('保存并返回'));
    await tester.pumpAndSettle();
    final original = (await dependencies.diaries.listActive()).single;
    expect(original.title, '完成写作');
    expect(original.body, '立即保存的正文');
    expect(find.byKey(const ValueKey('diary-body')), findsNothing);
    await tester.tap(find.byTooltip('写今天'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('diary-body')), '最后一次修改');
    await tester.tap(find.text('保存并返回'));
    await tester.pumpAndSettle();
    final edited = (await dependencies.diaries.listActive()).single;
    expect(edited.id, original.id);
    expect(edited.body, '最后一次修改');
    expect(edited.createdAt, original.createdAt);
    expect(edited.date, original.date);
  });

  testWidgets(
    'list shows one date for untitled diaries without changing data',
    (tester) async {
      final titled = await dependencies.diaries.save(
        id: dependencies.diaries.newId(),
        date: LocalDate(2026, 10, 9),
        title: '有标题的日记',
        body: '有标题正文',
      );
      final untitled = await dependencies.diaries.save(
        id: dependencies.diaries.newId(),
        date: LocalDate(2026, 10, 8),
        body: '无标题正文',
      );
      final empty = await dependencies.diaries.save(
        id: dependencies.diaries.newId(),
        date: LocalDate(2026, 10, 7),
        body: '',
      );
      await start(tester);
      expect(find.text('有标题的日记'), findsOneWidget);
      expect(find.text('2026-10-09\n有标题正文'), findsOneWidget);
      expect(find.text('2026-10-08'), findsOneWidget);
      expect(find.text('无标题正文'), findsOneWidget);
      expect(find.text('2026-10-07'), findsOneWidget);
      expect(find.text('暂无正文'), findsOneWidget);
      expect(
        (await dependencies.diaries.findById(titled.id))!.title,
        titled.title,
      );
      expect((await dependencies.diaries.findById(untitled.id))!.title, isNull);
      final storedEmpty = (await dependencies.diaries.findById(empty.id))!;
      expect(storedEmpty.title, isNull);
      expect(storedEmpty.body, '');
    },
  );

  testWidgets(
    'changed date persists while editor stays open until save and return',
    (tester) async {
      final original = await dependencies.diaries.save(
        id: dependencies.diaries.newId(),
        date: LocalDate(2026, 10, 9),
        body: '原正文',
      );
      await dependencies.diaries.save(
        id: dependencies.diaries.newId(),
        date: LocalDate(2026, 10, 10),
        body: '另一篇',
      );
      await start(tester);
      await tester.tap(find.text('2026-10-09'));
      await tester.pumpAndSettle();
      expect(find.text('修改日期'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('diary-body')),
        '改期前最后一句',
      );
      await pickNewDate(tester, 12);
      expect(find.text('编辑日记'), findsOneWidget);
      expect(find.text('日记日期：2026-10-12'), findsOneWidget);
      final moved = (await dependencies.diaries.findById(original.id))!;
      expect(moved.date, LocalDate(2026, 10, 12));
      expect(moved.body, '改期前最后一句');
      expect(moved.createdAt, original.createdAt);
      expect(await dependencies.diaries.findByDate(original.date), isNull);
      await tester.enterText(
        find.byKey(const ValueKey('diary-body')),
        '改期后继续写',
      );
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(
        (await dependencies.diaries.findById(original.id))!.date,
        moved.date,
      );
      expect(
        (await dependencies.diaries.findById(original.id))!.body,
        '改期后继续写',
      );
      await tester.tap(find.text('保存并返回'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('diary-body')), findsNothing);
      expect(find.text('2026-10-12'), findsOneWidget);
      expect(
        tester.widget<ListTile>(find.byType(ListTile).first).title,
        isA<Text>().having((text) => text.data, 'date', '2026-10-12'),
      );
    },
  );

  testWidgets(
    'cancel and same-date confirmation keep the stored record unchanged',
    (tester) async {
      final original = await dependencies.diaries.save(
        id: dependencies.diaries.newId(),
        date: LocalDate(2026, 10, 9),
        body: '正文',
      );
      await start(tester);
      await tester.tap(find.text('2026-10-09'));
      await tester.pumpAndSettle();
      await pickNewDate(tester, 12, submit: false);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('日记日期：2026-10-09'), findsOneWidget);
      await pickNewDate(tester, 9);
      final unchanged = (await dependencies.diaries.findById(original.id))!;
      expect(unchanged.date, original.date);
      expect(unchanged.updatedAt, original.updatedAt);
      expect(await dependencies.diaries.listActive(), hasLength(1));
      expect(find.text('编辑日记'), findsOneWidget);
    },
  );

  testWidgets(
    'date conflict preserves both diaries and can be retried or changed',
    (tester) async {
      final original = await dependencies.diaries.save(
        id: dependencies.diaries.newId(),
        date: LocalDate(2026, 10, 9),
        body: '本篇',
      );
      final other = await dependencies.diaries.save(
        id: dependencies.diaries.newId(),
        date: LocalDate(2026, 10, 10),
        body: '不覆盖的另一篇',
      );
      await start(tester);
      await tester.tap(find.text('2026-10-09'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('diary-body')),
        '保留当前输入',
      );
      await pickNewDate(tester, 10);
      expect(find.text('该日期已有日记'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.text('日记日期：2026-10-09'), findsOneWidget);
      expect(
        (await dependencies.diaries.findById(original.id))!.body,
        '保留当前输入',
      );
      expect((await dependencies.diaries.findById(other.id))!.body, other.body);
      await tester.ensureVisible(find.text('重试修改日期'));
      await tester.tap(find.text('重试修改日期'));
      await tester.pumpAndSettle();
      expect(find.text('该日期已有日记'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      await pickNewDate(tester, 8);
      expect(
        (await dependencies.diaries.findById(original.id))!.date,
        LocalDate(2026, 10, 8),
      );
      expect(await dependencies.diaries.listActive(), hasLength(2));
      expect(find.text('编辑日记'), findsOneWidget);
    },
  );

  testWidgets(
    'date write failure retains original date and retry stays in editor',
    (tester) async {
      final original = await dependencies.diaries.save(
        id: dependencies.diaries.newId(),
        date: LocalDate(2026, 10, 9),
        body: '原正文',
      );
      await database.connection.execute('''
      CREATE TRIGGER reject_date_change BEFORE UPDATE OF diary_date ON diary_entries
      WHEN NEW.diary_date != OLD.diary_date
      BEGIN SELECT RAISE(ABORT, 'simulated date write failure'); END;
    ''');
      await start(tester);
      await tester.tap(find.text('2026-10-09'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('diary-body')),
        '必须先保存的正文',
      );
      await pickNewDate(tester, 12);
      expect(find.text('修改日期失败，日记仍保留原日期，请重试。'), findsOneWidget);
      expect(find.text('日记日期：2026-10-09'), findsOneWidget);
      expect(
        (await dependencies.diaries.findById(original.id))!.body,
        '必须先保存的正文',
      );
      expect(
        (await dependencies.diaries.findById(original.id))!.date,
        original.date,
      );
      await database.connection.execute('DROP TRIGGER reject_date_change');
      await tester.ensureVisible(find.text('重试修改日期'));
      await tester.tap(find.text('重试修改日期'));
      await tester.pumpAndSettle();
      expect(find.text('编辑日记'), findsOneWidget);
      expect(
        (await dependencies.diaries.findById(original.id))!.date,
        LocalDate(2026, 10, 12),
      );
      expect(await dependencies.diaries.listActive(), hasLength(1));
    },
  );

  testWidgets('pending date commit blocks leaving and duplicate submission', (
    tester,
  ) async {
    final original = await dependencies.diaries.save(
      id: dependencies.diaries.newId(),
      date: LocalDate(2026, 10, 9),
      body: '正文',
    );
    await start(tester);
    await tester.tap(find.text('2026-10-09'));
    await tester.pumpAndSettle();
    await pickNewDate(tester, 12, submit: false);
    final entered = Completer<void>();
    final release = Completer<void>();
    final transaction = database.connection.transaction((tx) async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    try {
      await tester.tap(find.text('确认修改'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '保存并返回'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('diary-date')))
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
    expect(
      (await dependencies.diaries.findById(original.id))!.date,
      LocalDate(2026, 10, 12),
    );
    expect(find.text('编辑日记'), findsOneWidget);
  });
}
