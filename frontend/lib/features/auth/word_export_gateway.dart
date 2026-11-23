import 'dart:typed_data';

const wordMime =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

/// Owner-scoped JSON request whose response is an editable Word file.
abstract interface class WordExportGateway {
  Future<Uint8List> exportWord(String path, Map<String, Object?> body);
}
