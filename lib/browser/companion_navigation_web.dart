import 'dart:js_interop';

@JS('window.location.assign')
external void _assign(String url);

/// User-submitted top-level navigation. The host browser owns the destination;
/// Wingman cannot enforce its native filtering after this handoff.
void navigateCompanion(Uri destination) {
  if (destination.scheme != 'https' || destination.userInfo.isNotEmpty) {
    throw const FormatException('A secure web destination is required.');
  }
  _assign(destination.toString());
}
