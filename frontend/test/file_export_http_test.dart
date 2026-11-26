import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/file_export_gateway.dart';
import 'package:university_path_frontend/features/writing/writing_api.dart';

import 'support/auth_fixture.dart';

// Synthetic loopback transport only. No deployed service.
void main() {
  test(
    'Word and PDF export post the edited draft as the owner and check the file',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var exports = 0;
      var valid = true;
      final formats = <String>[];
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
          formats.add(body['format'] as String);
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
          final pdf = body['format'] == 'pdf';
          request.response.headers.set(
            'content-type',
            pdf ? ExportFormat.pdf.mime : ExportFormat.docx.mime,
          );
          request.response.add(
            !valid
                ? [0x3C, 0x68]
                : pdf
                ? '%PDF-1.4'.codeUnits
                : [0x50, 0x4B, 3, 4, 0],
          );
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
        Future<List<int>> export(ExportFormat format) => api.exportFile(
          WritingType.portfolio,
          draft,
          format,
          name: '가상 지원자',
        );
        expect((await export(ExportFormat.docx)).take(4), [0x50, 0x4B, 3, 4]);
        expect(
          String.fromCharCodes((await export(ExportFormat.pdf)).take(5)),
          '%PDF-',
        );
        valid = false;
        await expectLater(
          export(ExportFormat.pdf),
          throwsA(isA<AuthFailure>()),
        );
        await auth.logout();
        await expectLater(
          export(ExportFormat.docx),
          throwsA(isA<AuthFailure>()),
        );
        expect(exports, 3);
        expect(formats, ['docx', 'pdf', 'pdf']);
      } finally {
        auth.close();
        await server.close(force: true);
      }
    },
  );
}
