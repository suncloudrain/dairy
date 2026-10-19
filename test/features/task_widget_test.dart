import 'package:dairy/app/app_dependencies.dart';
import 'package:dairy/app/dairy_app.dart';
import 'package:dairy/data/database/app_database.dart';
import 'package:dairy/models/local_date.dart';
import 'package:dairy/models/task_period.dart';
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

  Future<void> start(WidgetTester tester, {double width = 390}) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(DairyApp(initialize: () async => dependencies));
    await tester.pumpAndSettle();
    await tester.tap(find.text('任务'));
    await tester.pumpAndSettle();
  }

  Future<void> openNew(WidgetTester tester) async {
    await tester.tap(find.byTooltip('新建任务').last);
    await tester.pumpAndSettle();
  }

  Future<void> title(WidgetTester tester, String text) =>
      tester.enterText(find.byKey(const ValueKey('task-title')), text);

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
  }

  testWidgets('empty form creates nothing and validates before writing', (
    tester,
  ) async {
    await start(tester);
    await openNew(tester);
    expect(await database.connection.query('tasks'), isEmpty);
    await save(tester);
    expect(find.text('请输入任务标题。'), findsOneWidget);
    expect(find.text('新建任务'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('有未保存的修改'), findsNothing);
    expect(await database.connection.query('tasks'), isEmpty);
  });

  testWidgets(
    'manual save and edit preserve ID, creation time and completion',
    (tester) async {
      await start(tester);
      await openNew(tester);
      await title(tester, '我的任务');
      await tester.enterText(
        find.byKey(const ValueKey('task-notes')),
        '备注\n第二行',
      );
      await tester.pump(const Duration(seconds: 6));
      expect(await database.connection.query('tasks'), isEmpty);
      await save(tester);
      final first = (await dependencies.tasks.list(type: TaskType.day)).single;
      expect(first.notes, '备注\n第二行');
      expect(first.isCompleted, isFalse);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      final completed = (await dependencies.tasks.findById(first.id))!;
      expect(completed.completedAt, isNotNull);
      await tester.tap(find.text('我的任务'));
      await tester.pumpAndSettle();
      await title(tester, '修改后的任务');
      await save(tester);
      final edited = (await dependencies.tasks.findById(first.id))!;
      expect(edited.title, '修改后的任务');
      expect(edited.createdAt, first.createdAt);
      expect(edited.completedAt, completed.completedAt);
      expect(edited.isCompleted, isTrue);
      expect(await database.connection.query('tasks'), hasLength(1));
    },
  );

  testWidgets('completed and unfinished filters follow completion and undo', (
    tester,
  ) async {
    await dependencies.tasks.save(
      id: dependencies.tasks.newId(),
      title: '状态任务',
      period: TaskPeriod.day(LocalDate.fromDateTime(DateTime.now())),
    );
    await start(tester);
    await tester.tap(find.text('未完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('状态任务'), findsNothing);
    await tester.tap(find.text('已完成'));
    await tester.pumpAndSettle();
    expect(find.text('状态任务'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('状态任务'), findsNothing);
    final task = (await dependencies.tasks.list(type: TaskType.day)).single;
    expect(task.isCompleted, isFalse);
    expect(task.completedAt, isNull);
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(find.text('状态任务'), findsOneWidget);
  });

  testWidgets(
    'back offers continue, discard and save without silent data loss',
    (tester) async {
      await start(tester);
      await openNew(tester);
      await title(tester, '未保存任务');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('有未保存的修改'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(find.text('新建任务'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃修改'));
      await tester.pumpAndSettle();
      expect(await database.connection.query('tasks'), isEmpty);
      await openNew(tester);
      await title(tester, '返回时保存');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存并返回'));
      await tester.pumpAndSettle();
      expect(find.text('返回时保存'), findsOneWidget);
      expect(await database.connection.query('tasks'), hasLength(1));
    },
  );

  testWidgets('custom presets and positive duration validation use one task', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    await openNew(tester);
    await title(tester, '自定义任务');
    await tester.enterText(find.byKey(const ValueKey('task-days')), '0');
    await save(tester);
    expect(find.byKey(const ValueKey('task-editor-error')), findsOneWidget);
    expect(await database.connection.query('tasks'), isEmpty);
    await tester.ensureVisible(find.text('30 天'));
    await tester.tap(find.text('30 天'));
    await tester.pump();
    await save(tester);
    final task = (await dependencies.tasks.list(type: TaskType.custom)).single;
    expect(task.period.days, 30);
    expect(task.period.start.daysUntil(task.period.lastDay), 29);
    expect(await database.connection.query('tasks'), hasLength(1));
    await tester.tap(find.text('日任务'));
    await tester.pumpAndSettle();
    expect(find.text('自定义任务'), findsNothing);
  });

  testWidgets(
    'month/year editing selects future periods and saved tasks remain visible',
    (tester) async {
      await start(tester);
      await tester.tap(find.text('月任务'));
      await tester.pumpAndSettle();
      await openNew(tester);
      await title(tester, '未来月份');
      await tester.tap(find.byKey(const ValueKey('task-date')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('task-period-year')),
        '2028',
      );
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 月').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      await save(tester);
      final monthly = (await dependencies.tasks.list(type: TaskType.month))
          .single;
      expect(monthly.period.start, LocalDate(2028, 2, 1));
      expect(monthly.period.endExclusive, LocalDate(2028, 3, 1));
      expect(find.text('未来月份'), findsOneWidget);
      await tester.tap(find.text('年任务'));
      await tester.pumpAndSettle();
      await openNew(tester);
      await title(tester, '未来年份');
      await tester.tap(find.byKey(const ValueKey('task-date')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('task-period-year')),
        '2029',
      );
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      await save(tester);
      final yearly = (await dependencies.tasks.list(type: TaskType.year))
          .single;
      expect(yearly.period.start, LocalDate(2029, 1, 1));
      expect(yearly.period.endExclusive, LocalDate(2030, 1, 1));
      expect(find.text('未来年份'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('task-list-period')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('task-period-year')),
        '2030',
      );
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('未来年份'), findsNothing);
    },
  );

  testWidgets(
    'editing can move a task between types without changing identity',
    (tester) async {
      final original = await dependencies.tasks.save(
        id: dependencies.tasks.newId(),
        title: '移动类型',
        period: TaskPeriod.day(LocalDate.fromDateTime(DateTime.now())),
      );
      await start(tester);
      await tester.tap(find.text('移动类型'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('task-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自定义').last);
      await tester.pumpAndSettle();
      await save(tester);
      final edited = (await dependencies.tasks.findById(original.id))!;
      expect(edited.period.type, TaskType.custom);
      expect(edited.createdAt, original.createdAt);
      expect(find.text('移动类型'), findsOneWidget);
      expect(await database.connection.query('tasks'), hasLength(1));
    },
  );

  testWidgets(
    'delete confirmation cancels or soft deletes without clearing completion',
    (tester) async {
      final task = await dependencies.tasks.save(
        id: dependencies.tasks.newId(),
        title: '待删除任务',
        period: TaskPeriod.day(LocalDate.fromDateTime(DateTime.now())),
      );
      await dependencies.tasks.setCompleted(task.id, true);
      await start(tester);
      await tester.tap(find.byTooltip('任务操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('待删除任务'), findsOneWidget);
      await tester.tap(find.text('待删除任务'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('task-notes')), '未保存修改');
      await tester.tap(find.byTooltip('删除任务'));
      await tester.pumpAndSettle();
      expect(find.textContaining('尚未保存的修改将被放弃'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('待删除任务'), findsNothing);
      final deleted = (await database.connection.query('tasks')).single;
      expect(deleted['deleted_at'], isNotNull);
      expect(deleted['is_completed'], 1);
      expect(deleted['completed_at'], isNotNull);
      expect(deleted['notes'], isNull);
    },
  );

  testWidgets(
    'write failure keeps the form and retry creates a single record',
    (tester) async {
      await database.connection.execute('''
      CREATE TRIGGER reject_task_insert BEFORE INSERT ON tasks
      BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END;
    ''');
      await start(tester);
      await openNew(tester);
      await title(tester, '失败后重试');
      await save(tester);
      expect(find.text('保存失败，当前输入已保留，请重试。'), findsOneWidget);
      expect(find.text('新建任务'), findsOneWidget);
      expect(await database.connection.query('tasks'), isEmpty);
      await database.connection.execute('DROP TRIGGER reject_task_insert');
      await save(tester);
      expect(find.text('失败后重试'), findsOneWidget);
      expect(await database.connection.query('tasks'), hasLength(1));
    },
  );

  testWidgets(
    'failed completion/deletion retains the database and visible task',
    (tester) async {
      await dependencies.tasks.save(
        id: dependencies.tasks.newId(),
        title: '操作失败任务',
        period: TaskPeriod.day(LocalDate.fromDateTime(DateTime.now())),
      );
      await database.connection.execute('''
      CREATE TRIGGER reject_task_update BEFORE UPDATE ON tasks
      BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END;
    ''');
      await start(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      await tester.tap(find.byTooltip('任务操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('操作失败任务'), findsOneWidget);
      expect(
        (await database.connection.query('tasks')).single['deleted_at'],
        isNull,
      );
      await database.connection.execute('DROP TRIGGER reject_task_update');
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    },
  );

  testWidgets('task form and filters fit wide and narrow windows', (
    tester,
  ) async {
    await start(tester, width: 1200);
    await openNew(tester);
    await title(tester, '跨平台布局');
    tester.view.physicalSize = const Size(360, 640);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await save(tester);
    expect(find.text('跨平台布局'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
