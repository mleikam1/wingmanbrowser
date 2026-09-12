import 'package:flutter/widgets.dart';

/// Local route lifetime only. Reader and library operations use this to reject
/// stale results when another route covers them. No activity is recorded.
final appRouteObserver = AppRouteObserver();

class AppRouteObserver extends RouteObserver<ModalRoute<dynamic>> {
  final List<Route<dynamic>> _routes = [];

  /// An app-owned find control needs the document visible beneath its dialog.
  bool get showsBrowserControls =>
      _routes.isNotEmpty &&
      _routes.last.settings.name == 'wingman-browser-find';
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) _routes.clear();
    _routes.add(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  /// A destroyed private scope must not leave a dialog or reverse-animation
  /// snapshot visible. Other/new tab scopes never call this operation.
  void removePrivateFeatureRoutes(NavigatorState owner) {
    if (!identical(navigator, owner)) return;
    for (final route in _routes.reversed.toList()) {
      if (!route.isFirst) owner.removeRoute(route);
    }
  }
}
