import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/app_shell/workspace_title_bar.dart';
import 'package:university_path_frontend/features/settings/settings_page.dart';
import 'package:university_path_frontend/features/assistant/assistant_panel.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/shared/widgets/responsive_columns.dart';
import 'package:university_path_frontend/shared/widgets/task_focus_group.dart';
import 'package:university_path_frontend/shared/widgets/input_dialog.dart';

bool inWidget(Type type) {
  var found = false;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((element) {
    if (element.widget.runtimeType == type) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

Future<void> tab(WidgetTester tester, {bool reverse = false}) async {
  if (reverse) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (reverse) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('AI is after body and before top bar; close restores opener', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const UniversityPathApp(startAuthenticated: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    final opener = find.byType(FloatingActionButton);
    await tester.tap(opener);
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('홈'))).requestFocus();
    await tester.pump();
    var body = false, ai = false, top = false;
    for (var i = 0; i < 80; i++) {
      await tab(tester);
      if (inWidget(SettingsPage)) {
        expect(ai, isFalse);
        body = true;
      }
      if (inWidget(AssistantPanel)) {
        expect(body, isTrue);
        ai = true;
      }
      if (inWidget(WorkspaceTitleBar)) {
        expect(ai, isTrue);
        top = true;
        break;
      }
    }
    expect(top, isTrue);
    await tester.tap(find.byTooltip('AI 도우미 닫기'));
    await tester.pumpAndSettle();
    expect(
      Focus.of(tester.element(find.byIcon(Icons.chat_bubble_outline))).hasFocus,
      isTrue,
    );
  });
  testWidgets(
    'admin navigation body then title at expanded and compact sizes',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      await tester.pumpWidget(const UniversityPathApp());
      await tester.pumpAndSettle();
      final entry = find.byKey(const Key('sample-super-admin-entry'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      for (final size in [const Size(1440, 900), const Size(480, 520)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpAndSettle();
        final start = size.width > 760
            ? find
                  .descendant(
                    of: find.byKey(
                      const ValueKey('admin-menu-/admin/overview'),
                    ),
                    matching: find.byType(Text),
                  )
                  .first
            : find.descendant(
                of: find.byTooltip('관리 현황'),
                matching: find.byType(Icon),
              );
        Focus.of(tester.element(start)).requestFocus();
        await tester.pump();
        var body = false, top = false;
        for (var i = 0; i < 80; i++) {
          await tab(tester);
          if (inWidget(AdminWorkspace)) body = true;
          if (inWidget(WorkspaceTitleBar)) {
            expect(body, isTrue);
            top = true;
            break;
          }
        }
        expect(top, isTrue);
      }
      expect(tester.takeException(), isNull);
    },
  );
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'left column completes before right and Shift Tab reverses across resize',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final nodes = List.generate(4, (_) => FocusNode());
      addTearDown(() {
        for (final node in nodes) {
          node.dispose();
        }
      });
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskFocusGroup(
              child: ResponsiveColumns(
                enabled: true,
                first: Column(
                  children: [
                    TextField(focusNode: nodes[0]),
                    TextField(focusNode: nodes[1]),
                  ],
                ),
                second: Column(
                  children: [
                    TextField(focusNode: nodes[2]),
                    TextField(focusNode: nodes[3]),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      for (final size in [const Size(1000, 700), const Size(480, 520)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpAndSettle();
        nodes[0].requestFocus();
        await tester.pump();
        for (var i = 1; i < 4; i++) {
          await tab(tester);
          expect(nodes[i].hasFocus, isTrue);
        }
        for (var i = 2; i >= 0; i--) {
          await tab(tester, reverse: true);
          expect(nodes[i].hasFocus, isTrue);
        }
      }
    },
  );
  testWidgets(
    'student sidebar then settings then top bar with hidden pages skipped',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const UniversityPathApp(startAuthenticated: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('수강 관리').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('설정'));
      await tester.pumpAndSettle();
      Focus.of(tester.element(find.text('홈'))).requestFocus();
      await tester.pump();
      var sawSettings = false, sawTitle = false;
      for (var i = 0; i < 60; i++) {
        await tab(tester);
        if (inWidget(SettingsPage)) sawSettings = true;
        if (inWidget(WorkspaceTitleBar)) {
          expect(sawSettings, isTrue);
          sawTitle = true;
          break;
        }
      }
      expect(sawTitle, isTrue);
      await tab(tester, reverse: true);
      expect(inWidget(SettingsPage), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('modal cycles inside form then cancel save and restores opener', (
    tester,
  ) async {
    final opener = FocusNode(),
        field = FocusNode(),
        cancel = FocusNode(),
        save = FocusNode();
    for (final node in [opener, field, cancel, save]) {
      addTearDown(node.dispose);
    }
    final changes = ValueNotifier(0);
    addTearDown(changes.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              focusNode: opener,
              onPressed: () => showInputDialog<void>(
                context: context,
                builder: (context) => InputDialog(
                  title: const Text('입력'),
                  content: TextField(focusNode: field),
                  changes: changes,
                  hasContent: () => false,
                  actions: [
                    TextButton(
                      focusNode: cancel,
                      onPressed: () => InputDialog.cancel<void>(context),
                      child: const Text('취소'),
                    ),
                    FilledButton(
                      focusNode: save,
                      onPressed: () {},
                      child: const Text('저장'),
                    ),
                  ],
                ),
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    opener.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    field.requestFocus();
    await tester.pump();
    await tab(tester);
    expect(cancel.hasFocus, isTrue);
    await tab(tester);
    expect(save.hasFocus, isTrue);
    await tab(tester);
    expect(field.hasFocus, isTrue);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(opener.hasFocus, isTrue);
  });
}
