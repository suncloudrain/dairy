import 'package:flutter/material.dart';

import '../../data/repositories/task_repository.dart';
import '../../models/task_period.dart';
import 'task_list_model.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, required this.repository});
  final TaskRepository repository;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  late final TaskListModel _model;

  @override
  void initState() {
    super.initState();
    _model = TaskListModel(widget.repository)..load();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('任务'),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _model.load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: _model,
      builder: (context, _) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in TaskType.values)
                  ChoiceChip(
                    label: Text(switch (type) {
                      TaskType.day => '今日',
                      TaskType.month => '本月',
                      TaskType.year => '今年',
                      TaskType.custom => '自定义',
                    }),
                    selected: _model.type == type,
                    onSelected: (_) => _model.selectType(type),
                  ),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    ),
  );

  Widget _body() {
    if (_model.loading) return const Center(child: CircularProgressIndicator());
    if (_model.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_model.error!),
            TextButton(onPressed: _model.load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_model.tasks.isEmpty) return const Center(child: Text('暂无任务'));
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: ListView.builder(
          itemCount: _model.tasks.length,
          itemBuilder: (context, index) {
            final task = _model.tasks[index];
            return ListTile(
              leading: Icon(
                task.isCompleted
                    ? Icons.check_circle_outline
                    : Icons.radio_button_unchecked,
              ),
              title: Text(task.title),
              subtitle: Text('${task.period.start} 至 ${task.period.lastDay}'),
            );
          },
        ),
      ),
    );
  }
}
