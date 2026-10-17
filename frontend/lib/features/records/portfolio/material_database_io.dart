import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

Future<Database>? _database;
Future<Database> openMaterialDatabase() =>
    _database ??= _open().catchError((Object error) {
      _database = null;
      throw error;
    });
Future<Database> _open() async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return databaseFactoryIo.openDatabase(
    '${directory.path}${Platform.pathSeparator}personal_materials.v1.db',
  );
}
