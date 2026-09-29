import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/main.dart';

void main() {
  testWidgets('renders the UniversityPath workspace', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const UniversityPathApp());
    expect(find.text('UniversityPath'), findsOneWidget);
    expect(find.text('정민서님, 오늘 무엇을 정리해볼까요?'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
