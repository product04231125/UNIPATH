import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/academic_guidance_models.dart';
import '../api/student_api.dart';
import '../assistant/ai_record_catalog.dart';
import '../auth/auth_api.dart';
import '../auth/file_export_gateway.dart';

List<T> _rows<T>(Object? value, T Function(Map<String, dynamic>) parse) => [
  for (final v in (value ?? const []) as List)
    parse(Map<String, dynamic>.from(v as Map)),
];

enum WritingType {
  coverLetter('cover_letter', '자기소개서'),
  portfolio('portfolio', '포트폴리오');

  const WritingType(this.value, this.label);
  final String value, label;
  static WritingType parse(String? value) =>
      values.firstWhere((t) => t.value == value, orElse: () => coverLetter);
}

/// What the student asked for; kept with the draft so the form can be restored.
class WritingInput {
  const WritingInput({
    required this.type,
    required this.targetRole,
    this.improve = false,
    this.targetCompany = '',
    this.postingText = '',
    this.questions = const [],
    this.charLimit,
    this.originalText = '',
    this.composition = const [],
    this.posting,
    this.postingRequirements = const [],
  });

  WritingInput.fromJson(Map<String, dynamic> json)
    : type = WritingType.parse(json['document_type'] as String?),
      improve = json['mode'] == 'improve',
      targetRole = json['target_role'] as String? ?? '',
      targetCompany = json['target_company'] as String? ?? '',
      postingText = json['posting_text'] as String? ?? '',
      questions = List<String>.from(json['questions'] as List? ?? const []),
      charLimit = json['char_limit'] as int?,
      originalText = json['original_text'] as String? ?? '',
      composition = [
        for (final g in json['composition'] as List? ?? const [])
          Map<String, Object?>.from(g as Map),
      ],
      posting = json['posting'] == null
          ? null
          : Map<String, Object?>.from(json['posting'] as Map),
      postingRequirements = [
        for (final r in json['posting_requirements'] as List? ?? const [])
          Map<String, Object?>.from(r as Map),
      ];

  final WritingType type;
  final bool improve;
  final String targetRole, targetCompany, postingText, originalText;
  final List<String> questions;
  final int? charLimit;

  /// 포트폴리오 구성: `{requirement, records: [{kind, record_id}]}` groups in order.
  final List<Map<String, Object?>> composition;

  /// The posting from 채용공고 분석 this is written for (`PostingLink.toSource`), and its
  /// requirements as that analysis compared them (`PostingLink.requirementsJson`).
  final Map<String, Object?>? posting;
  final List<Map<String, Object?>> postingRequirements;

  Map<String, Object?> toJson() => {
    'document_type': type.value,
    'mode': improve ? 'improve' : 'create',
    'target_role': targetRole,
    'target_company': targetCompany,
    'posting_text': postingText,
    'questions': questions,
    'char_limit': charLimit,
    'original_text': improve ? originalText : '',
    if (type == WritingType.portfolio && composition.isNotEmpty)
      'composition': composition,
    'posting': ?posting,
    if (postingRequirements.isNotEmpty)
      'posting_requirements': postingRequirements,
  };
}

class WritingCitation {
  WritingCitation.fromJson(Map<String, dynamic> json)
    : kind = json['kind'] as String,
      recordId = json['record_id'] as String,
      version = json['version'] as int,
      excerpt = json['excerpt'] as String;
  final String kind, recordId, excerpt;
  final int version;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'record_id': recordId,
    'version': version,
    'excerpt': excerpt,
  };
}

/// One paragraph or one fact row (label: text). Citations are from generation only; an edited
/// text is the student's own and is not re-verified.
class WritingPart {
  const WritingPart({
    this.label,
    required this.text,
    this.citations = const [],
  });

  WritingPart.fromJson(Map<String, dynamic> json)
    : label = json['label'] as String?,
      text = json['text'] as String,
      citations = _rows(json['citations'], WritingCitation.fromJson);

  final String? label;
  final String text;
  final List<WritingCitation> citations;

  Map<String, Object?> toJson() => {
    'label': ?label,
    'text': text,
    'citations': [for (final c in citations) c.toJson()],
  };
}

class WritingSection {
  const WritingSection({
    required this.heading,
    this.paragraphs = const [],
    this.facts = const [],
  });

  WritingSection.fromJson(Map<String, dynamic> json)
    : heading = json['heading'] as String,
      paragraphs = _rows(json['paragraphs'], WritingPart.fromJson),
      facts = _rows(json['facts'], WritingPart.fromJson);

  final String heading;
  final List<WritingPart> paragraphs, facts;

  /// Characters including spaces, as application forms count them.
  int get length => paragraphs.fold(0, (n, p) => n + p.text.length);

  Map<String, Object?> toJson() => {
    'heading': heading,
    'paragraphs': [for (final p in paragraphs) p.toJson()],
    'facts': [for (final f in facts) f.toJson()],
  };
}

class WritingRevision {
  WritingRevision.fromJson(Map<String, dynamic> json)
    : originalExcerpt = json['original_excerpt'] as String,
      sectionIndex = json['section_index'] as int,
      reason = json['reason'] as String;
  final String originalExcerpt, reason;
  final int sectionIndex;

  Map<String, Object?> toJson() => {
    'original_excerpt': originalExcerpt,
    'section_index': sectionIndex,
    'reason': reason,
  };
}

class WritingDraft {
  const WritingDraft({
    required this.sections,
    this.questionsForUser = const [],
    this.revisions = const [],
  });

  WritingDraft.fromJson(Map<String, dynamic> json)
    : sections = _rows(json['sections'], WritingSection.fromJson),
      questionsForUser = List<String>.from(
        json['questions_for_user'] as List? ?? const [],
      ),
      revisions = _rows(json['revisions'], WritingRevision.fromJson);

  final List<WritingSection> sections;
  final List<String> questionsForUser;
  final List<WritingRevision> revisions;

  /// Sections and text only: what is exported and what the student copies.
  Map<String, Object?> toExportJson() => {
    'sections': [
      for (final s in sections)
        if (s.paragraphs.isNotEmpty || s.facts.isNotEmpty) s.toJson(),
    ],
  };

  /// What is saved on the server: non-empty sections with their citations, the model's
  /// questions and revision notes that still point at a kept section.
  Map<String, Object?> toStoredJson() {
    final kept = <int, int>{};
    for (var i = 0; i < sections.length; i++) {
      final s = sections[i];
      if (s.paragraphs.isNotEmpty || s.facts.isNotEmpty) kept[i] = kept.length;
    }
    return {
      'sections': [for (final i in kept.keys) sections[i].toJson()],
      'questions_for_user': questionsForUser,
      'revisions': [
        for (final r in revisions)
          if (kept[r.sectionIndex] case final index?)
            {...r.toJson(), 'section_index': index},
      ],
    };
  }

  bool get isEmpty =>
      sections.every((s) => s.paragraphs.isEmpty && s.facts.isEmpty);

  String get plainText => [
    for (final s in sections)
      [
        s.heading,
        for (final f in s.facts) '${f.label}: ${f.text}',
        for (final p in s.paragraphs) p.text,
      ].join('\n'),
  ].join('\n\n');
}

class WritingSource {
  WritingSource.fromJson(Map<String, dynamic> json)
    : recordId = json['record_id'] as String,
      filename = json['filename'] as String,
      location = json['location'] as String,
      ocr = json['ocr'] == true;
  final String recordId, filename, location;
  final bool ocr;
}

class WritingResult {
  WritingResult.fromJson(this.raw)
    : status = raw['status'] as String,
      missingFields = List<String>.from(
        raw['missing_fields'] as List? ?? const [],
      ),
      failureReason = raw['failure_reason'] as String?,
      draft = raw['draft'] == null
          ? null
          : WritingDraft.fromJson(
              Map<String, dynamic>.from(raw['draft'] as Map),
            ),
      warnings = List<String>.from(raw['warnings'] as List? ?? const []),
      notice = raw['notice'] as String?,
      sources = _rows(raw['document_sources'], WritingSource.fromJson),
      originalRecordIds = List<String>.from(
        raw['original_record_ids'] as List? ?? const [],
      );

  final Map<String, dynamic> raw;
  final String status;
  final List<String> missingFields, warnings, originalRecordIds;
  final String? failureReason, notice;
  final WritingDraft? draft;
  final List<WritingSource> sources;

  String? get message => switch (status) {
    'draft_ready' => null,
    'not_configured' => '작성 모델이 아직 설정되지 않았습니다. 입력은 그대로 두었습니다.',
    'needs_user_input' when missingFields.contains('records') =>
      '초안에 쓸 기록이 없습니다. 수강·활동·경험·자격·성과 기록을 추가하거나 내 자료를 골라 주세요.',
    'needs_user_input' => 'Google 외부 전송 동의를 확인하고 다시 실행해 주세요.',
    _ when failureReason == 'personal_citation' =>
      '기록에서 근거를 확인한 문장이 없어 초안을 만들지 못했습니다. 기록을 더 구체적으로 적은 뒤 다시 시도해 주세요.',
    _
        when const {
          'model_timeout',
          'timeout',
          'model_busy',
        }.contains(failureReason) =>
      '작성 요청이 많거나 오래 걸렸습니다. 잠시 후 다시 시도해 주세요.',
    _ => '초안을 만들지 못했습니다. 입력은 그대로 두었습니다. 다시 시도해 주세요.',
  };
}

class WritingApi {
  const WritingApi(this.api);
  final StudentApi api;

  static List<Object?> _kept(
    Map<String, Object?> group,
    List<AiRecordOption> records,
  ) {
    final ids = {for (final r in records) '${r.kind}/${r.id}'};
    return [
      for (final r in (group['records'] as List? ?? const []).cast<Map>())
        if (ids.contains('${r['kind']}/${r['record_id']}')) r,
    ];
  }

  Future<WritingResult> generate(
    WritingInput input, {
    required List<AiRecordOption> records,
    List<GuidanceDocument> documents = const [],
  }) async => WritingResult.fromJson(
    (await api.api.request('POST', 'me/writing-drafts', {
      ...input.toJson(),
      // Only records that are sent may be arranged (a record deleted since composing drops out).
      if (input.toJson()['composition'] case final List groups)
        'composition': [
          for (final g in groups.cast<Map<String, Object?>>())
            if (_kept(g, records) case final kept when kept.isNotEmpty)
              {...g, 'records': kept},
        ],
      // A requirement stays even when its records are gone: it still says what is asked.
      if (input.toJson()['posting_requirements'] case final List asked)
        'posting_requirements': [
          for (final r in asked.cast<Map<String, Object?>>())
            {...r, 'records': _kept(r, records)},
        ],
      'records': [
        for (final r in records)
          {'kind': r.kind, 'record_id': r.id, 'expected_version': r.version},
      ],
      'documents': [
        for (final d in documents)
          {'filename': d.filename, 'content_base64': d.contentBase64},
      ],
      'external_processing_consent': true,
    }))!,
  );

  /// The student's edited draft as a Word file or PDF. No model call.
  Future<Uint8List> exportFile(
    WritingType type,
    WritingDraft draft,
    ExportFormat format, {
    required String name,
    String email = '',
    String phone = '',
    String link = '',
  }) async {
    if (api.api case final FileExportGateway gateway) {
      return gateway.exportFile('me/writing-exports', {
        'document_type': type.value,
        'format': format.extension,
        'draft': draft.toExportJson(),
        'profile': {'name': name, 'email': email, 'phone': phone, 'link': link},
        'reviewed': true,
      }, format);
    }
    throw AuthFailure('${format.label} 파일은 로그인한 뒤 받을 수 있습니다.');
  }
}

class WritingDocumentSummary {
  WritingDocumentSummary.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      title = json['title'] as String,
      type = WritingType.parse(json['document_type'] as String?),
      version = json['version'] as int,
      updatedAt = DateTime.tryParse(json['updated_at'] as String? ?? ''),
      posting = json['posting'] == null
          ? null
          : Map<String, Object?>.from(json['posting'] as Map);
  final String id, title;
  final WritingType type;
  final int version;
  final DateTime? updatedAt;

  /// The posting it was written for (`source`, `title`, `company`, `url`, …), if any.
  final Map<String, Object?>? posting;

  /// `합성 회사 · 프론트엔드 신입` for the list, or null.
  String? get postingLabel => switch (posting) {
    final p? => [
      if ((p['company'] as String? ?? '').isNotEmpty) p['company'],
      p['title'],
    ].join(' · '),
    null => null,
  };
}

/// A draft saved on the server: the form, the edited sections and the citation labels.
class WritingDocument extends WritingDocumentSummary {
  WritingDocument.fromJson(super.json)
    : input = WritingInput.fromJson(
        Map<String, dynamic>.from(json['input'] as Map),
      ),
      draft = WritingDraft.fromJson(
        Map<String, dynamic>.from(json['draft'] as Map),
      ),
      labels = Map<String, String>.from(json['labels'] as Map? ?? const {}),
      super.fromJson();
  final WritingInput input;
  final WritingDraft draft;
  final Map<String, String> labels;
}

class WritingDocumentApi {
  const WritingDocumentApi(this.api);
  final ApiGateway api;
  static const _path = 'me/writing-documents';

  Future<List<WritingDocumentSummary>> list() async => _rows(
    (await api.request('GET', _path))!['items'],
    WritingDocumentSummary.fromJson,
  );

  Future<WritingDocument> get(String id) async =>
      WritingDocument.fromJson((await api.request('GET', '$_path/$id'))!);

  Map<String, Object?> _body(
    String title,
    WritingInput input,
    WritingDraft draft,
    Map<String, String> labels,
  ) => {
    'title': title,
    'input': input.toJson(),
    'draft': draft.toStoredJson(),
    'labels': labels,
  };

  Future<WritingDocument> create(
    String title,
    WritingInput input,
    WritingDraft draft,
    Map<String, String> labels,
  ) async => WritingDocument.fromJson(
    (await api.request('POST', _path, _body(title, input, draft, labels)))!,
  );

  Future<WritingDocument> update(
    String id, {
    required int expectedVersion,
    required String title,
    required WritingInput input,
    required WritingDraft draft,
    required Map<String, String> labels,
  }) async => WritingDocument.fromJson(
    (await api.request('PUT', '$_path/$id', {
      ..._body(title, input, draft, labels),
      'expected_version': expectedVersion,
    }))!,
  );

  Future<void> delete(String id, {required int expectedVersion}) =>
      api.request('DELETE', '$_path/$id?expected_version=$expectedVersion');
}

/// The draft being edited on this device, with the saved document it came from (if any).
class WritingSession {
  const WritingSession({
    required this.input,
    required this.result,
    required this.draft,
    required this.labels,
    this.title = '',
    this.documentId,
    this.documentVersion,
    this.savedSnapshot,
  });
  final WritingInput input;
  final WritingResult result;
  final WritingDraft draft;
  final Map<String, String> labels;
  final String title;
  final String? documentId;
  final int? documentVersion;

  /// The title and sections as last saved on the server, to tell unsaved edits apart.
  final String? savedSnapshot;
}

/// The latest draft and its edits, kept only on this device until the student starts another.
class WritingSessionStore {
  WritingSessionStore({required this.ownerId, this.reader, this.writer});
  final String ownerId;
  final Future<String?> Function(String key)? reader;
  final Future<bool> Function(String key, String value)? writer;
  String get key => 'university_path.writing.$ownerId.v1';

  Future<WritingSession?> load() async {
    try {
      final value =
          await (reader?.call(key) ??
              SharedPreferences.getInstance().then((p) => p.getString(key)));
      if (value == null) return null;
      final json = Map<String, dynamic>.from(jsonDecode(value) as Map);
      return WritingSession(
        input: WritingInput.fromJson(
          Map<String, dynamic>.from(json['input'] as Map),
        ),
        result: WritingResult.fromJson(
          Map<String, dynamic>.from(json['result'] as Map),
        ),
        draft: WritingDraft.fromJson(
          Map<String, dynamic>.from(json['draft'] as Map),
        ),
        labels: Map<String, String>.from(json['labels'] as Map? ?? const {}),
        title: json['title'] as String? ?? '',
        documentId: json['document_id'] as String?,
        documentVersion: json['document_version'] as int?,
        savedSnapshot: json['saved_snapshot'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(WritingSession session) async {
    final value = jsonEncode({
      'input': session.input.toJson(),
      'result': session.result.raw,
      'draft': session.draft.toStoredJson(),
      // Record titles for the 근거 list; the records themselves stay on the server.
      'labels': session.labels,
      'title': session.title,
      'document_id': session.documentId,
      'document_version': session.documentVersion,
      'saved_snapshot': session.savedSnapshot,
    });
    try {
      await (writer?.call(key, value) ??
          SharedPreferences.getInstance().then((p) => p.setString(key, value)));
    } catch (_) {
      // Losing the local copy only means the draft is not restored next time.
    }
  }
}

String writingFailureMessage(Object error) => switch (error) {
  AuthFailure(status: 409) => '저장 기록이 바뀌었습니다. 다시 실행하면 최신 기록으로 작성합니다.',
  AuthFailure(status: 429) => '요청이 많습니다. 잠시 후 다시 시도하세요.',
  AuthFailure(:final message) => message,
  StateError(:final message) => message,
  _ => '응답을 확인하지 못했습니다. 입력은 그대로 두었습니다. 다시 시도하세요.',
};

/// Saving or deleting a document someone changed elsewhere (another tab or device).
String documentFailureMessage(Object error) => switch (error) {
  AuthFailure(status: 409) => '다른 곳에서 바뀐 문서입니다. 목록에서 다시 열어 주세요.',
  AuthFailure(status: 404) => '이미 지워진 문서입니다. 다시 저장하면 새 문서로 저장합니다.',
  _ => writingFailureMessage(error),
};
