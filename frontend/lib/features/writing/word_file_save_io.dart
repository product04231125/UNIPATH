import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Desktop: the student picks where to save. Elsewhere the file opens from a temporary copy.
Future<bool> saveWordFile(Uint8List bytes, String filename) async {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    final location = await getSaveLocation(
      suggestedName: filename,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Word 문서', extensions: ['docx']),
      ],
    );
    if (location == null) return false;
    var path = location.path;
    if (!path.toLowerCase().endsWith('.docx')) path += '.docx';
    await File(path).writeAsBytes(bytes, flush: true);
    return true;
  }
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes, flush: true);
  return launchUrl(file.uri, mode: LaunchMode.externalApplication);
}
