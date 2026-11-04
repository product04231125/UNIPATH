import 'package:flutter/foundation.dart';

/// Shared "현재 학교" selection owned by [AdminWorkspace], shown in the title bar.
class AdminSchoolChrome extends ChangeNotifier {
  String schoolId = '';
  List<({String id, String name})> schools = const [];
  bool visible = false;
  Future<void> Function(String id)? onChanged;

  String get schoolName {
    for (final school in schools) {
      if (school.id == schoolId) return school.name;
    }
    return '';
  }

  void publish({
    required String schoolId,
    required List<({String id, String name})> schools,
    required bool visible,
    required Future<void> Function(String id) onChanged,
  }) {
    final sameSchools =
        this.schools.length == schools.length &&
        [
          for (var i = 0; i < schools.length; i++)
            this.schools[i].id == schools[i].id &&
                this.schools[i].name == schools[i].name,
        ].every((ok) => ok);
    final changed =
        this.schoolId != schoolId || this.visible != visible || !sameSchools;
    this.schoolId = schoolId;
    this.schools = List.unmodifiable(schools);
    this.visible = visible;
    this.onChanged = onChanged;
    if (changed) notifyListeners();
  }

  void clear() {
    if (!visible && schools.isEmpty && schoolId.isEmpty) return;
    schoolId = '';
    schools = const [];
    visible = false;
    onChanged = null;
    notifyListeners();
  }
}
