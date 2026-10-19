import 'package:flutter/foundation.dart';

import '../../data/repositories/task_repository.dart';
import '../../models/local_date.dart';
import '../../models/task.dart';
import '../../models/task_period.dart';

final class TaskListModel extends ChangeNotifier {
  TaskListModel(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    date = LocalDate.fromDateTime(_clock());
  }

  final TaskRepository _repository;
  final DateTime Function() _clock;
  TaskType type = TaskType.day;
  late LocalDate date;
  bool? completed;
  List<Task> _tasks = const [];
  List<Task> get tasks => List.unmodifiable(_tasks);
  bool loading = false;
  String? error;
  String? actionError;
  String? busyId;
  bool _disposed = false;
  int _request = 0;

  TaskPeriod? get period => switch (type) {
    TaskType.day => TaskPeriod.day(date),
    TaskType.month => TaskPeriod.month(date.year, date.month),
    TaskType.year => TaskPeriod.year(date.year),
    TaskType.custom => null,
  };

  Future<void> selectType(TaskType value) async {
    type = value;
    date = LocalDate.fromDateTime(_clock());
    await load();
  }

  Future<void> selectDate(LocalDate value) async {
    date = value;
    await load();
  }

  Future<void> selectCompleted(bool? value) async {
    completed = value;
    await load();
  }

  /// A saved task must be visible even when its type/period or filter changed.
  Future<void> focusTask(Task task) async {
    type = task.period.type;
    date = task.period.start;
    completed = null;
    await load();
  }

  Future<void> load() async {
    if (_disposed) return;
    final request = ++_request;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final tasks = await _repository.list(
        type: type,
        period: period,
        completed: completed,
      );
      if (_disposed || request != _request) return;
      _tasks = tasks;
    } catch (_) {
      if (_disposed || request != _request) return;
      error = '读取任务失败，请重试。';
    }
    if (_disposed || request != _request) return;
    loading = false;
    notifyListeners();
  }

  Future<bool> setCompleted(Task task, bool value) =>
      _mutate(task.id, () async {
        await _repository.setCompleted(task.id, value);
      });

  Future<bool> deleteTask(Task task) =>
      _mutate(task.id, () => _repository.softDelete(task.id));

  Future<bool> _mutate(String id, Future<void> Function() action) async {
    if (_disposed || busyId != null) return false;
    busyId = id;
    actionError = null;
    notifyListeners();
    try {
      await action();
      if (!_disposed) await load();
      return true;
    } catch (_) {
      if (!_disposed) actionError = '任务操作失败，原状态仍保留，请重试。';
      return false;
    } finally {
      busyId = null;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
