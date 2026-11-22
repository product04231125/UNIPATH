import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/job_recommendation_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';

import 'support/auth_fixture.dart';

// Synthetic loopback transport only. No deployed service or paid model.
void main() {
  test('recommendation HTTP uses authenticated owner and base64 payload; logout blocks reuse', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var posts = 0;
    var categoryGets = 0;
    server.listen((request) async {
      final text = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/v1/auth/login') {
        request.response.write(
          jsonEncode({...identityJson(), 'access_token': token}),
        );
      } else if (request.uri.path.endsWith('/logout')) {
        request.response.statusCode = 204;
      } else if (request.uri.path == '/api/v1/me/job-categories') {
        expect(request.method, 'GET');
        expect(request.headers.value('Authorization'), 'Bearer $token');
        expect(request.headers.value('X-Unipath-Owner'), userId);
        expect(text, isEmpty);
        categoryGets++;
        request.response.write(
          jsonEncode({
            'categories': [
              {
                'code': '02',
                'name': '연구 및 공학기술',
                'children': [
                  {'code': '024', 'name': '소프트웨어'},
                ],
              },
            ],
          }),
        );
      } else {
        expect(request.uri.path, '/api/v1/me/job-recommendations');
        expect(request.method, 'POST');
        expect(request.headers.value('Authorization'), 'Bearer $token');
        expect(request.headers.value('X-Unipath-Owner'), userId);
        final body = jsonDecode(text) as Map;
        expect(body['external_processing_consent'], true);
        expect(body['region'], '전국');
        expect(body['keyword'], '');
        expect(body['category_codes'], ['024']);
        expect(body.containsKey('region_codes'), false);
        expect(
          utf8.decode(
            base64Decode(body['documents'][0]['content_base64'] as String),
          ),
          'synthetic',
        );
        posts++;
        request.response.write(
          jsonEncode({
            'status': 'completed',
            'query': {
              'keyword': '',
              'occupation_codes': ['024'],
              'occupation_label': '소프트웨어',
            },
            'search_notice': null,
            'category_browse_available': false,
          }),
        );
      }
      await request.response.close();
    });
    final auth = AuthApi(
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      cookieMode: false,
    );
    try {
      await auth.authenticate(
        email: 'synthetic@example.test',
        password: 'synthetic test password',
      );
      final api = JobRecommendationApi(auth.forOwner(userId));
      final categories = await api.loadCategories();
      expect(categories.single.name, '연구 및 공학기술');
      final request = JobRecommendationRequest(
        keyword: '',
        region: '전국',
        categoryCodes: [categories.single.children.single.code],
        consent: true,
        documents: [
          RecommendationDocument(
            'synthetic.txt',
            Uint8List.fromList(utf8.encode('synthetic')),
          ),
        ],
      );
      final result = await api.recommend(request);
      expect(result.occupationLabel, '소프트웨어');
      expect(result.occupationCodes, ['024']);
      expect(result.queryKeyword, '');
      expect(result.searchNotice, isNull);
      expect(result.categoryBrowseAvailable, isFalse);
      await auth.logout();
      await expectLater(api.recommend(request), throwsA(isA<AuthFailure>()));
      await expectLater(api.loadCategories(), throwsA(isA<AuthFailure>()));
      expect(categoryGets, 1);
      expect(posts, 1);
    } finally {
      auth.close();
      await server.close(force: true);
    }
  });
}
