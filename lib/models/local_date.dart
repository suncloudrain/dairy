/// A calendar date, independent of the device's time zone.
final class LocalDate implements Comparable<LocalDate> {
  factory LocalDate(int year, int month, int day) {
    final value = DateTime.utc(year, month, day);
    if (year < 1 ||
        year > 9999 ||
        value.year != year ||
        value.month != month ||
        value.day != day) {
      throw ArgumentError('Invalid calendar date: $year-$month-$day');
    }
    return LocalDate._(value);
  }

  const LocalDate._(this._value);

  factory LocalDate.parse(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw FormatException('Expected YYYY-MM-DD', value);
    }
    try {
      return LocalDate(
        int.parse(value.substring(0, 4)),
        int.parse(value.substring(5, 7)),
        int.parse(value.substring(8, 10)),
      );
    } on ArgumentError {
      throw FormatException('Invalid calendar date', value);
    }
  }

  factory LocalDate.fromDateTime(DateTime value) =>
      LocalDate(value.year, value.month, value.day);

  final DateTime _value;
  int get year => _value.year;
  int get month => _value.month;
  int get day => _value.day;

  LocalDate addDays(int days) {
    // UTC is an arithmetic carrier here, not a persisted midnight instant.
    final value = _value.add(Duration(days: days));
    return LocalDate(value.year, value.month, value.day);
  }

  int daysUntil(LocalDate other) => other._value.difference(_value).inDays;

  @override
  int compareTo(LocalDate other) => _value.compareTo(other._value);

  @override
  bool operator ==(Object other) =>
      other is LocalDate && _value == other._value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}
