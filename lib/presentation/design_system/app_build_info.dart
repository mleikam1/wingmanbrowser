import '../../config/app_version.dart';

/// Kept in sync with pubspec.yaml by the design-system build metadata test.
class AppBuildInfo {
  const AppBuildInfo({required this.version, required this.build});
  final String version, build;
  static const current = AppBuildInfo(
    version: AppVersion.name,
    build: AppVersion.build,
  );
}
