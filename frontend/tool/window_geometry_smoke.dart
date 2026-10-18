// Isolated native verification window. Does not read/write user preferences.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import 'package:university_path_frontend/app_shell/window_placement.dart';
import 'package:university_path_frontend/app_shell/workspace_title_bar.dart';

void require(bool value, String name) {
  if (!value) throw StateError(name);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const reportPath = String.fromEnvironment('NATIVE_REPORT_PATH');
  final report = File(
    reportPath.isEmpty
        ? '${Directory.systemTemp.path}/unipath_window_geometry_smoke.json'
        : reportPath,
  );
  await report.writeAsString(jsonEncode({'passed': false, 'phase': 'started'}));
  await windowManager.ensureInitialized();
  await report.writeAsString(
    jsonEncode({'passed': false, 'phase': 'window manager initialized'}),
  );
  await windowManager.setTitleBarStyle(
    TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await report.writeAsString(
    jsonEncode({'passed': false, 'phase': 'title bar hidden'}),
  );
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            WorkspaceTitleBar(),
            Expanded(child: Center(child: Text('합성 창 배치 검사'))),
          ],
        ),
      ),
    ),
  );
  try {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final displays = await screenRetriever.getAllDisplays();
    final areas = [
      for (final display in displays)
        Rect.fromLTWH(
          (display.visiblePosition ?? Offset.zero).dx,
          (display.visiblePosition ?? Offset.zero).dy,
          (display.visibleSize ?? display.size).width,
          (display.visibleSize ?? display.size).height,
        ),
    ];
    require(areas.isNotEmpty, 'display unavailable');
    final planned = restoreMainBounds(
      const Rect.fromLTWH(-9000, -9000, 640, 600),
      areas,
    );
    await windowManager.setBounds(planned);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final before = await windowManager.getBounds();
    require(
      (before.left - planned.left).abs() < 3 &&
          (before.top - planned.top).abs() < 3,
      'native restore',
    );
    final candidate = detachedChatBounds(before, areas, 360);
    final after = await windowManager.getBounds();
    require(before == after, 'main window must remain unchanged');
    require(candidate == null || !candidate.overlaps(before), 'peer overlap');
    final edge = Rect.fromLTWH(
      areas.first.right - 640,
      areas.first.top,
      640,
      600,
    );
    require(
      detachedChatBounds(edge, [areas.first], 360) == null,
      'space fallback',
    );
    await windowManager.maximize();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    require(await windowManager.isMaximized(), 'native maximize');
    await windowManager.unmaximize();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    require(!await windowManager.isMaximized(), 'native restore from maximize');
    await report.writeAsString(
      jsonEncode({
        'passed': true,
        'monitor_count': displays.length,
        'native_bounds_restore': true,
        'main_unchanged': true,
        'space_fallback': true,
        'native_maximize_restore': true,
        'dpr': windowManager.getDevicePixelRatio(),
      }),
    );
  } catch (error) {
    await report.writeAsString(
      jsonEncode({'passed': false, 'error': error.toString()}),
    );
  } finally {
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }
}
