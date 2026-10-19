import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import '../../data/repositories/task_repository.dart';
import '../../models/task.dart';
import '../../models/task_period.dart';
import 'task_editor_model.dart';
import 'task_period_controls.dart';

enum _LeaveChoice { discard, save }

class TaskEditorPage extends StatefulWidget {
  const TaskEditorPage({
    super.key,
    required this.repository,
    required this.initialPeriod,
    this.entry,
  });
  final TaskRepository repository;
  final TaskPeriod initialPeriod;
  final Task? entry;

  @override
  State<TaskEditorPage> createState() => _TaskEditorPageState();
}

class _TaskEditorPageState extends State<TaskEditorPage>
    with WidgetsBindingObserver {
  late final TaskEditorModel _model;
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late final TextEditingController _days;
  bool _confirming = false;
  bool _leaving = false;
  Task? _saved;

  @override
  void initState() {
    super.initState();
    _model = TaskEditorModel(
      id: widget.entry?.id ?? widget.repository.newId(),
      initialPeriod: widget.initialPeriod,
      entry: widget.entry,
      save: widget.repository.save,
      delete: widget.repository.softDelete,
    );
    _title = TextEditingController(text: _model.title);
    _notes = TextEditingController(text: _model.notes);
    _days = TextEditingController(text: _model.days);
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _save() async {
    if (_leaving || _confirming || _model.busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final saved = await _model.saveTask();
    if (mounted && saved != null) Navigator.pop(context, saved);
  }

  Future<bool> _allowLeave() async {
    if (_model.busy || _confirming) return false;
    if (!_model.dirty) return true;
    _confirming = true;
    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('有未保存的修改'),
        content: const Text('是否保存当前任务的修改？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _LeaveChoice.discard),
            child: const Text('放弃修改'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _LeaveChoice.save),
            child: const Text('保存并返回'),
          ),
        ],
      ),
    );
    _confirming = false;
    if (!mounted || choice == null) return false;
    if (choice == _LeaveChoice.discard) return true;
    FocusManager.instance.primaryFocus?.unfocus();
    _saved = await _model.saveTask();
    return _saved != null;
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    final allowed = await _allowLeave();
    _leaving = false;
    if (mounted && allowed) Navigator.pop(context, _saved);
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (_leaving) return AppExitResponse.cancel;
    _leaving = true;
    final allowed = await _allowLeave();
    _leaving = false;
    return allowed ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  Future<void> _delete() async {
    if (_model.busy || _confirming || _leaving) return;
    _confirming = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务？'),
        content: Text(
          _model.dirty
              ? '删除后任务不再显示，尚未保存的修改将被放弃。v0.1 暂不提供任务恢复入口。'
              : '删除后任务不再显示。v0.1 暂不提供任务恢复入口。',
        ),
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
    _confirming = false;
    if (!mounted || confirmed != true) return;
    if (await _model.deleteTask() && mounted) Navigator.pop(context);
  }

  Future<void> _chooseDate() async {
    final selected = await pickTaskDate(context, _model.type, _model.date);
    if (mounted && selected != null) _model.setDate(selected);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _model.dispose();
    _title.dispose();
    _notes.dispose();
    _days.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) => PopScope<Task>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _model.busy ? null : _leave),
          title: Text(widget.entry == null ? '新建任务' : '编辑任务'),
          actions: [
            if (widget.entry != null)
              IconButton(
                tooltip: '删除任务',
                onPressed: _model.busy ? null : _delete,
                icon: const Icon(Icons.delete_outline),
              ),
            TextButton(
              onPressed: _model.busy ? null : _save,
              child: const Text('保存'),
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _model.busy,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    key: const ValueKey('task-title'),
                    controller: _title,
                    onChanged: _model.setTitle,
                    decoration: const InputDecoration(
                      labelText: '任务标题（必填）',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('task-notes'),
                    controller: _notes,
                    onChanged: _model.setNotes,
                    keyboardType: TextInputType.multiline,
                    minLines: 3,
                    maxLines: null,
                    decoration: const InputDecoration(
                      labelText: '备注（可选）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<TaskType>(
                    key: const ValueKey('task-type'),
                    initialValue: _model.type,
                    decoration: const InputDecoration(labelText: '任务类型'),
                    items: [
                      for (final type in TaskType.values)
                        DropdownMenuItem(
                          value: type,
                          child: Text(taskTypeLabel(type)),
                        ),
                    ],
                    onChanged: (type) {
                      if (type != null) _model.setType(type);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    key: const ValueKey('task-date'),
                    onPressed: _chooseDate,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(switch (_model.type) {
                      TaskType.day => '日期：${_model.date}',
                      TaskType.month =>
                        '年月：${_model.date.year} 年 ${_model.date.month} 月',
                      TaskType.year => '年份：${_model.date.year} 年',
                      TaskType.custom => '开始日期：${_model.date}',
                    }),
                  ),
                  if (_model.type == TaskType.custom) ...[
                    TextField(
                      key: const ValueKey('task-days'),
                      controller: _days,
                      onChanged: _model.setDays,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '持续天数（正整数，包含开始日）',
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final days in [5, 10, 30])
                          ActionChip(
                            label: Text('$days 天'),
                            onPressed: () {
                              _days.text = days.toString();
                              _model.setDays(_days.text);
                            },
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    _model.period == null
                        ? '请选择有效的任务范围'
                        : '目标范围：${taskPeriodLabel(_model.period!)}',
                    key: const ValueKey('task-period-preview'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _model.entry?.isCompleted == true
                        ? '已完成（在任务列表中可撤销完成）'
                        : '未完成（保存后在任务列表中标记完成）',
                  ),
                  if (_model.busy) const LinearProgressIndicator(),
                  if (_model.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _model.error!,
                        key: const ValueKey('task-editor-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text('修改内容后点击右上角“保存”。'),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
