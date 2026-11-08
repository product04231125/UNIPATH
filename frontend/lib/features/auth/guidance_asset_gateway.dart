import 'dart:typed_data';

class GuidanceAsset {
  const GuidanceAsset(this.bytes, this.contentType);
  final Uint8List bytes;
  final String contentType;
}

abstract interface class GuidanceAssetGateway {
  Future<GuidanceAsset> guidanceAsset(String id);
}
