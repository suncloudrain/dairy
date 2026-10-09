import 'package:flutter/material.dart';

import '../../data/repositories/diary_repository.dart';
import '../../models/diary_entry.dart';
import '../../models/local_date.dart';
import 'diary_editor_page.dart';
import 'diary_list_model.dart';

class DiaryPage extends StatefulWidget {
  const DiaryPage({super.key, required this.repository, this.deleted = false});
  final DiaryRepository repository;
  final bool deleted;

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  late final DiaryListModel _model;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _model = DiaryListModel(widget.repository, deleted: widget.deleted)..load();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _openDate(
    LocalDate date, {
    DiaryEntry? entry,
    bool remind = false,
  }) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final existing = entry ?? await widget.repository.findByDate(date);
      if (!mounted) return;
      if (existing != null && remind) {
        final open = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('该日期已有日记'),
            content: const Text('每天可以写一篇日记。是否打开已有日记继续编辑？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('打开已有日记'),
              ),
            ],
          ),
        );
        if (!mounted || open != true) return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => DiaryEditorPage(
            repository: widget.repository,
            date: date,
            entry: existing,
          ),
        ),
      );
      if (mounted) await _model.load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('打开日记失败，请重试。')));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _newDiary() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (mounted && selected != null) {
      await _openDate(LocalDate.fromDateTime(selected), remind: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.deleted ? '日记回收站' : '日记'),
      actions: [
        if (!widget.deleted)
          IconButton(
            tooltip: '新建日记',
            icon: const Icon(Icons.add),
            onPressed: _opening ? null : _newDiary,
          ),
        if (!widget.deleted)
          IconButton(
            tooltip: '回收站',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) =>
                      DiaryPage(repository: widget.repository, deleted: true),
                ),
              );
              if (mounted) await _model.load();
            },
          ),
        IconButton(
          tooltip: '刷新',
          onPressed: _model.load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: widget.deleted
        ? null
        : FloatingActionButton(
            onPressed: _opening
                ? null
                : () => _openDate(LocalDate.fromDateTime(DateTime.now())),
            tooltip: '写今天',
            child: const Icon(Icons.edit_outlined),
          ),
    body: ListenableBuilder(
      listenable: _model,
      builder: (context, _) {
        if (_model.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_model.error != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_model.error!),
                TextButton(onPressed: _model.load, child: const Text('重试')),
              ],
            ),
          );
        }
        if (_model.entries.isEmpty) {
          return Center(child: Text(widget.deleted ? '回收站为空' : '暂无日记'));
        }
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: ListView.builder(
              itemCount: _model.entries.length,
              itemBuilder: (context, index) {
                final entry = _model.entries[index];
                final hasTitle = entry.title?.trim().isNotEmpty ?? false;
                final preview = entry.body.trim().isEmpty ? '暂无正文' : entry.body;
                return ListTile(
                  onTap: widget.deleted || _opening
                      ? null
                      : () => _openDate(entry.date, entry: entry),
                  title: Text(hasTitle ? entry.title! : entry.date.toString()),
                  subtitle: Text(
                    hasTitle ? '${entry.date}\n$preview' : preview,
                    maxLines: hasTitle ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: hasTitle,
                );
              },
            ),
          ),
        );
      },
    ),
  );
}
