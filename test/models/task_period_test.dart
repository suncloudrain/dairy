import 'package:dairy/models/local_date.dart';
import 'package:dairy/models/task_period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calendar parsing rejects normalized and malformed dates', () {
    expect(() => LocalDate.parse('2026-02-29'), throwsFormatException);
    expect(() => LocalDate.parse('2026-13-01'), throwsFormatException);
    expect(() => LocalDate.parse('2026-1-01'), throwsFormatException);
    expect(() => LocalDate(0, 1, 1), throwsArgumentError);
    expect(LocalDate.parse('2024-02-29').toString(), '2024-02-29');
  });

  test('natural periods handle leap years and year boundaries', () {
    expect(
      TaskPeriod.day(LocalDate(2024, 2, 29)).endExclusive,
      LocalDate(2024, 3, 1),
    );
    expect(TaskPeriod.month(2024, 2).days, 29);
    expect(TaskPeriod.month(2026, 2).days, 28);
    expect(TaskPeriod.month(2026, 12).endExclusive, LocalDate(2027, 1, 1));
    expect(TaskPeriod.year(2024).days, 366);
  });

  test(
    'custom period counts its first day and crosses month/year boundaries',
    () {
      final period = TaskPeriod.custom(LocalDate(2026, 10, 7), 5);
      expect(period.lastDay, LocalDate(2026, 10, 11));
      expect(period.endExclusive, LocalDate(2026, 10, 12));
      expect(
        TaskPeriod.custom(LocalDate(2026, 12, 30), 5).lastDay,
        LocalDate(2027, 1, 3),
      );
      expect(
        TaskPeriod.custom(LocalDate(2026, 10, 1), 30).endExclusive,
        isNot(TaskPeriod.month(2026, 10).endExclusive),
      );
    },
  );

  test('custom duration and type-aligned ranges are validated', () {
    expect(
      () => TaskPeriod.custom(LocalDate(2026, 1, 1), 0),
      throwsArgumentError,
    );
    expect(
      () => TaskPeriod.custom(LocalDate(2026, 1, 1), -1),
      throwsArgumentError,
    );
    expect(
      () => TaskPeriod(
        type: TaskType.month,
        start: LocalDate(2026, 1, 2),
        endExclusive: LocalDate(2026, 2, 1),
      ),
      throwsArgumentError,
    );
    expect(
      () => TaskPeriod(
        type: TaskType.day,
        start: LocalDate(2026, 1, 1),
        endExclusive: LocalDate(2026, 1, 3),
      ),
      throwsArgumentError,
    );
    expect(
      () => TaskPeriod.custom(LocalDate(9999, 12, 31), 1),
      throwsArgumentError,
    );
  });
}
