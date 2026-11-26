import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/guidance_asset_gateway.dart';

Future<bool> openGuidancePdf(GuidanceAsset asset, String id) async {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(id) ||
      asset.contentType != 'application/pdf') {
    return false;
  }
  final directory = await getTemporaryDirectory();
  final file = File(
    '${directory.path}${Platform.pathSeparator}unipath-guidance-$id.pdf',
  );
  await file.writeAsBytes(asset.bytes, flush: true);
  return launchUrl(file.uri, mode: LaunchMode.externalApplication);
}
