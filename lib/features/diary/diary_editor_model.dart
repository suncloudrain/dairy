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

enum DiarySaveStatus { empty, pending, saving, saved, failed }

/// One editing session owns one UUID. Revisions are local save coordination,
/// not cloud synchronization versions.
final class DiaryEditorModel extends ChangeNotifier {
  DiaryEditorModel({
    required this.id,
    required LocalDate date,
    required this.save,
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
  String? _error;
  RepositoryError? _businessError;

  LocalDate get date => _date;
  DiaryEntry? get entry => _entry;
  String get title => _title;
  String get body => _body;
  String? get error => _error;
  RepositoryError? get businessError => _businessError;
  bool get saving => _activeSave != null;
  bool get hasPendingChanges => _started && _revision != _savedRevision;
  bool get canChooseDate => _entry == null && !saving;

  DiarySaveStatus get status {
    if (saving) return DiarySaveStatus.saving;
    if (_error != null) return DiarySaveStatus.failed;
    if (hasPendingChanges) return DiarySaveStatus.pending;
    return _entry == null ? DiarySaveStatus.empty : DiarySaveStatus.saved;
  }

  void setTitle(String value) {
    if (_disposed || value == _title) return;
    _title = value;
    _changed();
  }

  void setBody(String value) {
    if (_disposed || value == _body) return;
    _body = value;
    _changed();
  }

  /// Only an unpersisted draft may select its date in this feature stage.
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
    if (_disposed) return Future.value(false);
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
