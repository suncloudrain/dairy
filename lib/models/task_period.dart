import 'local_date.dart';

enum TaskType {
  day('DAY'),
  month('MONTH'),
  year('YEAR'),
  custom('CUSTOM');

  const TaskType(this.databaseValue);
  final String databaseValue;

  static TaskType fromDatabase(String value) =>
      values.firstWhere((type) => type.databaseValue == value);
}

/// Includes [start], excludes [endExclusive]. Always represents one task.
final class TaskPeriod {
  factory TaskPeriod({
    required TaskType type,
    required LocalDate start,
    required LocalDate endExclusive,
  }) {
    if (start.compareTo(endExclusive) >= 0) {
      throw ArgumentError('The end must be after the start.');
    }
    final valid = switch (type) {
      TaskType.day => endExclusive == start.addDays(1),
      TaskType.month => start.day == 1 && endExclusive == _nextMonth(start),
      TaskType.year =>
        start.month == 1 &&
            start.day == 1 &&
            endExclusive == LocalDate(start.year + 1, 1, 1),
      TaskType.custom => true,
    };
    if (!valid) throw ArgumentError('Range does not match the task type.');
    return TaskPeriod._(type, start, endExclusive);
  }

  const TaskPeriod._(this.type, this.start, this.endExclusive);

  factory TaskPeriod.day(LocalDate date) => TaskPeriod(
    type: TaskType.day,
    start: date,
    endExclusive: date.addDays(1),
  );

  factory TaskPeriod.month(int year, int month) {
    final start = LocalDate(year, month, 1);
    return TaskPeriod(
      type: TaskType.month,
      start: start,
      endExclusive: _nextMonth(start),
    );
  }

  factory TaskPeriod.year(int year) => TaskPeriod(
    type: TaskType.year,
    start: LocalDate(year, 1, 1),
    endExclusive: LocalDate(year + 1, 1, 1),
  );

  factory TaskPeriod.custom(LocalDate start, int days) {
    if (days <= 0) throw ArgumentError.value(days, 'days', 'Must be positive');
    return TaskPeriod(
      type: TaskType.custom,
      start: start,
      endExclusive: start.addDays(days),
    );
  }

  static LocalDate _nextMonth(LocalDate date) => date.month == 12
      ? LocalDate(date.year + 1, 1, 1)
      : LocalDate(date.year, date.month + 1, 1);

  final TaskType type;
  final LocalDate start;
  final LocalDate endExclusive;
  int get days => start.daysUntil(endExclusive);
  LocalDate get lastDay => endExclusive.addDays(-1);
}
