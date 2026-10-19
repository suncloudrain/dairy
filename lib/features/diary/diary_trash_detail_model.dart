import 'package:flutter/foundation.dart';

import '../../data/repositories/diary_repository.dart';
import '../../data/repositories/repository_exception.dart';
import '../../models/diary_entry.dart';

/// Database actions for a read-only deleted entry. Navigation and clipboard
/// access belong to the page, not to this state object.
final class DiaryTrashDetailModel extends ChangeNotifier {
  DiaryTrashDetailModel(this._repository, {required this.entry}) {
    if (!entry.isDeleted) throw ArgumentError('Expected a deleted diary.');
  }

  final DiaryRepository _repository;
  final DiaryEntry entry;
  bool busy = false;
  bool restored = false;
  bool conflict = false;
  String? error;
  bool _disposed = false;

  Future<bool> restore() async {
    if (_disposed || busy || restored) return false;
    busy = true;
    conflict = false;
    error = null;
    notifyListeners();
    try {
      await _repository.restore(entry.id);
      if (_disposed) return false;
      restored = true;
      return true;
    } catch (failure) {
      if (!_disposed) {
        conflict =
            failure is RepositoryException &&
            failure.code == RepositoryError.diaryDateConflict;
        error = conflict ? '原日期已有日记，无法恢复。两篇日记均保留。' : '恢复失败，日记仍保留在回收站，请重试。';
      }
      return false;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<DiaryEntry?> findExisting() async {
    if (_disposed || busy || restored) return null;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final existing = await _repository.findByDate(entry.date);
      if (_disposed) return null;
      if (existing == null) error = '原日期当前没有日记，可以重试恢复。';
      return existing;
    } catch (_) {
      if (!_disposed) error = '读取现有日记失败，请重试。';
      return null;
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
