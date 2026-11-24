import 'package:flutter/foundation.dart';

import '../api/job_analysis_models.dart';
import '../api/job_recommendation_api.dart';
import '../api/student_api.dart';
import '../assistant/ai_record_catalog.dart';

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map? ?? const {});

DateTime? _day(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// One catalog entry (Q-Net national qualification or another common certificate).
class CertificateSummary {
  CertificateSummary.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      kind = json['kind'] as String? ?? 'private',
      kindLabel = json['kind_label'] as String? ?? '자격',
      issuer = json['issuer'] as String? ?? '',
      grade = json['grade'] as String?,
      field = json['field'] as String? ?? '';
  final String id, name, kind, kindLabel, issuer, field;
  final String? grade;
}

enum ScheduleEventKind {
  registration('접수'),
  exam('시험'),
  result('발표'),
  document('서류');

  const ScheduleEventKind(this.label);
  final String label;

  static ScheduleEventKind parse(Object? value) => values.firstWhere(
    (k) => k.name == value,
    orElse: () => ScheduleEventKind.exam,
  );
}

class ScheduleEvent {
  ScheduleEvent.fromJson(Map<String, dynamic> json)
    : kind = ScheduleEventKind.parse(json['kind']),
      label = json['label'] as String? ?? '일정',
      start = _day(json['start'])!,
      end = _day(json['end']) ?? _day(json['start'])!;
  final ScheduleEventKind kind;
  final String label;
  final DateTime start, end;

  bool get isRange => end.isAfter(start);
  bool endedBefore(DateTime today) => end.isBefore(_dateOnly(today));
  String get key => '${kind.name}|$label|${start.toIso8601String()}';
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

class ScheduleRound {
  ScheduleRound.fromJson(Map<String, dynamic> json)
    : name = json['name'] as String? ?? '회차',
      events = [
        for (final e in json['events'] as List? ?? const [])
          ScheduleEvent.fromJson(_map(e)),
      ];
  final String name;
  final List<ScheduleEvent> events;
}

class CertificateSchedule {
  CertificateSchedule.fromJson(Map<String, dynamic> json)
    : status = json['status'] as String? ?? 'unavailable',
      rounds = [
        for (final r in json['rounds'] as List? ?? const [])
          ScheduleRound.fromJson(_map(r)),
      ],
      referenceRounds = [
        for (final r in json['reference_rounds'] as List? ?? const [])
          ScheduleRound.fromJson(_map(r)),
      ],
      nextRegistration = json['next_registration'] == null
          ? null
          : ScheduleEvent.fromJson(_map(json['next_registration'])),
      nextEvent = json['next_event'] == null
          ? null
          : ScheduleEvent.fromJson(_map(json['next_event'])),
      source = json['source'] as String?,
      sourceUrl = json['source_url'] as String?,
      checkedAt = json['checked_at'] as String?,
      failureReason = json['failure_reason'] as String?,
      note = json['note'] as String?;

  /// upcoming, unpublished (next exam year not out yet), always (상시 시험) or unavailable.
  final String status;
  final List<ScheduleRound> rounds, referenceRounds;
  final ScheduleEvent? nextRegistration, nextEvent;
  final String? source, sourceUrl, checkedAt, failureReason, note;
}

class CertificateDetail {
  CertificateDetail.fromJson(Map<String, dynamic> json)
    : summary = CertificateSummary.fromJson(json),
      officialUrl = json['official_url'] as String?,
      eligibilityNote = json['eligibility_note'] as String?,
      fee = json['fee'] as String?,
      method = json['method'] as String?,
      subjectsText = json['subjects_text'] as String?,
      eligibility = json['eligibility'] as String?,
      trend = json['trend'] as String?,
      subjects = List<String>.from(json['subjects'] as List? ?? const []),
      passCriteria = json['pass_criteria'] as String?,
      infoFailureReason = json['info_failure_reason'] as String?,
      schedule = CertificateSchedule.fromJson(_map(json['schedule']));
  final CertificateSummary summary;
  final String? officialUrl,
      eligibilityNote,
      fee,
      method,
      subjectsText,
      eligibility,
      trend,
      passCriteria,
      infoFailureReason;
  final List<String> subjects;
  final CertificateSchedule schedule;
}

class CertificateRecommendation {
  CertificateRecommendation.fromJson(Map<String, dynamic> json)
    : certificate = CertificateSummary.fromJson(_map(json['certificate'])),
      reason = json['reason'] as String,
      requirements = List<String>.from(json['requirements'] as List? ?? []),
      relatedRecords = List<String>.from(
        json['related_records'] as List? ?? [],
      ),
      timing = json['timing'] as String?,
      weeks = json['weeks'] as int?,
      evidence = [
        for (final e in json['evidence'] as List? ?? const [])
          (
            requirement: _map(e)['requirement'] as String,
            frequency: _map(e)['frequency'] as int?,
          ),
      ],
      schedule = CertificateSchedule.fromJson(_map(json['schedule']));
  final CertificateSummary certificate;
  final String reason;
  final List<String> requirements, relatedRecords;
  final String? timing;
  final int? weeks;
  final List<({String requirement, int? frequency})> evidence;
  final CertificateSchedule schedule;
}

class CertificateRecommendationResult {
  CertificateRecommendationResult.fromJson(Map<String, dynamic> raw)
    : status = raw['status'] as String,
      missingFields = List<String>.from(raw['missing_fields'] as List? ?? []),
      goalLabel = _map(raw['goal'])['label'] as String?,
      goalKeyword = _map(raw['goal'])['keyword'] as String? ?? '',
      gapCount = _map(raw['gap_basis'])['gaps'] as int? ?? 0,
      postingCount = _map(raw['gap_basis'])['postings'] as int? ?? 0,
      gapAnalyzedAt = DateTime.tryParse(
        _map(raw['gap_basis'])['analyzed_at'] as String? ?? '',
      ),
      recommendations = [
        for (final value in raw['recommendations'] as List? ?? const [])
          CertificateRecommendation.fromJson(_map(value)),
      ],
      held = List<String>.from(raw['held'] as List? ?? const []),
      summary = raw['summary'] as String?,
      failureReason = raw['failure_reason'] as String?;
  final String status;
  final List<String> missingFields, held;
  final String? goalLabel, summary, failureReason;
  final String goalKeyword;
  final int gapCount, postingCount;
  final DateTime? gapAnalyzedAt;
  final List<CertificateRecommendation> recommendations;

  String get goalSummary =>
      [?goalLabel, if (goalKeyword.isNotEmpty) goalKeyword].join(' · ');
}

class CertificateApi {
  const CertificateApi(this.api);
  final StudentApi api;

  Future<List<CertificateSummary>> search(String query) async {
    final value = await api.api.request(
      'GET',
      'me/certificates?query=${Uri.encodeQueryComponent(query)}',
    );
    return [
      for (final item in value?['items'] as List? ?? const [])
        CertificateSummary.fromJson(_map(item)),
    ];
  }

  Future<CertificateDetail> detail(String id) async =>
      CertificateDetail.fromJson(
        (await api.api.request(
          'GET',
          'me/certificates/${Uri.encodeComponent(id)}',
        ))!,
      );

  Future<CertificateRecommendationResult> recommend({
    required List<AiRecordOption> records,
    RecommendationAcademicStage? academicStage,
  }) async => CertificateRecommendationResult.fromJson(
    (await api.api.request('POST', 'me/certificate-recommendations', {
      'records': [
        for (final r in records)
          PersonalEvidenceSelection(
            kind: r.kind,
            recordId: r.id,
            expectedVersion: r.version,
          ).toJson(),
      ],
      if (academicStage != null) 'academic_stage': academicStage.name,
      'external_processing_consent': true,
    }))!,
  );
}

/// Which certificate the 시험 일정 tab shows; 자격증 추천 cards set it.
class CertificateSelection extends ChangeNotifier {
  CertificateSummary? _selected;
  CertificateSummary? get selected => _selected;
  void select(CertificateSummary value) {
    _selected = value;
    notifyListeners();
  }
}

/// `D-3`, `D-day`, or null once the date has passed.
String? dDay(DateTime date, DateTime today) {
  final days = _dateOnly(date).difference(_dateOnly(today)).inDays;
  if (days < 0) return null;
  return days == 0 ? 'D-day' : 'D-$days';
}

String shortDate(DateTime d) => '${d.month}월 ${d.day}일';

String eventPeriod(ScheduleEvent e) {
  final start = '${e.start.year}. ${e.start.month}. ${e.start.day}.';
  if (!e.isRange) return start;
  final end = e.end.year == e.start.year
      ? '${e.end.month}. ${e.end.day}.'
      : '${e.end.year}. ${e.end.month}. ${e.end.day}.';
  return '$start ~ $end';
}
