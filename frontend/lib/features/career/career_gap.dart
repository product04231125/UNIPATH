import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/student_api.dart';
import '../auth/auth_api.dart';

List<T> _rows<T>(Object? value, T Function(Map<String, dynamic>) parse) =>
    List.unmodifiable(
      ((value ?? const []) as List).map(
        (v) => parse(Map<String, dynamic>.from(v as Map)),
      ),
    );

class GapPosting {
  GapPosting.fromJson(Map<String, dynamic> json)
    : number = json['posting'] as int,
      source = json['source'] as String,
      title = json['title'] as String,
      company = json['company'] as String,
      url = json['url'] as String,
      closingLabel = json['closing_label'] as String? ?? '확인 필요',
      expiresAt = DateTime.tryParse(json['expires_at'] as String? ?? '');
  final int number;
  final String source, title, company, url, closingLabel;
  final DateTime? expiresAt;
}

class GapPostingRef {
  GapPostingRef.fromJson(Map<String, dynamic> json)
    : posting = json['posting'] as int,
      excerpt = json['excerpt'] as String;
  final int posting;
  final String excerpt;
}

class GapEvidence {
  GapEvidence.fromJson(Map<String, dynamic> json)
    : kind = json['kind'] as String,
      recordId = json['record_id'] as String,
      version = json['version'] as int,
      excerpt = json['excerpt'] as String;
  final String kind, recordId, excerpt;
  final int version;
}

class GapAction {
  GapAction.fromJson(Map<String, dynamic> json)
    : type = json['type'] as String,
      title = json['title'] as String,
      detail = json['detail'] as String,
      weeks = json['weeks'] as int?;
  final String type, title, detail;
  final int? weeks;

  String get typeLabel => switch (type) {
    'certificate' => '자격증',
    'activity' => '활동',
    'project' => '프로젝트',
    'course' => '강의·교육',
    _ => '공부',
  };
}

class GapRequirement {
  GapRequirement.fromJson(Map<String, dynamic> json)
    : id = json['requirement_id'] as String,
      requirement = json['requirement'] as String,
      category = json['category'] as String? ?? 'other',
      frequency = json['frequency'] as int,
      postings = _rows(json['postings'], GapPostingRef.fromJson),
      status = json['status'] as String,
      evidence = _rows(json['personal_evidence'], GapEvidence.fromJson),
      explanation = json['explanation'] as String,
      actions = _rows(json['actions'], GapAction.fromJson);
  final String id, requirement, category, status, explanation;
  final int frequency;
  final List<GapPostingRef> postings;
  final List<GapEvidence> evidence;
  final List<GapAction> actions;

  /// Preparation wording, not an evidence verdict (team decision for job analysis, 2026-11-22).
  String get statusLabel => switch (status) {
    'supported' => '준비됨',
    'partially_supported' => '일부 준비됨',
    _ => '준비 필요',
  };
}

class GapReport {
  GapReport.fromJson(this.raw)
    : status = raw['status'] as String,
      missingFields = List<String>.from(
        raw['missing_fields'] as List? ?? const [],
      ),
      goalLabel = _goal(raw)['label'] as String?,
      goalCodes = List<String>.from(
        _goal(raw)['category_codes'] as List? ?? const [],
      ),
      goalKeyword = _goal(raw)['keyword'] as String? ?? '',
      postings = _rows(raw['postings'], GapPosting.fromJson),
      requirements = _rows(raw['requirements'], GapRequirement.fromJson),
      summary = raw['summary'] as String?,
      warnings = List<String>.from(raw['warnings'] as List? ?? const []),
      searchNotice = raw['search_notice'] as String?,
      categoryBrowseAvailable = raw['category_browse_available'] == true,
      failureReason = raw['failure_reason'] as String?,
      generatedAt = DateTime.tryParse(raw['generated_at'] as String? ?? '');

  static Map<String, dynamic> _goal(Map<String, dynamic> raw) =>
      Map<String, dynamic>.from(raw['goal'] as Map? ?? const {});

  final Map<String, dynamic> raw;
  final String status;
  final List<String> missingFields, goalCodes, warnings;
  final String goalKeyword;
  final String? goalLabel, summary, searchNotice, failureReason;
  final List<GapPosting> postings;
  final List<GapRequirement> requirements;
  final bool categoryBrowseAvailable;
  final DateTime? generatedAt;

  String get goalSummary => [
    if (goalLabel case final label? when label.isNotEmpty) label,
    if (goalKeyword.isNotEmpty) goalKeyword,
  ].join(' · ');

  int count(String status) =>
      requirements.where((r) => r.status == status).length;
}

class CareerGapApi {
  const CareerGapApi(this.api);
  final StudentApi api;

  /// Empty [categoryCodes] and [keyword]: the server uses the saved career goal.
  Future<GapReport> analyze({
    required List<Map<String, Object?>> records,
    List<String> categoryCodes = const [],
    String keyword = '',
  }) async => GapReport.fromJson(
    (await api.api.request('POST', 'me/career-gap-analyses', {
      'records': records,
      'category_codes': categoryCodes,
      'keyword': keyword,
      'external_processing_consent': true,
    }))!,
  );
}

/// The latest completed report, kept only on this device for the 홈 summary.
class GapReportStore {
  GapReportStore({required this.ownerId, this.reader, this.writer});
  final String ownerId;
  final Future<String?> Function(String key)? reader;
  final Future<bool> Function(String key, String value)? writer;
  String get key => 'university_path.career_gap.$ownerId.v1';

  Future<GapReport?> load() async {
    try {
      final value =
          await (reader?.call(key) ??
              SharedPreferences.getInstance().then((p) => p.getString(key)));
      if (value == null) return null;
      return GapReport.fromJson(
        Map<String, dynamic>.from(jsonDecode(value) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(GapReport report) async {
    final value = jsonEncode(report.raw);
    try {
      await (writer?.call(key, value) ??
          SharedPreferences.getInstance().then((p) => p.setString(key, value)));
    } catch (_) {
      // A missing cache only hides the 홈 summary; the analysis itself is unaffected.
    }
  }
}

String gapFailureMessage(Object error) => switch (error) {
  AuthFailure(status: 409) => '저장 기록이 바뀌었습니다. 다시 실행하면 최신 기록으로 분석합니다.',
  AuthFailure(status: 429) => '요청이 많습니다. 잠시 후 다시 시도하세요.',
  AuthFailure(:final message) => message,
  _ => '분석 응답을 확인하지 못했습니다. 다시 시도하세요.',
};
