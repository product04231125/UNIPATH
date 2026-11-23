import 'dart:typed_data';

import '../auth/file_export_gateway.dart';

/// Saves a file the student exported; false when cancelled or unsupported.
Future<bool> saveExportFile(
  Uint8List bytes,
  String filename,
  ExportFormat format,
) async => false;
