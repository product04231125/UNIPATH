import 'dart:typed_data';

/// Owner-scoped download of a saved 내 자료 PDF.
abstract interface class MaterialFileGateway {
  Future<Uint8List> materialFile(String id);
}
