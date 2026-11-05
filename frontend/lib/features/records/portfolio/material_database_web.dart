import 'package:sembast_web/sembast_web.dart';

Future<Database>? _database;
Future<Database> openMaterialDatabase() => _database ??= databaseFactoryWeb
    .openDatabase('university_path.personal_materials.v1')
    .catchError((Object error) {
      _database = null;
      throw error;
    });
