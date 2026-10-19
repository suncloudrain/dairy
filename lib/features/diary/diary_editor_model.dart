import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/repository_exception.dart';
import '../../models/diary_entry.dart';
import '../../models/local_date.dart';

typedef DiarySave = Future<DiaryEntry> Function({
  required String id,
  required LocalDate date,
  String? title,
  required String body,
});
typedef DiaryDelete = Future<void> Function(String id);

enum DiarySaveStatus { empty, pending, saving, saved, failed, deleted }

/// One editing session owns one UUID. Revisions are local save coordination,
/// not cloud synchronization versions.
final class DiaryEditorModel extends ChangeNotifier {
  DiaryEditorModel({
    required this.id,
    required LocalDate date,
    required this.save,
    this.delete,
    DiaryEntry? entry,
    this.debounce = const Duration(milliseconds: 800),
    this.maxInterval = const Duration(seconds: 5),
  }) : _date = entry?.date ?? date,
       _entry = entry,
       _title = entry?.title ?? '',
       _body = entry?.body ?? '',
       _started = entry != null {
    if (entry != null && entry.id != id) {
      throw ArgumentError('Entry and editor must have the same ID.');
    }
  }

  final String id;
  final DiarySave save;
  final DiaryDelete? delete;
  final Duration debounce;
  final Duration maxInterval;
  LocalDate _date;
  DiaryEntry? _entry;
  String _title;
  String _body;
  bool _started;
  bool _disposed = false;
  int _revision = 0;
  int _savedRevision = 0;
  Timer? _debounceTimer;
  Timer? _maxTimer;
  Future<bool>? _activeSave;
  Future<bool>? _dateChange;
  Future<bool>? _deletion;
  bool _deleted = false;
  bool _deleteFailed = false;
  LocalDate? _failedDate;
  String? _error;
  RepositoryError? _businessError;

  LocalDate get date => _date;
  DiaryEntry? get entry => _entry;
  String get title => _title;
  String get body => _body;
  String? get error => _error;
  RepositoryError? get businessError => _businessError;
  bool get changingDate => _dateChange != null;
  bool get deleting => _deletion != null;
  bool get deleted => _deleted;
  bool get deleteFailed => _deleteFailed;
  bool get busy => changingDate || deleting;
  bool get saving => _activeSave != null || busy;
  LocalDate? get failedDate => _failedDate;
  bool get hasPendingChanges => _started && _revision != _savedRevision;
  bool get canChooseDate => _entry == null && !saving;

  DiarySaveStatus get status {
    if (_deleted) return DiarySaveStatus.deleted;
    if (saving) return DiarySaveStatus.saving;
    if (_error != null) return DiarySaveStatus.failed;
    if (hasPendingChanges) return DiarySaveStatus.pending;
    return _entry == null ? DiarySaveStatus.empty : DiarySaveStatus.saved;
  }

  void setTitle(String value) {
    if (_disposed || _deleted || busy || value == _title) return;
    _title = value;
    _changed();
  }

  void setBody(String value) {
    if (_disposed || _deleted || busy || value == _body) return;
    _body = value;
    _changed();
  }

  /// Draft dates are local; persisted entries use the explicit change operation.
  void chooseDate(LocalDate value) {
    if (_disposed || !canChooseDate || value == _date) return;
    _date = value;
    _changed();
  }

  void _changed() {
    _started = _started || _title.isNotEmpty || _body.isNotEmpty;
    _revision++;
    _error = null;
    _businessError = null;
    _failedDate = null;
    _deleteFailed = false;
    if (hasPendingChanges && !saving) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounce, () => unawaited(flush()));
      // Never reset this timer on each keystroke: continuous typing must save.
      _maxTimer ??= Timer(maxInterval, () => unawaited(flush()));
    }
    _notify();
  }

  /// Waits until the latest input is committed, or returns false on failure.
  /// The same future is shared by timer, retry and navigation requests.
  Future<bool> flush() {
    if (_disposed || _deleted) return Future.value(false);
    return _deletion ?? _dateChange ?? _flushContent();
  }

  Future<bool> _flushContent() {
    if (_disposed || _deleted) return Future.value(false);
    if (_activeSave != null) return _activeSave!;
    _cancelTimers();
    if (!hasPendingChanges) return Future.value(true);
    final completion = Completer<bool>();
    _activeSave = completion.future;
    _error = null;
    _businessError = null;
    _notify();
    unawaited(_drain(completion));
    return completion.future;
  }

  /// Save current content at its original date before attempting to move it.
  /// Publish the new date only after persistence succeeds.
  Future<bool> changeDate(LocalDate value) {
    if (_disposed || _deleted || _entry == null || busy) {
      return Future.value(false);
    }
    if (value == _date) return Future.value(true);
    final completion = Completer<bool>();
    _dateChange = completion.future;
    _error = null;
    _businessError = null;
    _failedDate = null;
    _deleteFailed = false;
    _notify();
    unawaited(_commitDateChange(value, completion));
    return completion.future;
  }

  /// Drain all content writes before deletion, then close this editing session
  /// to future writes even if the record is subsequently restored elsewhere.
  Future<bool> deleteEntry() {
    if (_disposed || _deleted || _entry == null || delete == null || busy) {
      return Future.value(false);
    }
    final completion = Completer<bool>();
    _deletion = completion.future;
    _error = null;
    _businessError = null;
    _failedDate = null;
    _deleteFailed = false;
    _notify();
    unawaited(_commitDeletion(completion));
    return completion.future;
  }

  Future<void> _commitDeletion(Completer<bool> completion) async {
    var success = false;
    try {
      if (!await _flushContent() || _disposed) return;
      await delete!(id);
      if (_disposed) return;
      _deleted = true;
      _cancelTimers();
      success = true;
    } catch (error) {
      if (!_disposed) {
        _deleteFailed = true;
        _businessError = error is RepositoryException ? error.code : null;
        _error = '删除失败，日记仍保留，请重试。';
      }
    } finally {
      _deletion = null;
      completion.complete(success && !_disposed);
      _notify();
    }
  }

  Future<void> _commitDateChange(
    LocalDate value,
    Completer<bool> completion,
  ) async {
    var success = false;
    try {
      if (!await _flushContent() || _disposed) return;
      final saved = await save(id: id, date: value, title: _title, body: _body);
      if (_disposed) return;
      _entry = saved;
      _date = saved.date;
      success = true;
    } catch (error) {
      if (!_disposed) {
        _failedDate = value;
        _businessError = error is RepositoryException ? error.code : null;
        _error = switch (_businessError) {
          RepositoryError.diaryDateConflict => '该日期已有日记，日记仍保留原日期。',
          RepositoryError.recordUnavailable => '这篇日记已不可编辑，当前输入仍保留在页面中。',
          _ => '修改日期失败，日记仍保留原日期，请重试。',
        };
      }
    } finally {
      _dateChange = null;
      completion.complete(success && !_disposed);
      _notify();
    }
  }

  Future<void> _drain(Completer<bool> completion) async {
    var success = true;
    try {
      while (!_disposed && hasPendingChanges) {
        final revision = _revision;
        // Capture immutable values before the asynchronous write starts.
        final saved = await save(
          id: id,
          date: _date,
          title: _title,
          body: _body,
        );
        if (_disposed) {
          success = false;
          break;
        }
        _entry = saved;
        _savedRevision = revision;
        // If input changed during the write, save only the latest snapshot next.
      }
    } catch (error) {
      success = false;
      if (!_disposed) {
        _businessError = error is RepositoryException ? error.code : null;
        _error = switch (_businessError) {
          RepositoryError.diaryDateConflict => '该日期已有日记，内容尚未保存。请选择其他日期。',
          RepositoryError.recordUnavailable => '这篇日记已不可编辑，当前输入仍保留在页面中。',
          _ => '保存失败，当前输入已保留，请重试。',
        };
      }
    } finally {
      _activeSave = null;
      completion.complete(success && !_disposed);
      _notify();
    }
  }

  void _cancelTimers() {
    _debounceTimer?.cancel();
    _maxTimer?.cancel();
    _debounceTimer = null;
    _maxTimer = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    super.dispose();
  }
}
