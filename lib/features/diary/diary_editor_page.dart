import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import '../../data/repositories/diary_repository.dart';
import '../../data/repositories/repository_exception.dart';
import '../../models/diary_entry.dart';
import '../../models/local_date.dart';
import 'diary_editor_model.dart';

class DiaryEditorPage extends StatefulWidget {
  const DiaryEditorPage({
    super.key,
    required this.repository,
    required this.date,
    this.entry,
  });

  final DiaryRepository repository;
  final LocalDate date;
  final DiaryEntry? entry;

  @override
  State<DiaryEditorPage> createState() => _DiaryEditorPageState();
}

class _DiaryEditorPageState extends State<DiaryEditorPage>
    with WidgetsBindingObserver {
  late final DiaryEditorModel _model;
  late final TextEditingController _title;
  late final TextEditingController _body;
  bool _leaving = false;
  bool _conflictAcknowledged = false;
  bool _choosingDate = false;
  bool _confirmingDelete = false;

  @override
  void initState() {
    super.initState();
    _model = DiaryEditorModel(
      id: widget.entry?.id ?? widget.repository.newId(),
      date: widget.date,
      entry: widget.entry,
      save: widget.repository.save,
      delete: widget.repository.softDelete,
    )..addListener(_onModelChanged);
    _title = TextEditingController(text: _model.title);
    _body = TextEditingController(text: _model.body);
    WidgetsBinding.instance.addObserver(this);
  }

  void _onModelChanged() {
    if (_model.businessError != RepositoryError.diaryDateConflict ||
        _conflictAcknowledged) {
      return;
    }
    _conflictAcknowledged = true;
    final message = _model.failedDate == null
        ? '已有日记不会被覆盖。当前输入已保留，请选择其他日记日期后重试。'
        : '该日期的日记不会被覆盖，本篇日记仍保留原日期和内容。请选择其他日期。';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('该日期已有日记'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ],
          ),
        ),
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_model.flush());
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (_leaving) return AppExitResponse.cancel;
    final saved = await _prepareToLeave();
    return saved ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  Future<bool> _prepareToLeave() async {
    if (_leaving || _model.busy || _confirmingDelete) return false;
    setState(() => _leaving = true);
    FocusManager.instance.primaryFocus?.unfocus();
    final saved = await _model.flush();
    if (!mounted) return false;
    if (!saved) {
      setState(() => _leaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存失败，已保留编辑内容。请处理后重试返回。')));
    }
    return saved;
  }

  Future<void> _leave() async {
    if (await _prepareToLeave() && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _chooseDate() async {
    if (_leaving || _choosingDate || _confirmingDelete || _model.busy) return;
    _choosingDate = true;
    FocusManager.instance.primaryFocus?.unfocus();
    final date = _model.date;
    DateTime? selected;
    try {
      selected = await showDatePicker(
        context: context,
        initialDate: DateTime(date.year, date.month, date.day),
        firstDate: DateTime(1),
        lastDate: DateTime(9999, 12, 31),
        confirmText: _model.entry == null ? '确定' : '确认修改',
      );
    } finally {
      _choosingDate = false;
    }
    if (!mounted || selected == null) return;
    final chosen = LocalDate.fromDateTime(selected);
    if (_model.entry != null) {
      await _changeDate(chosen);
    } else {
      _conflictAcknowledged = false;
      _model.chooseDate(chosen);
    }
  }

  Future<void> _changeDate(LocalDate date) async {
    if (_leaving || _confirmingDelete || _model.busy || date == _model.date) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _conflictAcknowledged = false;
    if (await _model.changeDate(date) && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('日记日期已修改，可继续编辑')));
    }
  }

  Future<void> _delete() async {
    if (_leaving ||
        _choosingDate ||
        _confirmingDelete ||
        _model.busy ||
        _model.entry == null) {
      return;
    }
    _confirmingDelete = true;
    FocusManager.instance.primaryFocus?.unfocus();
    bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('移入回收站？'),
          content: const Text('当前内容将先保存，再移入回收站。之后可以在回收站恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('移入回收站'),
            ),
          ],
        ),
      );
    } finally {
      _confirmingDelete = false;
    }
    if (!mounted || confirmed != true) return;
    if (await _model.deleteEntry() && mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _model.removeListener(_onModelChanged);
    _model.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) => PopScope<void>(
      // Always route back through flush: input can change before the next frame
      // has rebuilt PopScope's state.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: _leaving || _model.busy ? null : _leave,
          ),
          title: Text(_model.entry == null ? '新建日记' : '编辑日记'),
          actions: [
            if (_model.entry != null)
              IconButton(
                tooltip: '删除日记',
                onPressed: _leaving || _model.busy ? null : _delete,
                icon: const Icon(Icons.delete_outline),
              ),
            TextButton(
              onPressed: _leaving || _model.busy ? null : _leave,
              child: const Text('保存并返回'),
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _leaving || _model.busy,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('日记日期：${_model.date}')),
                      if (_model.canChooseDate || _model.entry != null)
                        TextButton(
                          key: const ValueKey('diary-date'),
                          onPressed: _model.busy ? null : _chooseDate,
                          child: Text(_model.entry == null ? '选择日期' : '修改日期'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('diary-title'),
                    controller: _title,
                    onChanged: _model.setTitle,
                    decoration: const InputDecoration(
                      labelText: '标题（可选）',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('diary-body'),
                    controller: _body,
                    onChanged: _model.setBody,
                    keyboardType: TextInputType.multiline,
                    minLines: 10,
                    maxLines: null,
                    decoration: const InputDecoration(
                      labelText: '正文',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_model.saving) const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    switch (_model.status) {
                      DiarySaveStatus.empty => '输入后自动保存',
                      DiarySaveStatus.pending => '未保存',
                      DiarySaveStatus.saving => '保存中…',
                      DiarySaveStatus.saved => '已保存',
                      DiarySaveStatus.failed => _model.error!,
                      DiarySaveStatus.deleted => '已移入回收站',
                    },
                    key: const ValueKey('diary-save-status'),
                    style: _model.error == null
                        ? null
                        : TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  if (_model.status == DiarySaveStatus.failed)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () {
                          if (_model.deleteFailed) {
                            unawaited(_delete());
                            return;
                          }
                          final failedDate = _model.failedDate;
                          if (failedDate != null) {
                            unawaited(_changeDate(failedDate));
                          } else {
                            unawaited(_model.flush());
                          }
                        },
                        child: Text(
                          _model.deleteFailed
                              ? '重试删除'
                              : _model.failedDate == null
                              ? '重试保存'
                              : '重试修改日期',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
