import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/word_export_gateway.dart';
import 'package:university_path_frontend/features/writing/writing_api.dart';

import 'support/auth_fixture.dart';

// Synthetic loopback transport only. No deployed service.
void main() {
  test(
    'Word export posts the edited draft as the owner and checks the file',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var exports = 0;
      var valid = true;
      server.listen((request) async {
        final text = await utf8.decoder.bind(request).join();
        if (request.uri.path == '/api/v1/auth/login') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({...identityJson(), 'access_token': token}),
          );
        } else if (request.uri.path.endsWith('/logout')) {
          request.response.statusCode = 204;
        } else {
          expect(request.uri.path, '/api/v1/me/writing-exports');
          expect(request.method, 'POST');
          expect(request.headers.value('Authorization'), 'Bearer $token');
          expect(request.headers.value('X-Unipath-Owner'), userId);
          final body = jsonDecode(text) as Map;
          expect(body['reviewed'], true);
          expect(body['profile'], {
            'name': '가상 지원자',
            'email': '',
            'phone': '',
            'link': '',
          });
          expect(body['draft'], {
            'sections': [
              {
                'heading': '경험',
                'paragraphs': [
                  {'text': '직접 고친 문단', 'citations': []},
                ],
                'facts': [],
              },
            ],
          });
          exports++;
          request.response.headers.set('content-type', wordMime);
          request.response.add(valid ? [0x50, 0x4B, 3, 4, 0] : [0x3C, 0x68]);
        }
        await request.response.close();
      });
      final auth = AuthApi(
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
        cookieMode: false,
      );
      const draft = WritingDraft(
        sections: [
          WritingSection(
            heading: '경험',
            paragraphs: [WritingPart(text: '직접 고친 문단')],
          ),
        ],
      );
      try {
        await auth.authenticate(
          email: 'synthetic@example.test',
          password: 'synthetic test password',
        );
        final api = WritingApi(
          StudentApi(auth.forOwner(userId), ownerId: userId),
        );
        final bytes = await api.exportWord(
          WritingType.portfolio,
          draft,
          name: '가상 지원자',
        );
        expect(bytes.take(4), [0x50, 0x4B, 3, 4]);
        valid = false;
        await expectLater(
          api.exportWord(WritingType.portfolio, draft, name: '가상 지원자'),
          throwsA(isA<AuthFailure>()),
        );
        await auth.logout();
        await expectLater(
          api.exportWord(WritingType.portfolio, draft, name: '가상 지원자'),
          throwsA(isA<AuthFailure>()),
        );
        expect(exports, 2);
      } finally {
        auth.close();
        await server.close(force: true);
      }
    },
  );
}
