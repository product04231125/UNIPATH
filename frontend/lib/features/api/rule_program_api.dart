import '../auth/auth_api.dart';
import 'rule_program_models.dart';

/// Selects registered execution rules; it cannot assert official graduation.
class OfficialProgramApi {
  const OfficialProgramApi(this.api);
  final ApiGateway api;
  static const _path = 'catalog/rule-programs';

  Future<OfficialProgramSelection> select(
    OfficialSelectionContext context, {
    String? on,
  }) async {
    final query = Uri(
      queryParameters: {
        ...context.toJson().map(
          (key, value) => MapEntry(key, value.toString()),
        ),
        'on': ?on,
      },
    ).query;
    final result = OfficialProgramSelection.fromJson(
      (await api.request('GET', '$_path?$query'))!,
    );
    if (result.status == 'available' &&
        (result.programs.isEmpty || result.issues.isNotEmpty)) {
      throw const FormatException('Inconsistent execution catalogue selection');
    }
    for (final program in result.programs) {
      _validatePublic(program);
    }
    return result;
  }

  Future<OfficialPublicProgram> get(String id, {String? on}) async {
    final query = on == null
        ? ''
        : '?${Uri(queryParameters: {'on': on}).query}';
    final result = OfficialPublicProgram.fromJson(
      (await api.request('GET', '$_path/$id$query'))!,
    );
    _validatePublic(result);
    return result;
  }

  static void _validatePublic(OfficialPublicProgram program) {
    if (program.status != 'approved' || program.rules.isEmpty) {
      throw const FormatException('Public execution program is not approved');
    }
    for (final rule in program.rules) {
      if (rule.evidence.isEmpty) {
        throw const FormatException('Execution criterion lacks evidence');
      }
      for (final source in rule.evidence) {
        final uri = Uri.parse(source.sourceUrl);
        if (!{'http', 'https'}.contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            source.page < 1) {
          throw const FormatException('Invalid execution source citation');
        }
      }
    }
  }
}

class OfficialProgramAdminApi {
  const OfficialProgramAdminApi(this.api);
  final ApiGateway api;
  static const _path = 'admin/rule-programs';

  Future<OfficialProgramList> list({
    String? institutionId,
    String? ruleSetId,
    String? ruleId,
    String? status,
    String? cursor,
    int limit = 100,
  }) async {
    final query = Uri(
      queryParameters: {
        'institution_id': ?institutionId,
        'rule_set_id': ?ruleSetId,
        'rule_id': ?ruleId,
        'status': ?status,
        'cursor': ?cursor,
        'limit': '$limit',
      },
    ).query;
    return OfficialProgramList.fromJson(
      (await api.request('GET', '$_path?$query'))!,
    );
  }

  Future<OfficialProgramView> get(String id) async =>
      OfficialProgramView.fromJson((await api.request('GET', '$_path/$id'))!);
  Future<OfficialProgramView> create(OfficialProgramCreate payload) async =>
      OfficialProgramView.fromJson(
        (await api.request('POST', _path, payload.toJson()))!,
      );
  Future<OfficialProgramView> replace(
    String id,
    OfficialProgramReplace payload,
  ) async => OfficialProgramView.fromJson(
    (await api.request('PUT', '$_path/$id', payload.toJson()))!,
  );
  Future<OfficialProgramView> approve(
    String id,
    OfficialProgramApprove payload,
  ) async => OfficialProgramView.fromJson(
    (await api.request('POST', '$_path/$id/approve', payload.toJson()))!,
  );
  Future<OfficialProgramView> revoke(
    String id,
    OfficialProgramRevoke payload,
  ) async => OfficialProgramView.fromJson(
    (await api.request('POST', '$_path/$id/revoke', payload.toJson()))!,
  );
  Future<void> removeDraft(String id, {required int expectedVersion}) async {
    await api.request('DELETE', '$_path/$id?expected_version=$expectedVersion');
  }
}

class CertificateCatalogApi {
  const CertificateCatalogApi(this.api);
  final ApiGateway api;
  String get prefix => 'catalog';

  Future<CertificateRegistryProviderList> providers({
    String? query,
    String? cursor,
    int limit = 100,
  }) async {
    final filter = Uri(
      queryParameters: {'query': ?query, 'cursor': ?cursor, 'limit': '$limit'},
    ).query;
    return CertificateRegistryProviderList.fromJson(
      (await api.request('GET', '$prefix/certificate-providers?$filter'))!,
    );
  }

  Future<CertificateRegistryCertificateList> certificates({
    String? providerId,
    String? query,
    String? cursor,
    int limit = 100,
  }) async {
    final filter = Uri(
      queryParameters: {
        'provider_id': ?providerId,
        'query': ?query,
        'cursor': ?cursor,
        'limit': '$limit',
      },
    ).query;
    return CertificateRegistryCertificateList.fromJson(
      (await api.request('GET', '$prefix/certificates?$filter'))!,
    );
  }

  Future<CertificateRegistryProviderView> provider(String id) async =>
      CertificateRegistryProviderView.fromJson(
        (await api.request('GET', '$prefix/certificate-providers/$id'))!,
      );
  Future<CertificateRegistryCertificateView> certificate(String id) async =>
      CertificateRegistryCertificateView.fromJson(
        (await api.request('GET', '$prefix/certificates/$id'))!,
      );
}

class CertificateRegistryAdminApi extends CertificateCatalogApi {
  const CertificateRegistryAdminApi(super.api);
  @override
  String get prefix => 'admin';

  Future<CertificateRegistryProviderView> createProvider(
    CertificateRegistryProviderCreate payload,
  ) async => CertificateRegistryProviderView.fromJson(
    (await api.request(
      'POST',
      '$prefix/certificate-providers',
      payload.toJson(),
    ))!,
  );
  Future<CertificateRegistryCertificateView> createCertificate(
    CertificateRegistryCertificateCreate payload,
  ) async => CertificateRegistryCertificateView.fromJson(
    (await api.request('POST', '$prefix/certificates', payload.toJson()))!,
  );
  Future<CertificateRegistryProviderView> updateProvider(
    String id,
    CertificateRegistryRegistryUpdate payload,
  ) async => CertificateRegistryProviderView.fromJson(
    (await api.request(
      'PATCH',
      '$prefix/certificate-providers/$id',
      payload.toJson(),
    ))!,
  );
  Future<CertificateRegistryCertificateView> updateCertificate(
    String id,
    CertificateRegistryRegistryUpdate payload,
  ) async => CertificateRegistryCertificateView.fromJson(
    (await api.request('PATCH', '$prefix/certificates/$id', payload.toJson()))!,
  );
  Future<CertificateRegistryProviderView> setProviderActive(
    String id,
    bool active, {
    required int expectedVersion,
  }) async => CertificateRegistryProviderView.fromJson(
    (await api.request(
      'POST',
      '$prefix/certificate-providers/$id/${active ? 'activate' : 'deactivate'}',
      {'expected_version': expectedVersion},
    ))!,
  );
  Future<CertificateRegistryCertificateView> setCertificateActive(
    String id,
    bool active, {
    required int expectedVersion,
  }) async => CertificateRegistryCertificateView.fromJson(
    (await api.request(
      'POST',
      '$prefix/certificates/$id/${active ? 'activate' : 'deactivate'}',
      {'expected_version': expectedVersion},
    ))!,
  );
  Future<CertificateRegistryRegistryReferences> references(
    String id, {
    bool provider = false,
  }) async => CertificateRegistryRegistryReferences.fromJson(
    (await api.request(
      'GET',
      '$prefix/${provider ? 'certificate-providers' : 'certificates'}/$id/references',
    ))!,
  );
}
