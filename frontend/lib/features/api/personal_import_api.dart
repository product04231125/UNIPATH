import '../auth/auth_api.dart';
import 'personal_import_models.dart';

/// Construct for one account after explicit migration review and confirmation.
/// The caller preserves original local data and discards this on account change.
class PersonalImportApi {
  const PersonalImportApi(this.api, {required this.ownerId});
  final ApiGateway api;
  final String ownerId;
  static const _path = 'me/personal-imports';

  Future<PersonalImportReceipt> create(PersonalImportRequest request) async {
    if (request.sourceOwnerId != ownerId || !request.consentConfirmed) {
      throw ArgumentError('Confirm import from the current account first');
    }
    final result = PersonalImportReceipt.fromJson(
      (await api.request('POST', _path, request.toJson()))!,
    );
    return _verify(result, request.importId);
  }

  Future<PersonalImportReceipt> get(String importId) async => _verify(
    PersonalImportReceipt.fromJson(
      (await api.request('GET', '$_path/$importId'))!,
    ),
    importId,
  );

  PersonalImportReceipt _verify(PersonalImportReceipt receipt, String id) {
    final identities = receipt.mappings
        .map((value) => (value.resource, value.clientId))
        .toSet();
    if (receipt.ownerId != ownerId ||
        receipt.importId != id ||
        receipt.recordCount < 0 ||
        receipt.recordCount > 500 ||
        (receipt.recordCount == 0 && receipt.profileVersionAtImport == null) ||
        receipt.recordCount != receipt.mappings.length ||
        identities.length != receipt.mappings.length ||
        receipt.mappings.any((value) => value.versionAtImport < 1) ||
        (receipt.profileVersionAtImport != null &&
            receipt.profileVersionAtImport! < 1)) {
      throw const FormatException('Invalid personal import receipt');
    }
    return receipt;
  }
}
