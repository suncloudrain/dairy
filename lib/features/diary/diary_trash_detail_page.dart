import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/repositories/diary_repository.dart';
import '../../models/diary_entry.dart';
import 'diary_editor_page.dart';
import 'diary_trash_detail_model.dart';

class DiaryTrashDetailPage extends StatefulWidget {
  const DiaryTrashDetailPage({
    super.key,
    required this.repository,
    required this.entry,
  });
  final DiaryRepository repository;
  final DiaryEntry entry;

  @override
  State<DiaryTrashDetailPage> createState() => _DiaryTrashDetailPageState();
}

class _DiaryTrashDetailPageState extends State<DiaryTrashDetailPage> {
  late final DiaryTrashDetailModel _model;
  bool _copying = false;
  bool _opening = false;
  bool get _enabled =>
      !_model.busy && !_model.restored && !_copying && !_opening;

  @override
  void initState() {
    super.initState();
    _model = DiaryTrashDetailModel(widget.repository, entry: widget.entry);
  }

  void _leave() {
    if (_enabled) Navigator.of(context).pop();
  }

  Future<void> _restore() async {
    if (!_enabled) return;
    if (await _model.restore()) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!mounted || !_model.conflict) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('原日期已有日记'),
        content: const Text('无法恢复到该日期，两篇日记都已保留。可以手动复制正文，再打开现有日记自行整理。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _copy() async {
    if (!_enabled) return;
    setState(() => _copying = true);
    try {
      await Clipboard.setData(ClipboardData(text: widget.entry.body));
      if (mounted) _message('正文已复制');
    } catch (_) {
      if (mounted) _message('复制失败，请重试。');
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _openExisting() async {
    if (!_enabled) return;
    setState(() => _opening = true);
    try {
      final existing = await _model.findExisting();
      if (!mounted || existing == null) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => DiaryEditorPage(
            repository: widget.repository,
            date: existing.date,
            entry: existing,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) {
      final entry = widget.entry;
      final deletedAt = entry.deletedAt!.toLocal();
      final localizations = MaterialLocalizations.of(context);
      final deletedLabel =
          '${localizations.formatCompactDate(deletedAt)} ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(deletedAt), alwaysUse24HourFormat: true)}';
      return PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('已删除日记'),
            leading: BackButton(onPressed: _enabled ? _leave : null),
            actions: [
              TextButton(
                onPressed: _enabled ? _restore : null,
                child: const Text('恢复'),
              ),
            ],
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (entry.title != null) ...[
                    SelectableText(
                      entry.title!,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text('原日记日期：${entry.date}'),
                  Text('删除时间：$deletedLabel'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _enabled ? _copy : null,
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('复制正文'),
                      ),
                      if (_model.conflict)
                        OutlinedButton(
                          onPressed: _enabled ? _openExisting : null,
                          child: const Text('打开现有日记'),
                        ),
                    ],
                  ),
                  if (_model.busy || _copying) const LinearProgressIndicator(),
                  if (_model.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _model.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  SelectableText(
                    entry.body.isEmpty ? '暂无正文' : entry.body,
                    key: const ValueKey('diary-trash-body'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
