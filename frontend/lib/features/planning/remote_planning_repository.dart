import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/personal_import_api.dart';
import '../api/personal_import_models.dart';
import '../api/student_api.dart';
import '../api/student_api_models.dart';
import '../auth/auth_api.dart';
import '../auth/local_data_owner.dart';
import 'planning_repository.dart';

/// Authenticated planning. Device originals are read only for explicit import;
/// API failures never fall back to silently writing a different store.
class RemotePlanningRepository extends PlanningRepository {
  RemotePlanningRepository(this.api);
  final StudentApi api;
  bool _loading = true, _failed = false, _ready = false, _closed = false;
  PlanningProfile _profile = const PlanningProfile();
  List<PlanningEvent> _events = [];
  PlanningProfile? _localProfile;
  List<PlanningEvent> _localEvents = [];
  Map<String, dynamic>? _journal;
  SharedPreferences? _preferences;
  bool _localReadFailed = false;
  final _records = <String, StudentRecord<StudentEventCreate>>{};
  final _creates = <String, StudentEventCreate>{};
  Future<void> _pending = Future.value();

  @override
  bool get isServerBacked => true;
  @override
  bool get isLoading => _loading;
  @override
  bool get loadFailed => _failed;
  @override
  PlanningProfile get profile => _profile;
  @override
  List<PlanningEvent> get events => List.unmodifiable(_events);
  String get _journalKey =>
      LocalDataOwner(api.ownerId).key('university_path.planning_import.v1');
  bool get _hasLocalProfile =>
      _localProfile != null &&
      jsonEncode(_localProfile!.toJson()) !=
          jsonEncode(const PlanningProfile().toJson());
  @override
  bool get canImportLocalPlanning =>
      !_localReadFailed &&
      _journal?['completed'] != true &&
      (_journal != null ||
          _localEvents.isNotEmpty ||
          (_hasLocalProfile && _profile.version == 0));
  @override
  List<String> get localPlanningPreview => [
    if (_hasLocalProfile)
      '기기 학업 정보: ${_localProfile!.school} · ${_localProfile!.department} · '
          '${_localProfile!.admissionYear ?? '입학연도 미입력'} '
          '(${_profile.version == 0 ? '서버 초기화 대상' : '서버 기존 정보 유지'})',
    for (final event in _localEvents.take(100))
      '${event.title}: ${event.start.toLocal()} ~ ${event.end.toLocal()}',
  ];
  @override
  String? get localPlanningNotice {
    if (_localReadFailed) return '기기 자료를 확인하지 못했습니다. 서버 자료만 표시합니다. 다시 불러와 주세요.';
    if (_journal?['completed'] == true) {
      return '이 기기의 학업 정보·일정 이전이 완료되었습니다. 기기 원본은 보관합니다.';
    }
    if (_journal != null) return '이전 결과 확인이 필요합니다. 같은 요청으로 안전하게 다시 확인할 수 있습니다.';
    if (_hasLocalProfile || _localEvents.isNotEmpty) {
      return '이 기기에 기존 학업 정보·일정 ${_localEvents.length}개가 별도로 있습니다. '
          '동의 전에는 전송하지 않습니다. 서버에 저장된 학업 정보는 덮어쓰지 않습니다.';
    }
    return null;
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    if (_closed) {
      return Future.error(StateError('Planning repository is closed'));
    }
    final result = _pending.then((_) {
      if (_closed) throw StateError('Planning repository is closed');
      return operation();
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _requireReady() {
    if (!_ready || _failed) {
      throw StateError('Read server planning before writing');
    }
  }

  @override
  Future<void> load() => _enqueue(_load);
  Future<void> _load() async {
    _loading = true;
    _failed = false;
    _ready = false;
    _notify();
    try {
      final profile = await api.profile();
      final records = <String, StudentRecord<StudentEventCreate>>{};
      final seen = <String>{};
      String? cursor;
      do {
        final page = await api.list(StudentResources.events, cursor: cursor);
        for (final item in page.items) {
          if (records.containsKey(item.id)) {
            throw const FormatException('Repeated event');
          }
          records[item.id] = item;
        }
        cursor = page.nextCursor;
        if (cursor != null && !seen.add(cursor)) {
          throw const FormatException('Repeated cursor');
        }
      } while (cursor != null);
      _profile = _toProfile(profile);
      _records
        ..clear()
        ..addAll(records);
      _refreshEvents();
      await _readLocal();
      _ready = true;
    } catch (_) {
      _failed = true;
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<void> _readLocal() async {
    final local = PlanningRepository(owner: LocalDataOwner(api.ownerId));
    try {
      _preferences ??= await SharedPreferences.getInstance();
      await local.load();
      if (local.loadFailed) {
        throw const FormatException('Unreadable local planning');
      }
      _localProfile = local.profile;
      _localEvents = local.events;
      final raw = _preferences!.getString(_journalKey);
      _journal = raw == null
          ? null
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
      _localReadFailed = false;
    } catch (_) {
      _localReadFailed = true;
    } finally {
      local.dispose();
    }
  }

  PlanningProfile _toProfile(StudentProfileView value) => PlanningProfile(
    school: value.school,
    department: value.department,
    admissionYear: value.admissionYear,
    track: value.track,
    academicYearOverride: value.academicYearOverride,
    weekStartsOn: weekStartDayFromStorage(value.weekStartsOn),
    version: value.version,
  );
  Map<String, Object?> _profileData(PlanningProfile value) => {
    'school': value.school,
    'department': value.department,
    'admission_year': value.admissionYear,
    'track': value.track,
    'academic_year_override': value.academicYearOverride,
    'week_starts_on': value.weekStartsOn.storageValue,
  };
  void _refreshEvents() {
    _events =
        _records.values
            .map(
              (item) => PlanningEvent(
                id: item.id,
                title: item.data.title,
                memo: item.data.detail,
                start: item.data.startsAt.toLocal(),
                end: item.data.endsAt.toLocal(),
                category: PlanningEventCategoryText.fromStorage(
                  item.data.category,
                ),
                version: item.version,
              ),
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
  }

  @override
  Future<void> saveProfile(PlanningProfile profile) =>
      _enqueue(() => _saveProfile(profile));
  Future<void> _saveProfile(PlanningProfile value) async {
    _requireReady();
    if (value.version == null) {
      throw StateError('Capture profile version before editing');
    }
    final saved = await api.patchProfile(
      expectedVersion: value.version!,
      changes: _profileData(value),
    );
    _profile = _toProfile(saved);
    _notify();
  }

  @override
  Future<void> saveSchoolContext({
    String? school,
    String? department,
    int? admissionYear,
    String? track,
  }) => _enqueue(
    () => _saveProfile(
      PlanningProfile(
        school: school ?? '',
        department: department ?? '',
        admissionYear: admissionYear,
        track: track,
        academicYearOverride: _profile.academicYearOverride,
        weekStartsOn: _profile.weekStartsOn,
        version: _profile.version,
      ),
    ),
  );

  @override
  Future<void> saveEvent(PlanningEvent event) => _enqueue(() async {
    _requireReady();
    final previous = _records[event.id];
    final payload = StudentEventCreate(
      title: event.title,
      detail: event.memo,
      startsAt: event.start.toUtc(),
      endsAt: event.end.toUtc(),
      timeZone: previous?.data.timeZone ?? 'UTC',
      category: event.category.storageValue,
    );
    final StudentRecord<StudentEventCreate> saved;
    if (event.version != null) {
      if (previous == null) {
        throw const AuthFailure('일정이 변경되었습니다. 다시 불러와 주세요.', status: 409);
      }
      saved = await api.patch(
        StudentResources.events,
        event.id,
        expectedVersion: event.version!,
        changes: payload.toJson()..remove('client_id'),
      );
    } else {
      final pending = _creates.putIfAbsent(
        event.id,
        () => StudentEventCreate.fromJson({
          ...payload.toJson(),
          'client_id': planningClientId(),
        }),
      );
      // Reuse exactly the same body after an uncertain response. An edited retry
      // must not accidentally create a second record or overwrite the first.
      final pendingBody = pending.toJson()..remove('client_id');
      if (jsonEncode(pendingBody) !=
          jsonEncode(payload.toJson()..remove('client_id'))) {
        throw const AuthFailure(
          '이전 저장 결과를 먼저 확인해 주세요. 자료를 다시 불러온 뒤 수정할 수 있습니다.',
          status: 409,
        );
      }
      saved = await api.create(StudentResources.events, pending);
    }
    _records[saved.id] = saved;
    _refreshEvents();
    _notify();
  });

  @override
  Future<void> deleteEvent(String id, {int? expectedVersion}) =>
      _enqueue(() async {
        _requireReady();
        if (expectedVersion == null) {
          throw StateError('Capture event version before deleting');
        }
        await api.remove(
          StudentResources.events,
          id,
          expectedVersion: expectedVersion,
        );
        _records.remove(id);
        _refreshEvents();
        _notify();
      });

  @override
  Future<void> importLocalPlanning({required bool confirmed}) => _enqueue(
    () async {
      _requireReady();
      if (!confirmed || !canImportLocalPlanning) {
        throw StateError('Confirm planning import first');
      }
      if (_journal == null) {
        if (_localEvents.length > 100) {
          throw const AuthFailure('일정은 한 번에 100개까지 이전할 수 있습니다. 기기 원본은 유지됩니다.');
        }
        final request = PersonalImportRequest.fromJson({
          'import_id': planningClientId(),
          'source_owner_id': api.ownerId,
          'consent_confirmed': true,
          if (_hasLocalProfile && _profile.version == 0)
            'profile': _profileData(_localProfile!),
          'events': _localEvents
              .map(
                (event) => {
                  'client_id': planningClientId(),
                  'title': event.title,
                  'detail': event.memo,
                  'starts_at': event.start.toUtc().toIso8601String(),
                  'ends_at': event.end.toUtc().toIso8601String(),
                  'time_zone': 'UTC',
                  'category': event.category.storageValue,
                },
              )
              .toList(),
        });
        final journal = {'request': request.toJson(), 'completed': false};
        if (!await _preferences!.setString(_journalKey, jsonEncode(journal))) {
          throw StateError('Could not preserve import retry information');
        }
        _journal = journal;
      }
      final request = PersonalImportRequest.fromJson(
        Map<String, dynamic>.from(_journal!['request'] as Map),
      );
      await PersonalImportApi(api.api, ownerId: api.ownerId).create(request);
      // Persist completion before re-reading. A failed read is not a failed import.
      final journal = {..._journal!, 'completed': true};
      if (!await _preferences!.setString(_journalKey, jsonEncode(journal))) {
        throw const AuthFailure('서버 이전은 완료됐습니다. 같은 요청으로 결과를 다시 확인해 주세요.');
      }
      _journal = journal;
      await _load();
    },
  );

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}

/// Local operation identity, separate from the server record UUID.
String planningClientId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
