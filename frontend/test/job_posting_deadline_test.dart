import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/job_recommendation_api.dart';
import 'package:university_path_frontend/features/records/portfolio/job_recommendation_result.dart';

RecommendationPosting posting({String? expiresAt, String label = '확인 필요'}) =>
    RecommendationPosting.fromJson({
      'source': 'work24',
      'source_id': 'K000000000001',
      'title': '합성 개발자',
      'company': '합성 회사',
      'url': 'https://www.work24.go.kr/synthetic',
      'location': '서울',
      'closing_label': label,
      'expires_at': expiresAt,
    });

void main() {
  final now = DateTime.utc(2026, 11, 22, 3);

  test('end-of-day Korea deadline shows the date and weekday only', () {
    expect(
      postingDeadlineLabel(
        posting(expiresAt: '2026-11-30T23:59:59+09:00'),
        now: now,
      ),
      '마감 11월 30일(월)',
    );
  });

  test('offset deadlines stay in Korea time whatever the device zone', () {
    // 2026-12-01 18:00 KST written in UTC.
    expect(
      postingDeadlineLabel(
        posting(expiresAt: '2026-12-01T09:00:00Z'),
        now: now,
      ),
      '마감 12월 1일(화) 18:00',
    );
  });

  test('another year is spelled out and a plain date has no time', () {
    expect(
      postingDeadlineLabel(posting(expiresAt: '2027-01-05'), now: now),
      '마감 2027년 1월 5일(화)',
    );
  });

  test('without a date the posting closing text is kept', () {
    expect(postingDeadlineLabel(posting(label: '채용시까지'), now: now), '마감 채용시까지');
    expect(postingDeadlineLabel(posting(), now: now), '마감 확인 필요');
  });
}
