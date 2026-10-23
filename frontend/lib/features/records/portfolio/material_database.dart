import 'package:sembast/sembast.dart';

import 'material_database_stub.dart'
    if (dart.library.io) 'material_database_io.dart'
    if (dart.library.js_interop) 'material_database_web.dart'
    as platform;

/// Platform storage boundary, injectable by embedding hosts and test harnesses.
class MaterialDatabase {
  static Future<Database> Function() open = platform.openMaterialDatabase;
}

Future<Database> openMaterialDatabase() => MaterialDatabase.open();
