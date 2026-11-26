import '../api/job_analysis_models.dart';
import '../career/saved_analyses.dart';
import '../records/portfolio/job_recommendation_result.dart';
import 'writing_api.dart';

/// Opens 자기소개서·포트폴리오 for an analysed posting.
typedef WriteForPosting = void Function(PostingLink link, WritingType type);

/// One requirement of a linked posting as 채용공고 분석 compared it with the student's records.
class PostingRequirementLink {
  const PostingRequirementLink({
    required this.requirement,
    required this.priority,
    required this.status,
    this.records = const [],
  });

  factory PostingRequirementLink.fromJson(Map<String, dynamic> json) =>
      PostingRequirementLink(
        requirement: json['requirement'] as String,
        priority: json['priority'] as String,
        status: json['status'] as String,
        records: [
          for (final r in json['records'] as List? ?? const [])
            (
              kind: (r as Map)['kind'] as String,
              recordId: r['record_id'] as String,
            ),
        ],
      );

  final String requirement;

  /// `required` or `preferred`.
  final String priority;

  /// `supported`, `partially_supported` or `insufficient_evidence`.
  final String status;
  final List<({String kind, String recordId})> records;

  bool get required => priority == 'required';

  Map<String, Object?> toJson() => {
    'requirement': requirement,
    'priority': priority,
    'status': status,
    'records': [
      for (final r in records) {'kind': r.kind, 'record_id': r.recordId},
    ],
  };
}

const _statuses = {'supported', 'partially_supported', 'insufficient_evidence'};
const maxPostingRequirements = 20, _maxRequirementRecords = 10;

/// The posting a 자기소개서·포트폴리오 is written for: what was collected or pasted in
/// 채용공고 분석, and how its requirements compared with the student's records there.
class PostingLink {
  const PostingLink({
    required this.source,
    this.sourceId = '',
    required this.title,
    this.company = '',
    this.url = '',
    this.text = '',
    this.analyzedAt,
    this.requirements = const [],
  });

  /// A posting from 공고 찾기.
  factory PostingLink.fromRanked(RankedPosting entry, {DateTime? analyzedAt}) {
    final posting = entry.posting;
    return PostingLink(
      source: posting.source,
      sourceId: posting.id,
      title: posting.title,
      company: posting.company,
      url: posting.url,
      // Only a collected body is a posting text; a metadata summary is not.
      text: posting.textScope == 'metadata_only' ? '' : posting.text,
      analyzedAt: analyzedAt,
      requirements: _requirements([
        for (final c in entry.comparisons)
          (
            c.requirement,
            c.priority,
            c.status,
            [for (final e in c.evidence) (kind: e.kind, recordId: e.id)],
          ),
      ]),
    );
  }

  /// A posting pasted into 공고 1개 비교.
  factory PostingLink.fromJobAnalysis(
    String text,
    JobAnalysisResponse result, {
    DateTime? analyzedAt,
  }) => PostingLink(
    source: 'manual',
    title: analysisTitle(text, fallback: '붙여 넣은 공고'),
    text: text,
    analyzedAt: analyzedAt,
    requirements: _requirements([
      for (final c in result.comparisons)
        (
          c.requirement,
          c.priority,
          c.status,
          [
            for (final e in c.personalEvidence)
              (kind: e.kind, recordId: e.recordId),
          ],
        ),
    ]),
  );

  /// The link a saved document was written with, or null.
  static PostingLink? fromSaved(
    Map<String, Object?>? source,
    String text,
    List<Map<String, Object?>> requirements,
  ) {
    if (source == null) return null;
    return PostingLink(
      source: source['source'] as String? ?? 'manual',
      sourceId: source['source_id'] as String? ?? '',
      title: source['title'] as String? ?? '공고',
      company: source['company'] as String? ?? '',
      url: source['url'] as String? ?? '',
      text: text,
      analyzedAt: DateTime.tryParse(source['analyzed_at'] as String? ?? ''),
      requirements: [
        for (final r in requirements)
          PostingRequirementLink.fromJson(Map<String, dynamic>.from(r)),
      ],
    );
  }

  static List<PostingRequirementLink> _requirements(
    List<(String, String, String, List<({String kind, String recordId})>)> rows,
  ) {
    final all = [
      for (final (requirement, priority, status, records) in rows)
        if (requirement.trim().isNotEmpty)
          PostingRequirementLink(
            requirement: requirement.trim().length > 120
                ? requirement.trim().substring(0, 120)
                : requirement.trim(),
            priority: priority == 'required' ? 'required' : 'preferred',
            status: _statuses.contains(status)
                ? status
                : 'insufficient_evidence',
            records: {for (final r in records) '${r.kind}/${r.recordId}': r}
                .values
                .take(_maxRequirementRecords)
                .toList(),
          ),
    ];
    // 필수 first, keeping the analysis order inside each group.
    return [
      ...all.where((r) => r.required),
      ...all.where((r) => !r.required),
    ].take(maxPostingRequirements).toList();
  }

  final String source, sourceId, title, company, url, text;
  final DateTime? analyzedAt;
  final List<PostingRequirementLink> requirements;

  bool get hasText => text.trim().isNotEmpty;
  int get ready => requirements.where((r) => r.status == 'supported').length;

  String get sourceLabel => switch (source) {
    'work24' => '고용24',
    'saramin' => '사람인',
    'jobkorea' => '잡코리아',
    'greenhouse' => 'Greenhouse',
    _ => '붙여 넣은 공고',
  };

  /// `posting` of a writing request: shown with the saved document, not sent to the model.
  Map<String, Object?> toSource() => {
    'source': source,
    'source_id': sourceId,
    'title': title.length > 120 ? title.substring(0, 120) : title,
    'company': company.length > 120 ? company.substring(0, 120) : company,
    'url': url,
    'analyzed_at': analyzedAt?.toUtc().toIso8601String() ?? '',
  };

  List<Map<String, Object?>> requirementsJson() => [
    for (final r in requirements) r.toJson(),
  ];
}
