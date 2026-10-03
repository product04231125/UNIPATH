import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/shared/widgets/content_scroll_view.dart';

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('scroll gutter protects content and thumb drags $direction', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: SizedBox(
                width: 400,
                height: 300,
                child: ContentScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < 30; i++)
                        SizedBox(
                          key: ValueKey(i),
                          height: 60,
                          width: double.infinity,
                          child: Text('기록 $i'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final content = tester.getRect(find.byKey(const ValueKey(0)));
      final viewport = tester.getRect(find.byType(ContentScrollView));
      expect(
        direction == TextDirection.ltr
            ? viewport.right - content.right
            : content.left - viewport.left,
        16,
      );
      expect(find.byType(Scrollbar), findsOneWidget);
      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      final controller = scroll.controller!;
      expect(controller.position.maxScrollExtent, greaterThan(0));
      final x = direction == TextDirection.ltr
          ? viewport.right - 3
          : viewport.left + 3;
      await tester.dragFrom(Offset(x, 15), const Offset(0, 130));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  }
}
