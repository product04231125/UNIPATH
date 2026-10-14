import 'dart:ui';
import 'dart:math' as math;

/// Logical work areas exclude taskbars. No physical-pixel assumptions here.
Rect restoreMainBounds(Rect? saved, List<Rect> areas) {
  final target = saved == null
      ? areas.first
      : areas.reduce(
          (a, b) => _overlap(a, saved) >= _overlap(b, saved) ? a : b,
        );
  final width = math
      .min(saved?.width ?? 1440, target.width - 16)
      .clamp(1.0, target.width)
      .toDouble();
  final height = math
      .min(saved?.height ?? 900, target.height - 16)
      .clamp(1.0, target.height)
      .toDouble();
  final left = (saved?.left ?? target.left + (target.width - width) / 2)
      .clamp(target.left, target.right - width)
      .toDouble();
  final top = (saved?.top ?? target.top + (target.height - height) / 2)
      .clamp(target.top, target.bottom - height)
      .toDouble();
  return Rect.fromLTWH(left, top, width, height);
}

double _overlap(Rect a, Rect b) {
  final rect = a.intersect(b);
  return rect.isEmpty ? 0 : rect.width * rect.height;
}

Rect? detachedChatBounds(Rect main, List<Rect> areas, double requestedWidth) {
  final width = requestedWidth.clamp(300.0, 480.0);
  for (final area in areas) {
    final left = main.right + 8;
    if (area.height < 520 || left < area.left || left + width > area.right) {
      continue;
    }
    final height = main.height.clamp(520.0, area.height);
    final top = main.top.clamp(area.top, area.bottom - height);
    final candidate = Rect.fromLTWH(left, top, width, height);
    if (!candidate.overlaps(main)) return candidate;
  }
  return null;
}
