import 'package:flutter/foundation.dart';

/// Compile-time API origin. Prefer injecting via `--dart-define=API_BASE_URL=...`.
Uri configuredApiBaseUrl() => Uri.parse(
  const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8010',
  ),
);

bool isLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}

/// Keep Web cookie sessions same-site on a single PC.
///
/// `localhost` and `127.0.0.1` are different browser sites. HttpOnly cookies use
/// SameSite=Strict, so a page on one loopback host cannot send cookies to the
/// other. When both the page and the configured API are loopback, rewrite the
/// API host to match the page host.
Uri resolveApiBaseUrl(Uri configured, {Uri? pageUri, bool? web}) {
  final isWeb = web ?? kIsWeb;
  if (!isWeb) return configured;
  final pageHost = (pageUri ?? Uri.base).host.toLowerCase();
  final apiHost = configured.host.toLowerCase();
  if (isLoopbackHost(pageHost) &&
      isLoopbackHost(apiHost) &&
      pageHost != apiHost) {
    return configured.replace(host: pageHost);
  }
  return configured;
}
