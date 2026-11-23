import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/academic_guidance_models.dart';
import '../api/student_api.dart';
import '../assistant/ai_record_catalog.dart';
import '../auth/auth_api.dart';
import '../auth/word_export_gateway.dart';

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
  });

  WritingInput.fromJson(Map<String, dynamic> json)
    : type = WritingType.parse(json['document_type'] as String?),
      improve = json['mode'] == 'improve',
      targetRole = json['target_role'] as String? ?? '',
      targetCompany = json['target_company'] as String? ?? '',
      postingText = json['posting_text'] as String? ?? '',
      questions = List<String>.from(json['questions'] as List? ?? const []),
      charLimit = json['char_limit'] as int?,
      originalText = json['original_text'] as String? ?? '';

  final WritingType type;
  final bool improve;
  final String targetRole, targetCompany, postingText, originalText;
  final List<String> questions;
  final int? charLimit;

  Map<String, Object?> toJson() => {
    'document_type': type.value,
    'mode': improve ? 'improve' : 'create',
    'target_role': targetRole,
    'target_company': targetCompany,
    'posting_text': postingText,
    'questions': questions,
    'char_limit': charLimit,
    'original_text': improve ? originalText : '',
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

  Future<WritingResult> generate(
    WritingInput input, {
    required List<AiRecordOption> records,
    List<GuidanceDocument> documents = const [],
  }) async => WritingResult.fromJson(
    (await api.api.request('POST', 'me/writing-drafts', {
      ...input.toJson(),
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

  /// The student's edited draft as a Word file. No model call.
  Future<Uint8List> exportWord(
    WritingType type,
    WritingDraft draft, {
    required String name,
    String email = '',
    String phone = '',
    String link = '',
  }) async {
    if (api.api case final WordExportGateway gateway) {
      return gateway.exportWord('me/writing-exports', {
        'document_type': type.value,
        'draft': draft.toExportJson(),
        'profile': {'name': name, 'email': email, 'phone': phone, 'link': link},
        'reviewed': true,
      });
    }
    throw const AuthFailure('Word 파일은 로그인한 뒤 받을 수 있습니다.');
  }
}

/// The latest draft and its edits, kept only on this device until the student starts another.
class WritingSessionStore {
  WritingSessionStore({required this.ownerId, this.reader, this.writer});
  final String ownerId;
  final Future<String?> Function(String key)? reader;
  final Future<bool> Function(String key, String value)? writer;
  String get key => 'university_path.writing.$ownerId.v1';

  Future<(WritingInput, WritingResult, WritingDraft, Map<String, String>)?>
  load() async {
    try {
      final value =
          await (reader?.call(key) ??
              SharedPreferences.getInstance().then((p) => p.getString(key)));
      if (value == null) return null;
      final json = Map<String, dynamic>.from(jsonDecode(value) as Map);
      return (
        WritingInput.fromJson(Map<String, dynamic>.from(json['input'] as Map)),
        WritingResult.fromJson(
          Map<String, dynamic>.from(json['result'] as Map),
        ),
        WritingDraft.fromJson(Map<String, dynamic>.from(json['draft'] as Map)),
        Map<String, String>.from(json['labels'] as Map? ?? const {}),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(
    WritingInput input,
    WritingResult result,
    WritingDraft draft,
    Map<String, String> labels,
  ) async {
    final value = jsonEncode({
      'input': input.toJson(),
      'result': result.raw,
      'draft': {
        ...draft.toExportJson(),
        'questions_for_user': draft.questionsForUser,
      },
      // Record titles for the 근거 list; the records themselves stay on the server.
      'labels': labels,
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
