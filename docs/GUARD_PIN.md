# Local Guard PIN

`lib/guard_pin/guard_pin_service.dart` provides an optional local settings lock. It protects Guard changes inside Wingman; it is not device management, remote parental control, database encryption or protection against an owner who can modify the app/device. It does not control Safari, Chrome, other apps or other devices.

The PIN is 6–12 ASCII digits. Wingman derives a 32-byte verifier with PBKDF2-HMAC-SHA256, 600,000 iterations and a new 32-byte cryptographically random salt. Only the versioned verifier record, salt and failed-attempt state enter platform secure storage. The PIN is never written to SQLite, preferences, logs or a server. Dart strings and memory are managed by the runtime; this is not a promise of guaranteed memory erasure. [Password derivation guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)

Android uses `flutter_secure_storage` 11.1's default RSA-OAEP/AES-GCM storage with platform KeyStore protection. App backup is disabled. iOS uses Keychain with `unlocked_this_device` accessibility and `synchronizable: false`. There is no browser LocalStorage PIN fallback: the web companion reports the feature unsupported. This does not add a biometric prompt or require new camera/location permissions. [Secure-storage package](https://pub.dev/packages/flutter_secure_storage), [Apple accessibility attribute](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly)

Reads, parse failures and non-persisting writes fail closed. A failed secure-store read is never converted to “no PIN.” The service rereads after each write before granting access. Five attempted verifications trigger a 30-second delay, then exponential delays capped at an hour. Attempts are serialized and persisted before expensive derivation, preventing parallel requests or terminating the process mid-attempt from resetting the normal retry budget. A correct PIN cannot skip an active delay. Successful verification resets the counter. Clock changes, app modification, device compromise or deleting protected app data are outside this app-level lock's tamper guarantees.

The derivation runs in a worker isolate on Android/iOS so ordinary UI remains responsive. Unlock screens should show a busy state. PIN setup finishes locked. Replacement/removal requires the current PIN, including when a settings session is already unlocked. Backgrounding or leaving the protected session should call `lock()`; a pending unlock whose lock revision changed cannot grant access later. A newly created service reads an existing verifier into locked state and never persists an unlocked Boolean.

There is no remote PIN reset or recovery account. Explain this before enabling a PIN. iOS Keychain items may remain after an app reinstall; do not promise that reinstall always resets a Guard PIN. A future recovery flow needs a separately reviewed local/device-authentication and data-reset design, not a hidden bypass or an automatic credential overwrite.

## API

```dart
final pin = GuardPinService();
await pin.initialize();
// status: loading / notConfigured / locked / unlocked / unavailable / unsupported
// isLocked is also true for loading and unavailable: do not weaken policy.
final result = await pin.unlock(userInput);
if (result.success) {
  // Permit only the intended protected settings action/session.
}
pin.lock();
```

`setPin(newPin, currentPin: ...)` and `removePin(pin)` return the same `GuardPinAttempt` shape: `success`, fixed `reason` enum, and `retryAfter`. The UI must mediate every protected mutation, not only opening the settings page. Private browsing must continue using the same Guard policy. Do not place unlock state in a remote configuration or ordinary SQLite setting.

## Verification

The focused state-machine suite covers invalid input, salted records, restart-style service replacement, failed/corrupt storage, read-after-write verification, persisted rate limits, concurrent attempts, background cancellation, replacement/removal authorization and unsupported targets. Production PBKDF2 is checked against an independently calculated Python `hashlib` known answer. On the development host it took 1,860 ms in that run; this is not a mobile benchmark.

`integration_test/guard_pin_test.dart` is a separate native smoke test using the real secure-storage adapter and production derivation, with the isolated key `wingman.guard.pin.smoke.v1`. It never accesses the user's production credential key. It passed on September 10, 2026 on the reserved Android emulator and iOS simulator using the actual platform adapters. Both runs verified secure-store roundtrip, locked service replacement, rejected incorrect PIN, absent plaintext, and removal of the isolated test key. The measured test operation took 10,810 ms on Android and 8,051 ms on iOS; these durations include several derivations and storage operations, not just one unlock. Logs are retained outside the repository as `work/phase2-pin-android.log` and `work/phase2-pin-ios.log`. Service replacement occurs in the same app process; these tests do not establish a cold OS relaunch, physical-device timing, backup restoration, or compromised-device resistance.

Run from the repository root with a reserved native target:

```sh
flutter test test/guard_pin
flutter test integration_test/guard_pin_test.dart -d emulator-5556
flutter test integration_test/guard_pin_test.dart -d C157677F-A33F-45B2-BFFB-F3DED552D4F4
```

Device IDs describe this development environment; use `flutter devices` elsewhere. The smoke test's separate key prevents it from resetting a real Guard PIN.
