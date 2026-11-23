import 'dart:typed_data';

/// Files the server renders from the owner's edited draft.
enum ExportFormat {
  docx(
    'Word',
    'docx',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  ),
  pdf('PDF', 'pdf', 'application/pdf');

  const ExportFormat(this.label, this.extension, this.mime);
  final String label, extension, mime;

  /// A .docx file is a ZIP archive; a PDF starts with %PDF-.
  bool matches(Uint8List bytes) => switch (this) {
    docx =>
      bytes.length >= 4 &&
          bytes[0] == 0x50 &&
          bytes[1] == 0x4B &&
          bytes[2] == 3 &&
          bytes[3] == 4,
    pdf =>
      bytes.length >= 5 &&
          bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46 &&
          bytes[4] == 0x2D,
  };
}

/// Owner-scoped JSON request whose response is a rendered file.
abstract interface class FileExportGateway {
  Future<Uint8List> exportFile(
    String path,
    Map<String, Object?> body,
    ExportFormat format,
  );
}
