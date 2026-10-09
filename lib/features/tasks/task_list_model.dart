import 'package:flutter/foundation.dart';

import '../../data/repositories/task_repository.dart';
import '../../models/local_date.dart';
import '../../models/task.dart';
import '../../models/task_period.dart';

final class TaskListModel extends ChangeNotifier {
  TaskListModel(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final TaskRepository _repository;
  final DateTime Function() _clock;
  TaskType type = TaskType.day;
  List<Task> _tasks = const [];
  List<Task> get tasks => List.unmodifiable(_tasks);
  bool loading = false;
  String? error;
  bool _disposed = false;
  int _request = 0;

  Future<void> selectType(TaskType value) async {
    type = value;
    await load();
  }

  Future<void> load() async {
    final request = ++_request;
    final date = LocalDate.fromDateTime(_clock());
    final period = switch (type) {
      TaskType.day => TaskPeriod.day(date),
      TaskType.month => TaskPeriod.month(date.year, date.month),
      TaskType.year => TaskPeriod.year(date.year),
      TaskType.custom => null,
    };
    loading = true;
    error = null;
    notifyListeners();
    try {
      final tasks = await _repository.list(type: type, period: period);
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

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
