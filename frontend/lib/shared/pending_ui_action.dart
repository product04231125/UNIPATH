/// An in-memory navigation intent, never persisted or encoded as domain data.
/// The destination consumes it only once, after its required state is ready.
class PendingUiAction {
  bool _consumed = false;
  bool get isPending => !_consumed;

  bool consume() {
    if (_consumed) return false;
    _consumed = true;
    return true;
  }
}
