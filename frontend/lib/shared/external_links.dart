import 'package:url_launcher/url_launcher.dart';

/// Only browser URLs, never OS commands, files, or embedded credentials.
Uri? browserLink(String raw) {
  final value = raw.trim();
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(value) ||
      value.contains('\\')) {
    return null;
  }
  return uri;
}

typedef BrowserLinkOpener = Future<bool> Function(Uri uri);

Future<bool> openBrowserLink(Uri uri) => launchUrl(
  uri,
  mode: LaunchMode.externalApplication,
  webOnlyWindowName: '_blank',
);
