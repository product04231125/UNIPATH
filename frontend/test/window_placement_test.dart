import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/app_shell/window_placement.dart';

void main() {
  test(
    'right placement leaves main unchanged and falls back when insufficient',
    () {
      const area = Rect.fromLTWH(0, 0, 1920, 1040);
      const main = Rect.fromLTWH(40, 40, 1200, 900);
      final chat = detachedChatBounds(main, [area], 360)!;
      expect(chat.left, main.right + 8);
      expect(chat.overlaps(main), isFalse);
      expect(area.contains(chat.bottomRight - const Offset(1, 1)), isTrue);
      expect(
        detachedChatBounds(const Rect.fromLTWH(500, 0, 1440, 900), [area], 360),
        isNull,
      );
      expect(
        detachedChatBounds(main, [const Rect.fromLTWH(0, 0, 1920, 500)], 360),
        isNull,
      );
    },
  );
  test('restore handles removed monitors and negative logical coordinates', () {
    const left = Rect.fromLTWH(-1280, -120, 1280, 984);
    const right = Rect.fromLTWH(0, 0, 1920, 1040);
    final saved = const Rect.fromLTWH(-1200, -80, 900, 700);
    expect(restoreMainBounds(saved, [left, right]), saved);
    final restored = restoreMainBounds(saved, [right]);
    expect(restored.left, 0);
    expect(restored.top, 0);
    final large = restoreMainBounds(
      const Rect.fromLTWH(-4000, 5000, 3000, 2000),
      [left],
    );
    expect(left.contains(large.topLeft), isTrue);
    expect(left.contains(large.bottomRight - const Offset(1, 1)), isTrue);
  });
}
