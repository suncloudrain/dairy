enum RepositoryError { diaryDateConflict, recordUnavailable, invalidInput }

/// Expected business failures; storage failures retain their original exception.
final class RepositoryException implements Exception {
  const RepositoryException(this.code);
  final RepositoryError code;

  @override
  String toString() => 'RepositoryException(${code.name})';
}
