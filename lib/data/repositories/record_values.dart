import 'repository_exception.dart';

void validateRecordId(String id) {
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(id)) {
    throw const RepositoryException(RepositoryError.invalidInput);
  }
}

String? optionalText(String? value) =>
    value == null || value.trim().isEmpty ? null : value;
