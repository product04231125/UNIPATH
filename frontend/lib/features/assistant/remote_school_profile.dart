import 'dart:async';

import '../../chat_window.dart' as native;
import '../planning/planning_repository.dart';

/// Child windows never write the combined profile/event storage themselves.
class RemoteSchoolProfile extends PlanningRepository {
  RemoteSchoolProfile() {
    _subscription = native.schoolProfileChanges().listen(_receive);
  }
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  PlanningProfile _remoteProfile = const PlanningProfile();
  bool _loading = true;
  bool _failed = false;
  bool _disposed = false;
  @override
  PlanningProfile get profile => _remoteProfile;
  @override
  bool get isLoading => _loading;
  @override
  bool get loadFailed => _failed;
  void _receive(Map<String, dynamic> value) {
    if (_disposed) return;
    _remoteProfile = PlanningProfile.fromJson(value);
    _loading = false;
    _failed = false;
    notifyListeners();
  }

  @override
  Future<void> load() async {
    try {
      _receive(await native.requestSchoolProfile());
    } catch (_) {
      if (_disposed) return;
      _loading = false;
      _failed = true;
      notifyListeners();
    }
  }

  @override
  Future<void> saveSchoolContext({
    String? school,
    String? department,
    int? admissionYear,
    String? track,
  }) async {
    _receive(
      await native.requestSchoolProfile({
        'school': school,
        'department': department,
        'admissionYear': admissionYear,
        'track': track,
      }),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription.cancel();
    super.dispose();
  }
}
