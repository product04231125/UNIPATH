import 'package:flutter/material.dart';

import '../../shared/app_tones.dart';

/// `2025.03 – 2026.06`, a single `2026.05.17`, or null when no dates exist.
String? recordPeriodLabel(String start, String end) {
  DateTime? parse(String v) => DateTime.tryParse(v.trim());
  final from = parse(start), to = parse(end);
  String day(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  String month(DateTime d) => '${d.year}.${d.month.toString().padLeft(2, '0')}';
  if (from == null && to == null) return null;
  if (from == null) return '~ ${day(to!)}';
  if (to == null) return '${day(from)} ~';
  if (from.year == to.year && from.month == to.month) {
    return from.day == to.day ? day(from) : '${day(from)} – ${to.day}일';
  }
  return '${month(from)} – ${month(to)}';
}

/// `120` / `7.5` without trailing zeros.
String recordNumber(String value) {
  final n = num.tryParse(value.trim());
  if (n == null) return value;
  return n == n.roundToDouble() ? '${n.round()}' : '$n';
}

/// Icon and color for an experience type typed by the student.
(IconData, AppTone) experienceVisual(String type) {
  if (type.contains('인턴') || type.contains('실습')) {
    return (Icons.work_outline, AppTone.accent);
  }
  if (type.contains('동아리') || type.contains('학회')) {
    return (Icons.groups_outlined, AppTone.warning);
  }
  if (type.contains('프로젝트') || type.contains('개발')) {
    return (Icons.code, AppTone.info);
  }
  return (Icons.star_outline, AppTone.accent);
}
