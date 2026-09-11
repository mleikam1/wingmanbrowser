import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One envelope holds both the owner-return verifier and active startup gate.
/// There is deliberately no normal-preferences or web-storage fallback.
abstract interface class HandoffStore {
  bool get supported;
  Future<String?> read();
  Future<void> write(String value);
}

class PlatformHandoffStore implements HandoffStore {
  PlatformHandoffStore() : _key = 'wingman.handoff.session.v1';

  @visibleForTesting
  PlatformHandoffStore.forTesting() : _key = 'wingman.handoff.smoke.v1';

  final String _key;
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      storageNamespace: 'wingman.handoff.v1',
    ),
    iOptions: IOSOptions(
      accountName: 'wingman.handoff',
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
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}
