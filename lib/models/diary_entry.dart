import 'local_date.dart';

final class DiaryEntry {
  const DiaryEntry({
    required this.id,
    this.title,
    required this.body,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String? title;
  final String body;
  final LocalDate date;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  bool get isDeleted => deletedAt != null;
}
