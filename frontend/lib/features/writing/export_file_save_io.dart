import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/file_export_gateway.dart';

/// Desktop: the student picks where to save. Elsewhere the file opens from a temporary copy.
Future<bool> saveExportFile(
  Uint8List bytes,
  String filename,
  ExportFormat format,
) async {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    final location = await getSaveLocation(
      suggestedName: filename,
      acceptedTypeGroups: [
        XTypeGroup(label: '${format.label} 문서', extensions: [format.extension]),
      ],
    );
    if (location == null) return false;
    var path = location.path;
    if (!path.toLowerCase().endsWith('.${format.extension}')) {
      path += '.${format.extension}';
    }
    await File(path).writeAsBytes(bytes, flush: true);
    return true;
  }
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes, flush: true);
  return launchUrl(file.uri, mode: LaunchMode.externalApplication);
}
