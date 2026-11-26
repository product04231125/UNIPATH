import 'package:flutter/foundation.dart';

import '../api/job_recommendation_api.dart';
import '../auth/auth_api.dart';

/// The job a student is preparing for: one Work24 occupation code plus optional detail words.
class CareerGoal {
  const CareerGoal({
    this.categoryCodes = const [],
    this.keyword = '',
    this.version = 0,
    this.categoryLabel,
  });

  CareerGoal.fromJson(Map<String, dynamic> json)
    : categoryCodes = List<String>.unmodifiable(
        (json['category_codes'] as List? ?? const []).cast<String>(),
      ),
      keyword = json['keyword'] as String? ?? '',
      version = json['version'] as int,
      categoryLabel = json['category_label'] as String?;

  final List<String> categoryCodes;
  final String keyword;
  final int version;
  final String? categoryLabel;

  bool get isSet => categoryCodes.isNotEmpty || keyword.isNotEmpty;

  /// The first code (the app picks one), and its 1차 parent when it is a 2차 code.
  String get code => categoryCodes.isEmpty ? '' : categoryCodes.first;
  String get topCode => code.length > 2 ? code.substring(0, 2) : code;
  String get subCode => code.length > 2 ? code : '';

  String get summary => [
    if (categoryLabel case final label? when label.isNotEmpty) label,
    if (keyword.isNotEmpty) keyword,
  ].join(' · ');
}

class CareerGoalApi {
  const CareerGoalApi(this.api);
  final ApiGateway api;

  Future<CareerGoal> load() async =>
      CareerGoal.fromJson((await api.request('GET', 'me/career-goal'))!);

  Future<CareerGoal> save({
    required List<String> categoryCodes,
    required String keyword,
    required int expectedVersion,
  }) async => CareerGoal.fromJson(
    (await api.request('PUT', 'me/career-goal', {
      'category_codes': categoryCodes,
      'keyword': keyword,
      'expected_version': expectedVersion,
    }))!,
  );
}

/// Shared by 홈 and 채용공고 분석 so a saved goal shows everywhere at once.
class CareerGoalController extends ChangeNotifier {
  CareerGoalController(this.api);
  final ApiGateway api;

  CareerGoal _goal = const CareerGoal();
  bool _loading = false, _loaded = false;
  String? _error;
  Future<List<JobCategory>>? _categories;

  CareerGoal get goal => _goal;
  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;

  Future<List<JobCategory>> get categories =>
      _categories ??= JobRecommendationApi(api)
          .loadCategories()
          .catchError((Object error) {
            _categories = null;
            throw error;
          });

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _goal = await CareerGoalApi(api).load();
      _loaded = true;
    } on AuthFailure catch (e) {
      _error = e.message;
    } catch (_) {
      _error = '목표 직무를 불러오지 못했습니다.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Throws [AuthFailure] (409 when another device changed the goal first).
  Future<void> save(List<String> categoryCodes, String keyword) async {
    _goal = await CareerGoalApi(api).save(
      categoryCodes: categoryCodes,
      keyword: keyword.trim(),
      expectedVersion: _goal.version,
    );
    _loaded = true;
    _error = null;
    notifyListeners();
  }
}
