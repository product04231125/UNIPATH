import 'dart:typed_data';

/// Owner-scoped download of a saved 내 자료 PDF and its page images.
abstract interface class MaterialFileGateway {
  Future<Uint8List> materialFile(String id);

  /// Page [number] (1-based) of the saved PDF, rendered by the server as WebP.
  Future<Uint8List> materialPage(String id, int number);
}

/// A WebP file is a RIFF container with the WEBP form type.
bool isWebp(Uint8List bytes) =>
    bytes.length >= 12 &&
    String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
    String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
