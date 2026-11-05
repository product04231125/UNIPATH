import 'package:sembast/sembast.dart';

Future<Database> openMaterialDatabase() =>
    Future.error(UnsupportedError('Local material storage is unavailable'));
