import 'package:flutter/material.dart';

import '../features/diary/diary_page.dart';
import '../features/tasks/tasks_page.dart';
import 'app_dependencies.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.dependencies});
  final AppDependencies dependencies;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 720;
      return Scaffold(
        body: Row(
          children: [
            if (wide) ...[
              NavigationRail(
                selectedIndex: _selected,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: _select,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.book_outlined),
                    label: Text('日记'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.task_alt),
                    label: Text('任务'),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(
              child: IndexedStack(
                index: _selected,
                children: [
                  DiaryPage(repository: widget.dependencies.diaries),
                  TasksPage(repository: widget.dependencies.tasks),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _selected,
                onDestinationSelected: _select,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.book_outlined),
                    label: '日记',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.task_alt),
                    label: '任务',
                  ),
                ],
              ),
      );
    },
  );

  void _select(int value) => setState(() => _selected = value);
}
