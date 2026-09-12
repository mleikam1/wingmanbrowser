/// Kept in sync with pubspec.yaml by the design-system build metadata test.
class AppBuildInfo {
  const AppBuildInfo({required this.version, required this.build});
  final String version, build;
  static const current = AppBuildInfo(version: '0.10.0', build: '10');
}
