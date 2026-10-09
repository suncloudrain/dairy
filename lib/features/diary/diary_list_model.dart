import 'package:flutter/foundation.dart';

import '../../data/repositories/diary_repository.dart';
import '../../models/diary_entry.dart';

final class DiaryListModel extends ChangeNotifier {
  DiaryListModel(this._repository, {this.deleted = false});

  final DiaryRepository _repository;
  final bool deleted;
  List<DiaryEntry> _entries = const [];
  List<DiaryEntry> get entries => List.unmodifiable(_entries);
  bool loading = false;
  String? error;
  bool _disposed = false;
  int _request = 0;

  Future<void> load() async {
    final request = ++_request;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final entries = deleted
          ? await _repository.listDeleted()
          : await _repository.listActive();
      if (_disposed || request != _request) return;
      _entries = entries;
    } catch (_) {
      if (_disposed || request != _request) return;
      error = '读取日记失败，请重试。';
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
