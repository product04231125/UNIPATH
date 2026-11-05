/// Device-local data is partitioned by the authenticated server UUID.
/// This is storage organization, not encryption or server authorization.
class LocalDataOwner {
  const LocalDataOwner(this.userId);
  static String? currentUserId;
  factory LocalDataOwner.current() => LocalDataOwner(currentUserId);
  final String? userId;
  String key(String base) => userId == null ? base : '$base.account.$userId';
}
