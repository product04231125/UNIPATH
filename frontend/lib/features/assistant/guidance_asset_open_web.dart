import 'dart:async';
import 'dart:js_interop';

import '../auth/guidance_asset_gateway.dart';

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts, _BlobOptions options);
}

@JS()
extension type _BlobOptions._(JSObject _) implements JSObject {
  external factory _BlobOptions({String type});
}

@JS('URL.createObjectURL')
external JSString _create(_Blob blob);
@JS('URL.revokeObjectURL')
external void _revoke(JSString url);
@JS('window.open')
external JSObject? _open(JSString url, JSString target, JSString features);

Future<bool> openGuidancePdf(GuidanceAsset asset, String id) async {
  if (asset.contentType != 'application/pdf') return false;
  final url = _create(
    _Blob(
      <JSAny>[asset.bytes.toJS].toJS,
      _BlobOptions(type: 'application/pdf'),
    ),
  );
  final opened = _open(url, '_blank'.toJS, 'noopener'.toJS);
  // No bearer token or server URL is placed in the new browser tab.
  Timer(const Duration(minutes: 5), () => _revoke(url));
  // noopener may deliberately return null; opening is best-effort in browsers.
  return opened != null;
}
