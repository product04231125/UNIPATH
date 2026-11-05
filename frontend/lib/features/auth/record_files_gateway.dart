import 'dart:typed_data';

/// Captured-login transport for private record source PDFs. No local persistence.
abstract interface class RecordFilesGateway {
  Future<Map<String, dynamic>> upload(
    String path,
    Uint8List bytes, {
    required Map<String, Object?> metadata,
  });
  Future<Uint8List> download(String path);
}
