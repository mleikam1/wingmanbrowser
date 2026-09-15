import 'dart:js_interop';

@JS('window.location.assign')
external void _assign(String url);

@JS('window.open')
external JSAny? _open(String url, String target, String features);

/// User-submitted top-level navigation. The host browser owns the destination;
/// Wingman cannot enforce its native filtering after this handoff.
void navigateCompanion(Uri destination, {bool newTab = false}) {
  if (destination.scheme != 'https' || destination.userInfo.isNotEmpty) {
    throw const FormatException('A secure web destination is required.');
  }
  if (newTab) {
    // A synchronous, user-selected article leaves its Discover route intact.
    // Neither the publisher nor the new tab receives an opener or referrer.
    _open(destination.toString(), '_blank', 'noopener,noreferrer');
  } else {
    _assign(destination.toString());
  }
}
