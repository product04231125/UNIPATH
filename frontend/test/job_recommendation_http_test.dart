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
    server.listen((request) async {
      final text = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/v1/auth/login') {
        request.response.write(
          jsonEncode({...identityJson(), 'access_token': token}),
        );
      } else if (request.uri.path.endsWith('/logout')) {
        request.response.statusCode = 204;
      } else {
        expect(request.uri.path, '/api/v1/me/job-recommendations');
        expect(request.method, 'POST');
        expect(request.headers.value('Authorization'), 'Bearer $token');
        expect(request.headers.value('X-Unipath-Owner'), userId);
        final body = jsonDecode(text) as Map;
        expect(body['external_processing_consent'], true);
        expect(body['region'], '전국');
        expect(body.containsKey('region_codes'), false);
        expect(
          utf8.decode(
            base64Decode(body['documents'][0]['content_base64'] as String),
          ),
          'synthetic',
        );
        posts++;
        request.response.write(jsonEncode({'status': 'not_configured'}));
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
      final request = JobRecommendationRequest(
        keyword: 'Engineer',
        region: '전국',
        consent: true,
        documents: [
          RecommendationDocument(
            'synthetic.txt',
            Uint8List.fromList(utf8.encode('synthetic')),
          ),
        ],
      );
      expect((await api.recommend(request)).status, 'not_configured');
      await auth.logout();
      await expectLater(api.recommend(request), throwsA(isA<AuthFailure>()));
      expect(posts, 1);
    } finally {
      auth.close();
      await server.close(force: true);
    }
  });
}
