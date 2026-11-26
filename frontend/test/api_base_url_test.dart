import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/api_base_url.dart';

void main() {
  test('loopback Web rewrites API host to match the page host', () {
    expect(
      resolveApiBaseUrl(
        Uri.parse('http://127.0.0.1:8010'),
        pageUri: Uri.parse('http://localhost:3000/'),
        web: true,
      ),
      Uri.parse('http://localhost:8010'),
    );
    expect(
      resolveApiBaseUrl(
        Uri.parse('http://localhost:8010'),
        pageUri: Uri.parse('http://127.0.0.1:3000/'),
        web: true,
      ),
      Uri.parse('http://127.0.0.1:8010'),
    );
  });

  test('non-web and non-loopback origins keep the configured API host', () {
    expect(
      resolveApiBaseUrl(
        Uri.parse('http://127.0.0.1:8010'),
        pageUri: Uri.parse('http://localhost:3000/'),
        web: false,
      ),
      Uri.parse('http://127.0.0.1:8010'),
    );
    expect(
      resolveApiBaseUrl(
        Uri.parse('http://127.0.0.1:8010'),
        pageUri: Uri.parse('http://192.168.0.10:3000/'),
        web: true,
      ),
      Uri.parse('http://127.0.0.1:8010'),
    );
    expect(
      resolveApiBaseUrl(
        Uri.parse('https://api.example.test'),
        pageUri: Uri.parse('http://localhost:3000/'),
        web: true,
      ),
      Uri.parse('https://api.example.test'),
    );
  });
}
