import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local personal planning data. It is deliberately separate from
/// school records and will be replaced by an API adapter once that contract is
/// available.
class PlanningRepository extends ChangeNotifier {
  PlanningRepository({this._preferences});

  static const _storageKey = 'university_path.personal_planning.v1';

  SharedPreferences? _preferences;
  bool _isLoading = true;
  PlanningProfile _profile = const PlanningProfile();
  List<PlanningEvent> _events = const [];

  bool get isLoading => _isLoading;
  PlanningProfile get profile => _profile;
  List<PlanningEvent> get events => List.unmodifiable(_events);

  Future<void> load() async {
    try {
      _preferences ??= await SharedPreferences.getInstance();
      final raw = _preferences!.getString(_storageKey);
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _profile = PlanningProfile.fromJson(
          Map<String, dynamic>.from(decoded['profile'] as Map? ?? const {}),
        );
        _events =
            (decoded['events'] as List? ?? const [])
                .whereType<Map>()
                .map(
                  (value) =>
                      PlanningEvent.fromJson(Map<String, dynamic>.from(value)),
                )
                .toList()
              ..sort((a, b) => a.start.compareTo(b.start));
      }
    } on FormatException {
      _profile = const PlanningProfile();
      _events = const [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveProfile(PlanningProfile profile) async {
    _profile = profile;
    await _save();
    notifyListeners();
  }

  Future<void> saveEvent(PlanningEvent event) async {
    final index = _events.indexWhere((item) => item.id == event.id);
    final updated = [..._events];
    if (index == -1) {
      updated.add(event);
    } else {
      updated[index] = event;
    }
    updated.sort((a, b) => a.start.compareTo(b.start));
    _events = updated;
    await _save();
    notifyListeners();
  }

  Future<void> deleteEvent(String id) async {
    _events = _events.where((item) => item.id != id).toList();
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    _preferences ??= await SharedPreferences.getInstance();
    await _preferences!.setString(
      _storageKey,
      jsonEncode({
        'profile': _profile.toJson(),
        'events': _events.map((event) => event.toJson()).toList(),
      }),
    );
  }
}

class PlanningProfile {
  const PlanningProfile({
    this.school = '',
    this.department = '',
    this.admissionYear,
    this.academicYearOverride,
    this.weekStartsOn = WeekStartDay.sunday,
  });

  final String school;
  final String department;
  final int? admissionYear;
  final int? academicYearOverride;
  final WeekStartDay weekStartsOn;

  bool get isConfigured =>
      school.trim().isNotEmpty &&
      department.trim().isNotEmpty &&
      admissionYear != null;

  int? academicYearFor(DateTime date) {
    if (academicYearOverride != null) return academicYearOverride;
    if (admissionYear == null) return null;
    final academicYearStart = date.month < 3 ? date.year - 1 : date.year;
    return (academicYearStart - admissionYear! + 1).clamp(1, 4);
  }

  Map<String, dynamic> toJson() => {
    'school': school,
    'department': department,
    'admissionYear': admissionYear,
    'academicYearOverride': academicYearOverride,
    'weekStartsOn': weekStartsOn.storageValue,
  };

  factory PlanningProfile.fromJson(Map<String, dynamic> json) =>
      PlanningProfile(
        school: json['school'] as String? ?? '',
        department: json['department'] as String? ?? '',
        admissionYear: json['admissionYear'] as int?,
        academicYearOverride: json['academicYearOverride'] as int?,
        weekStartsOn: weekStartDayFromStorage(json['weekStartsOn']),
      );
}

enum WeekStartDay {
  sunday,
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
}

extension WeekStartDayText on WeekStartDay {
  int get weekday => switch (this) {
    WeekStartDay.sunday => DateTime.sunday,
    WeekStartDay.monday => DateTime.monday,
    WeekStartDay.tuesday => DateTime.tuesday,
    WeekStartDay.wednesday => DateTime.wednesday,
    WeekStartDay.thursday => DateTime.thursday,
    WeekStartDay.friday => DateTime.friday,
    WeekStartDay.saturday => DateTime.saturday,
  };

  String get label => switch (this) {
    WeekStartDay.sunday => '일요일',
    WeekStartDay.monday => '월요일',
    WeekStartDay.tuesday => '화요일',
    WeekStartDay.wednesday => '수요일',
    WeekStartDay.thursday => '목요일',
    WeekStartDay.friday => '금요일',
    WeekStartDay.saturday => '토요일',
  };

  String get storageValue => name;

}

WeekStartDay weekStartDayFromStorage(Object? value) =>
    WeekStartDay.values.firstWhere(
      (item) => item.storageValue == value,
      orElse: () => WeekStartDay.sunday,
    );

enum PlanningEventCategory { academic, personal, activity, deadline }

extension PlanningEventCategoryText on PlanningEventCategory {
  String get label => switch (this) {
    PlanningEventCategory.academic => '학업',
    PlanningEventCategory.personal => '개인',
    PlanningEventCategory.activity => '활동',
    PlanningEventCategory.deadline => '마감',
  };

  String get storageValue => name;

  static PlanningEventCategory fromStorage(Object? value) =>
      PlanningEventCategory.values.firstWhere(
        (item) => item.storageValue == value,
        orElse: () => PlanningEventCategory.personal,
      );
}

class PlanningEvent {
  const PlanningEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.category,
    this.memo = '',
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final PlanningEventCategory category;
  final String memo;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'category': category.storageValue,
    'memo': memo,
  };

  factory PlanningEvent.fromJson(Map<String, dynamic> json) => PlanningEvent(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    start: DateTime.tryParse(json['start'] as String? ?? '') ?? DateTime.now(),
    end: DateTime.tryParse(json['end'] as String? ?? '') ?? DateTime.now(),
    category: PlanningEventCategoryText.fromStorage(json['category']),
    memo: json['memo'] as String? ?? '',
  );
}
