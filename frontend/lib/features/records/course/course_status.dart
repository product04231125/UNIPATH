String courseStatusLabel(String value) => switch (value) {
  '이수 기록' || '이수 완료' || 'recorded' => '이수 완료',
  '수강 중' || 'in_progress' => '수강 중',
  '미이수' || 'not_completed' => '미이수',
  _ => '수강 예정',
};
