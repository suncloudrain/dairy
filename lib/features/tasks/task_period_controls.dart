import 'package:flutter/material.dart';

import '../../models/local_date.dart';
import '../../models/task_period.dart';

String taskTypeLabel(TaskType type) => switch (type) {
  TaskType.day => '日任务',
  TaskType.month => '月任务',
  TaskType.year => '年任务',
  TaskType.custom => '自定义',
};

String taskPeriodLabel(TaskPeriod period) => switch (period.type) {
  TaskType.day => period.start.toString(),
  TaskType.month => '${period.start.year} 年 ${period.start.month} 月',
  TaskType.year => '${period.start.year} 年',
  TaskType.custom => '${period.start} 至 ${period.lastDay}，共 ${period.days} 天',
};

Future<LocalDate?> pickTaskDate(
  BuildContext context,
  TaskType type,
  LocalDate initial,
) async {
  if (type == TaskType.day || type == TaskType.custom) {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 30),
    );
    return selected == null ? null : LocalDate.fromDateTime(selected);
  }
  return showDialog<LocalDate>(
    context: context,
    builder: (_) => _PeriodDialog(type: type, initial: initial),
  );
}

class _PeriodDialog extends StatefulWidget {
  const _PeriodDialog({required this.type, required this.initial});
  final TaskType type;
  final LocalDate initial;
  @override
  State<_PeriodDialog> createState() => _PeriodDialogState();
}

class _PeriodDialogState extends State<_PeriodDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    _year = TextEditingController(text: widget.initial.year.toString());
    _month = widget.initial.month;
  }

  @override
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.type == TaskType.month ? '选择年月' : '选择年份'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('task-period-year'),
              controller: _year,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '年份'),
              validator: (text) {
                final year = int.tryParse(text ?? '');
                if (year == null || year < 1 || year > 9999) return '请输入有效年份。';
                try {
                  if (widget.type == TaskType.year) {
                    TaskPeriod.year(year);
                  } else {
                    TaskPeriod.month(year, _month);
                  }
                  return null;
                } on ArgumentError {
                  return '该范围的结束日期超出支持范围。';
                }
              },
            ),
            if (widget.type == TaskType.month)
              DropdownButtonFormField<int>(
                initialValue: _month,
                decoration: const InputDecoration(labelText: '月份'),
                items: [
                  for (var month = 1; month <= 12; month++)
                    DropdownMenuItem(value: month, child: Text('$month 月')),
                ],
                onChanged: (month) => setState(() => _month = month!),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(
              context,
              LocalDate(
                int.parse(_year.text),
                widget.type == TaskType.year ? 1 : _month,
                1,
              ),
            );
          }
        },
        child: const Text('确定'),
      ),
    ],
  );
}
