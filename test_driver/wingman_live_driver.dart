import 'package:integration_test/integration_test_driver.dart';

// Attach only with flutter drive --use-existing-app to the explicitly installed
// opt-in live verification build. This driver never builds, installs or launches
// the app. Do not omit --use-existing-app: the ordinary drive path can reinstall.
Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 4),
  responseDataCallback: null,
);
