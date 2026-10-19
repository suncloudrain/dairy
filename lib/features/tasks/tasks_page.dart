import 'package:flutter/material.dart';

import '../../data/repositories/task_repository.dart';
import '../../models/local_date.dart';
import '../../models/task.dart';
import '../../models/task_period.dart';
import 'task_editor_page.dart';
import 'task_list_model.dart';
import 'task_period_controls.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, required this.repository});
  final TaskRepository repository;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  late final TaskListModel _model;
  bool _opening = false;

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

  bool get _enabled => !_opening && _model.busyId == null;

  Future<void> _openTask([Task? task]) async {
    if (!_enabled) return;
    setState(() => _opening = true);
    try {
      final saved = await Navigator.of(context).push<Task>(
        MaterialPageRoute(
          builder: (_) => TaskEditorPage(
            repository: widget.repository,
            entry: task,
            initialPeriod:
                task?.period ??
                _model.period ??
                TaskPeriod.custom(LocalDate.fromDateTime(DateTime.now()), 5),
          ),
        ),
      );
      if (!mounted) return;
      if (saved == null) {
        await _model.load();
      } else {
        await _model.focusTask(saved);
      }
    } catch (_) {
      if (mounted) _message('打开任务失败，请重试。');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _setCompleted(Task task, bool value) async {
    if (!await _model.setCompleted(task, value) && mounted) {
      _message(_model.actionError ?? '请等待当前操作完成。');
    }
  }

  Future<void> _delete(Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务？'),
        content: Text('确定删除“${task.title}”？删除后不再显示，v0.1 暂不提供任务恢复入口。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (!await _model.deleteTask(task) && mounted) {
      _message(_model.actionError ?? '请等待当前操作完成。');
    }
  }

  Future<void> _chooseDate() async {
    final selected = await pickTaskDate(context, _model.type, _model.date);
    if (mounted && selected != null) await _model.selectDate(selected);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('任务'),
        actions: [
          IconButton(
            tooltip: '新建任务',
            onPressed: _enabled ? () => _openTask() : null,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _enabled ? _model.load : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'task-create',
        tooltip: '新建任务',
        onPressed: _enabled ? () => _openTask() : null,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in TaskType.values)
                  ChoiceChip(
                    label: Text(taskTypeLabel(type)),
                    selected: _model.type == type,
                    onSelected: _enabled
                        ? (_) => _model.selectType(type)
                        : null,
                  ),
              ],
            ),
          ),
          if (_model.type != TaskType.custom)
            TextButton.icon(
              key: const ValueKey('task-list-period'),
              onPressed: _enabled ? _chooseDate : null,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text('查看：${taskPeriodLabel(_model.period!)}'),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final filter in <bool?>[null, false, true])
                  ChoiceChip(
                    label: Text(
                      filter == null
                          ? '全部'
                          : filter
                          ? '已完成'
                          : '未完成',
                    ),
                    selected: _model.completed == filter,
                    onSelected: _enabled
                        ? (_) => _model.selectCompleted(filter)
                        : null,
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
              key: ValueKey('task-row-${task.id}'),
              onTap: _enabled ? () => _openTask(task) : null,
              leading: Tooltip(
                message: task.isCompleted ? '撤销完成' : '标记完成',
                child: Checkbox(
                  value: task.isCompleted,
                  onChanged: _enabled
                      ? (value) => _setCompleted(task, value!)
                      : null,
                ),
              ),
              title: Text(
                task.title,
                style: TextStyle(
                  decoration: task.isCompleted
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
              subtitle: Text(
                '${taskPeriodLabel(task.period)}${task.notes == null ? '' : '\n${task.notes}'}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: PopupMenuButton<String>(
                tooltip: '任务操作',
                enabled: _enabled,
                onSelected: (_) => _delete(task),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
