import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

const _detachedChatPrefix = 'university_path_ai_detached_chat:';
final _mainWindowMaximizeController = StreamController<bool>.broadcast();

Future<void> _shutdownTrace(String event) async {
  final file = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}UniversityPath_shutdown_trace.log',
  );
  await file.writeAsString(
    '${DateTime.now().toIso8601String()} dart: $event\n',
    mode: FileMode.append,
    flush: true,
  );
}

class _DetachedChatWindowConfig {
  const _DetachedChatWindowConfig({
    required this.width,
    required this.height,
    required this.left,
    required this.top,
  });

  final double width;
  final double height;
  final double left;
  final double top;

  String toArguments() =>
      '$_detachedChatPrefix${jsonEncode({'width': width, 'height': height, 'left': left, 'top': top})}';

  static bool matches(String arguments) =>
      arguments.startsWith(_detachedChatPrefix) ||
      arguments == 'university_path_ai_detached_chat';

  static _DetachedChatWindowConfig fromArguments(String arguments) {
    const fallback = _DetachedChatWindowConfig(
      width: 360,
      height: 720,
      left: 0,
      top: 0,
    );
    if (!arguments.startsWith(_detachedChatPrefix)) return fallback;
    try {
      final values = jsonDecode(
        arguments.substring(_detachedChatPrefix.length),
      ) as Map<String, dynamic>;
      double value(String key, double defaultValue) =>
          (values[key] as num?)?.toDouble() ?? defaultValue;
      return _DetachedChatWindowConfig(
        width: value('width', fallback.width),
        height: value('height', fallback.height),
        left: value('left', fallback.left),
        top: value('top', fallback.top),
      );
    } catch (_) {
      return fallback;
    }
  }
}

Future<bool> isDetachedChatWindow() async {
  final controller = await WindowController.fromCurrentEngine();
  return _DetachedChatWindowConfig.matches(controller.arguments);
}

Future<bool> hasDetachedChatWindow() async {
  final windows = await WindowController.getAll();
  return windows.any(
    (window) => _DetachedChatWindowConfig.matches(window.arguments),
  );
}

Stream<bool> detachedChatWindowChanges() async* {
  yield await hasDetachedChatWindow();
  await for (final _ in onWindowsChanged) {
    await WindowController.cleanupClosedWindows();
    yield await hasDetachedChatWindow();
  }
}

Future<void> initializeDetachedChatWindow() async {
  await windowManager.ensureInitialized();
  final controller = await WindowController.fromCurrentEngine();
  unawaited(_shutdownTrace('detached window initialized'));
  final config = _DetachedChatWindowConfig.fromArguments(controller.arguments);
  await controller.setWindowMethodHandler((call) async {
    if (call.method == 'focus_detached_chat') {
      await windowManager.show();
      await windowManager.restore();
      await windowManager.focus();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await windowManager.focus();
      return null;
    }
    if (call.method == 'close_detached_chat') {
      await _shutdownTrace('detached close requested by main');
      await windowManager.close();
      return null;
    }
    throw MissingPluginException(
      'Unknown detached chat command: ${call.method}',
    );
  });
  windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: Size(config.width, config.height),
      center: false,
      title: 'UniversityPath AI 도우미',
      skipTaskbar: true,
    ),
    () async {
      await windowManager.setSize(Size(config.width, config.height));
      await windowManager.setMinimumSize(const Size(300, 520));
      await windowManager.setPosition(Offset(config.left, config.top));
      await windowManager.setSkipTaskbar(true);
      await windowManager.setMaximizable(false);
      await windowManager.show();
      await windowManager.focus();
    },
  );
  windowManager.addListener(_detachedWindowCloseListener);
}

class _DetachedWindowCloseListener with WindowListener {
  @override
  void onWindowClose() {
    unawaited(_shutdownTrace('detached native close event received'));
    unawaited(_notifyMainDetachedWindowClosed());
  }
}

final _detachedWindowCloseListener = _DetachedWindowCloseListener();

Future<void> _notifyMainDetachedWindowClosed() async {
  final windows = await WindowController.getAll();
  for (final window in windows) {
    if (!_DetachedChatWindowConfig.matches(window.arguments)) {
      await window.invokeMethod<void>('detached_chat_closed');
      return;
    }
  }
}

class _MainWindowCloseListener with WindowListener {
  bool _closing = false;

  @override
  void onWindowClose() {
    unawaited(_shutdownTrace('main native close event received'));
    unawaited(_closeMainAndDetachedChat());
  }

  @override
  void onWindowMaximize() {
    _mainWindowMaximizeController.add(true);
    // A detached panel would otherwise float over the maximized workspace.
    // Return it to the in-window dock as soon as the main workspace expands.
    unawaited(_dockDetachedChatInMainWindow());
  }

  @override
  void onWindowUnmaximize() {
    _mainWindowMaximizeController.add(false);
  }

  Future<void> _closeMainAndDetachedChat() async {
    if (_closing) return;
    _closing = true;
    await _shutdownTrace(
      'main close workflow started; detached=$_mainDetachedChatOpen',
    );
    if (!_mainDetachedChatOpen) {
      await _shutdownTrace('no detached window; closing main native window');
      await windowManager.setPreventClose(false);
      await windowManager.close();
      return;
    }
    final windows = await WindowController.getAll();
    final closeCalls = windows
        .where((window) => _DetachedChatWindowConfig.matches(window.arguments))
        .map((window) async {
          try {
            await window
                .invokeMethod<void>('close_detached_chat')
                .timeout(const Duration(milliseconds: 50));
          } catch (_) {
            // The process shutdown below also clears an unresponsive child.
          }
        });
    await Future.wait(closeCalls);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await WindowController.cleanupClosedWindows();
    await _shutdownTrace(
      'detached close requests completed; closing main native window',
    );
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }
}

final _mainWindowCloseListener = _MainWindowCloseListener();
bool _mainDetachedChatOpen = false;
StreamSubscription<bool>? _mainDetachedChatSubscription;

Future<bool> isMainWindowMaximized() async {
  await windowManager.ensureInitialized();
  return windowManager.isMaximized();
}

Stream<bool> mainWindowMaximizeChanges() =>
    _mainWindowMaximizeController.stream;

Future<void> _dockDetachedChatInMainWindow() async {
  if (!_mainDetachedChatOpen) return;
  final windows = await WindowController.getAll();
  for (final window in windows) {
    if (_DetachedChatWindowConfig.matches(window.arguments)) {
      try {
        await window.invokeMethod<void>('close_detached_chat');
      } catch (_) {
        // The normal window-change listener will reconcile a child that has
        // already started closing.
      }
      return;
    }
  }
}

Future<void> initializeMainWindowCloseBehavior() async {
  await windowManager.ensureInitialized();
  // This is the smallest workspace that preserves the 220px navigation,
  // readable content area, and the 300px AI dock without layout collapse.
  await windowManager.setMinimumSize(const Size(1365, 768));
  final controller = await WindowController.fromCurrentEngine();
  await controller.setWindowMethodHandler((call) async {
    if (call.method == 'detached_chat_closed') {
      _mainDetachedChatOpen = false;
      await _shutdownTrace('main received detached close notification');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await WindowController.cleanupClosedWindows();
      await _shutdownTrace('closed detached engine cleaned up');
      return null;
    }
    throw MissingPluginException('Unknown main window command: ${call.method}');
  });
  _mainDetachedChatOpen = await hasDetachedChatWindow();
  _mainDetachedChatSubscription ??= detachedChatWindowChanges().listen((open) {
    _mainDetachedChatOpen = open;
  });
  await windowManager.setPreventClose(true);
  windowManager.addListener(_mainWindowCloseListener);
  unawaited(_shutdownTrace('main close listener initialized'));
}

Future<void> openDetachedChatWindow({double width = 360}) async {
  final windows = await WindowController.getAll();
  for (final window in windows) {
    if (_DetachedChatWindowConfig.matches(window.arguments)) {
      _mainDetachedChatOpen = true;
      await window.show();
      await window.invokeMethod<void>('focus_detached_chat');
      return;
    }
  }

  await windowManager.ensureInitialized();
  final mainPosition = await windowManager.getPosition();
  final mainSize = await windowManager.getSize();
  final chatWidth = width.clamp(300.0, 480.0);
  final mainCenter = Offset(
    mainPosition.dx + mainSize.width / 2,
    mainPosition.dy + mainSize.height / 2,
  );
  final displays = await screenRetriever.getAllDisplays();
  final display = displays.firstWhere((item) {
    final position = item.visiblePosition ?? Offset.zero;
    final size = item.visibleSize ?? item.size;
    return Rect.fromLTWH(
      position.dx,
      position.dy,
      size.width,
      size.height,
    ).contains(mainCenter);
  }, orElse: () => displays.first);
  final workPosition = display.visiblePosition ?? Offset.zero;
  final workSize = display.visibleSize ?? display.size;
  final rightEdge = workPosition.dx + workSize.width;
  final canOpenOnRight =
      mainPosition.dx + mainSize.width + chatWidth <= rightEdge;
  // getBounds() already returns logical pixels. Leave one physical pixel
  // between visible edges rather than fully overlapping the shadow frame.
  final visualFrameOverlap = 15 / windowManager.getDevicePixelRatio();
  final chatHeight = mainSize.height.clamp(420.0, workSize.height);
  final chatTop = (mainPosition.dy).clamp(
    workPosition.dy,
    workPosition.dy + workSize.height - chatHeight,
  );
  final config = _DetachedChatWindowConfig(
    width: chatWidth,
    height: chatHeight,
    // It is a peer window, not an overlay. Prefer the right edge and use the
    // left edge when the current display does not have enough room there.
    left: canOpenOnRight
        ? mainPosition.dx + mainSize.width - visualFrameOverlap
        : mainPosition.dx - chatWidth + visualFrameOverlap,
    top: chatTop,
  );
  await WindowController.create(
    WindowConfiguration(arguments: config.toArguments(), hiddenAtLaunch: true),
  );
  _mainDetachedChatOpen = true;
  // The child makes itself visible only after its Dart side has set the final
  // size and position. Showing it here causes a distracting default-position
  // flash before it moves to the right side.
}
