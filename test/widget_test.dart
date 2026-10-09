import 'package:dairy/app/app_dependencies.dart';
import 'package:dairy/app/dairy_app.dart';
import 'package:dairy/data/database/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_database.dart';

void main() {
  late AppDatabase database;
  late AppDependencies dependencies;
  setUp(() async {
    database = await openTestDatabase();
    dependencies = AppDependencies(database);
  });
  tearDown(() => database.close());

  testWidgets(
    'narrow layout navigates diary, recycle bin and task types without creating data',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(DairyApp(initialize: () async => dependencies));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('暂无日记'), findsOneWidget);
      await tester.tap(find.byTooltip('回收站'));
      await tester.pumpAndSettle();
      expect(find.text('回收站为空'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('任务'));
      await tester.pumpAndSettle();
      expect(find.text('暂无任务'), findsOneWidget);
      await tester.tap(find.text('自定义'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(await dependencies.diaries.listActive(), isEmpty);
    },
  );

  testWidgets('wide layout uses a rail and can resize to narrow layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(DairyApp(initialize: () async => dependencies));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    tester.view.physicalSize = const Size(360, 640);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup failure offers retry without deleting user data', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      DairyApp(
        initialize: () async {
          if (++attempts == 1) throw StateError('Test storage failure');
          return dependencies;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('无法打开本地数据，请重试。'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('暂无日记'), findsOneWidget);
    expect(attempts, 2);
  });
}
