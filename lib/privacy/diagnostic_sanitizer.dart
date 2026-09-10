enum DiagnosticCode {
  networkFailure,
  storageFailure,
  permissionDenied,
  adError,
}

enum NavigationTransport { https, http, other }

/// Categorizes instead of attempting to redact secrets from arbitrary text.
/// Hostnames themselves may reveal sensitive browsing interests, so even a
/// URL's origin is excluded. Never pass raw exceptions into production logs.
class DiagnosticSanitizer {
  const DiagnosticSanitizer._();

  static NavigationTransport transport(Uri? uri) => switch (uri?.scheme) {
    'https' => NavigationTransport.https,
    'http' => NavigationTransport.http,
    _ => NavigationTransport.other,
  };

  /// [cause] is deliberately never converted to a string. Error descriptions
  /// from websites and platform SDKs can contain URLs, tokens and page content.
  static String failure(DiagnosticCode code, {Object? cause}) => code.name;
}
