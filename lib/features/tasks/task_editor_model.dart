import 'package:flutter/foundation.dart';

import '../../data/repositories/repository_exception.dart';
import '../../models/local_date.dart';
import '../../models/task.dart';
import '../../models/task_period.dart';

typedef TaskSave = Future<Task> Function({
  required String id,
  required String title,
  String? notes,
  required TaskPeriod period,
});
typedef TaskDelete = Future<void> Function(String id);

/// A manual-save form. No database writes occur while the user types.
final class TaskEditorModel extends ChangeNotifier {
  TaskEditorModel({
    required this.id,
    required TaskPeriod initialPeriod,
    required this.save,
    required this.delete,
    Task? entry,
  }) : _entry = entry,
       _title = entry?.title ?? '',
       _notes = entry?.notes ?? '',
       _type = (entry?.period ?? initialPeriod).type,
       _date = (entry?.period ?? initialPeriod).start,
       _days =
           (entry?.period.type == TaskType.custom
                   ? entry!.period.days
                   : initialPeriod.type == TaskType.custom
                   ? initialPeriod.days
                   : 5)
               .toString() {
    if (entry != null && entry.id != id) {
      throw ArgumentError('Entry and editor must have the same ID.');
    }
    _baseline = _snapshot;
  }

  final String id;
  final TaskSave save;
  final TaskDelete delete;
  Task? _entry;
  String _title;
  String _notes;
  TaskType _type;
  LocalDate _date;
  String _days;
  late ({
    String title,
    String notes,
    TaskType type,
    LocalDate date,
    String days,
  })
  _baseline;
  bool _disposed = false;
  bool busy = false;
  String? error;

  Task? get entry => _entry;
  String get title => _title;
  String get notes => _notes;
  TaskType get type => _type;
  LocalDate get date => _date;
  String get days => _days;
  bool get dirty => _snapshot != _baseline;
  ({String title, String notes, TaskType type, LocalDate date, String days})
  get _snapshot =>
      (title: _title, notes: _notes, type: _type, date: _date, days: _days);

  TaskPeriod? get period {
    try {
      if (_type == TaskType.custom) {
        final count = int.tryParse(_days);
        final maximum = _date.daysUntil(LocalDate(9999, 12, 31));
        if (count == null || count <= 0 || count > maximum) return null;
        return TaskPeriod.custom(_date, count);
      }
      return switch (_type) {
        TaskType.day => TaskPeriod.day(_date),
        TaskType.month => TaskPeriod.month(_date.year, _date.month),
        TaskType.year => TaskPeriod.year(_date.year),
        TaskType.custom => TaskPeriod.custom(_date, int.tryParse(_days) ?? 0),
      };
    } on ArgumentError {
      return null;
    }
  }

  void setTitle(String value) => _change(() => _title = value);
  void setNotes(String value) => _change(() => _notes = value);
  void setDays(String value) => _change(() => _days = value);
  void setDate(LocalDate value) => _change(() => _date = value);
  void setType(TaskType value) => _change(() {
    _type = value;
  });

  void _change(VoidCallback change) {
    if (_disposed || busy) return;
    change();
    error = null;
    notifyListeners();
  }

  Future<Task?> saveTask() async {
    if (_disposed || busy) return null;
    final selectedPeriod = period;
    if (_title.trim().isEmpty || selectedPeriod == null) {
      error = _title.trim().isEmpty
          ? '请输入任务标题。'
          : '请选择有效日期范围；持续天数必须为正整数，结束日期不能超出支持范围。';
      notifyListeners();
      return null;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      final saved = await save(
        id: id,
        title: _title,
        notes: _notes,
        period: selectedPeriod,
      );
      if (_disposed) return null;
      _entry = saved;
      _baseline = _snapshot;
      return saved;
    } catch (failure) {
      if (!_disposed) {
        error =
            failure is RepositoryException &&
                failure.code == RepositoryError.recordUnavailable
            ? '这个任务已不可编辑，当前输入仍保留。'
            : '保存失败，当前输入已保留，请重试。';
      }
      return null;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> deleteTask() async {
    if (_disposed || busy || _entry == null) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await delete(id);
      return !_disposed;
    } catch (_) {
      if (!_disposed) error = '删除失败，任务仍保留，请重试。';
      return false;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
