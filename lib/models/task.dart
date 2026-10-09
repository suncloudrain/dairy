import 'task_period.dart';

final class Task {
  const Task({
    required this.id,
    required this.title,
    this.notes,
    required this.period,
    required this.isCompleted,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String? notes;
  final TaskPeriod period;
  final bool isCompleted;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  bool get isDeleted => deletedAt != null;
}
