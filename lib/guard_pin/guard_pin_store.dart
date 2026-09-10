import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Only the salted verifier and retry state cross this boundary, never the PIN.
abstract interface class GuardPinStore {
  bool get supported;
  Future<String?> read();
  Future<void> write(String record);
  Future<void> delete();
}

class PlatformGuardPinStore implements GuardPinStore {
  PlatformGuardPinStore() : _key = 'wingman.guard.pin.v1';

  /// A fixed isolated key lets native tests verify the real adapter without
  /// reading, replacing or deleting the user's Guard credential.
  @visibleForTesting
  PlatformGuardPinStore.forTesting() : _key = 'wingman.guard.pin.smoke.v1';

  final String _key;
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accountName: 'wingman.guard',
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
  );

  @override
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String record) => _storage.write(key: _key, value: record);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}
