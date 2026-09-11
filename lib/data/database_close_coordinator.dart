/// All application database owners share one native close queue. Android's
/// sqflite worker pool can stop after the first of two concurrent final closes,
/// leaving the second native callback unresolved. Await each close before
/// dispatching another; callers still receive their own completion or failure.
final databaseCloseCoordinator = DatabaseCloseCoordinator();

class DatabaseCloseCoordinator {
  Future<void> _pending = Future.value();

  Future<void> run(Future<void> Function() close) {
    final result = _pending.then((_) => close());
    // A failed owner must not prevent another database from closing.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
