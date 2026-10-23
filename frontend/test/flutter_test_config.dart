import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:university_path_frontend/features/records/portfolio/material_database.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Widget tests must never access the user's app-support directory. Open the
  // isolated store before the widget test enters its fake asynchronous clock.
  var sequence = 0;
  Database? db;
  setUp(() async {
    db = await databaseFactoryMemory.openDatabase(
      'widget-materials-${sequence++}',
    );
    MaterialDatabase.open = () async => db!;
  });
  tearDown(() async {
    await db?.close();
  });
  await testMain();
}
