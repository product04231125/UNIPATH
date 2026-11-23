import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AiConsentFeature {
  schoolQuestion('학교 질문', '질문과 학교 문서의 관련 내용'),
  personalizedQuestion(
    '내 자료로 질문',
    '질문, 학교 문서의 관련 내용, 직접 선택한 개인 기록과 등록 자료 설명·PDF에서 추출한 텍스트(OCR 포함)',
  ),
  jobAnalysis(
    '채용 분석',
    '공고 본문, 저장된 수강·활동·경험·자격·성과 기록 전체와 직접 고른 내 자료의 설명·PDF에서 추출한 텍스트(OCR 포함)',
  ),
  jobRecommendation(
    '내 자료로 공고 찾기',
    '첨부 파일·직접 고른 내 자료에서 추출한 텍스트(OCR 포함)와 저장된 수강·활동·경험·자격·성과 기록 전체',
  );

  const AiConsentFeature(this.label, this.transferredData);
  final String label, transferredData;

  String? get _allRecordsConsentKey => switch (this) {
    // Bumped whenever the transferred data widens (내 자료, then 수강 기록): earlier consent
    // did not cover it.
    jobAnalysis => 'job_analysis_all_records_courses_materials',
    jobRecommendation => 'job_recommendation_all_records_courses',
    _ => null,
  };
}

/// One workspace/account owns this store. No credentials or records are stored.
class AiConsentPreferences extends ChangeNotifier {
  AiConsentPreferences({required this.ownerId, this.reader, this.writer});
  static const noticeVersion = 1;
  final String ownerId;
  final Future<String?> Function(String key)? reader;
  final Future<bool> Function(String key, String value)? writer;
  String get storageKey => 'university_path.ai_consent.$ownerId.v1';
  final Set<AiConsentFeature> _allowed = {};
  bool loading = true, saving = false, loadFailed = false;
  bool _disposed = false;
  String? error;
  Future<void>? _load;

  bool allows(AiConsentFeature feature) =>
      !_disposed && !loading && !loadFailed && _allowed.contains(feature);

  Future<void> load() => _load ??= _read();
  Future<void> _read() async {
    loading = true;
    loadFailed = false;
    error = null;
    _notify();
    try {
      final raw = reader != null
          ? await reader!(storageKey)
          : (await SharedPreferences.getInstance()).getString(storageKey);
      final next = <AiConsentFeature>{};
      if (raw != null) {
        final value = jsonDecode(raw) as Map;
        if (value['owner_id'] != ownerId) {
          throw const FormatException('Consent owner mismatch');
        }
        if (value['notice_version'] == noticeVersion) {
          final features = value['allowed'] as List;
          for (final name in features) {
            final feature = AiConsentFeature.values.byName(name as String);
            final scopeKey = feature._allRecordsConsentKey;
            if (scopeKey != null && value[scopeKey] != true) {
              continue;
            }
            next.add(feature);
          }
        }
      }
      if (_disposed) return;
      _allowed
        ..clear()
        ..addAll(next);
    } catch (_) {
      _allowed.clear();
      loadFailed = true;
      error = '외부 전송 설정을 읽지 못했습니다. 다시 읽기 전에는 전송하지 않습니다.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> retry() {
    if (loading || saving) return load();
    _load = null;
    return load();
  }

  Future<bool> setAllowed(AiConsentFeature feature, bool allowed) async {
    if (_disposed || loading || loadFailed || saving) return false;
    saving = true;
    error = null;
    final next = {..._allowed};
    if (allowed) {
      next.add(feature);
    } else {
      next.remove(feature);
      // Revocation fails closed in this session even when persistence fails.
      _allowed.remove(feature);
    }
    _notify();
    try {
      final value = jsonEncode({
        'owner_id': ownerId,
        'notice_version': noticeVersion,
        'allowed': next.map((f) => f.name).toList(),
        for (final feature in next) ?feature._allRecordsConsentKey: true,
      });
      final saved = writer != null
          ? await writer!(storageKey, value)
          : await (await SharedPreferences.getInstance()).setString(
              storageKey,
              value,
            );
      if (!saved) throw StateError('Consent write rejected');
      if (_disposed) return false;
      _allowed
        ..clear()
        ..addAll(next);
      return true;
    } catch (_) {
      error = allowed
          ? '허용 설정을 저장하지 못했습니다. 전송하지 않았습니다. 다시 시도해 주세요.'
          : '이 실행 중에는 전송을 차단했습니다. 기기 설정 저장에 실패했으므로 다시 해제해 주세요.';
      return false;
    } finally {
      saving = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _allowed.clear();
    super.dispose();
  }
}
