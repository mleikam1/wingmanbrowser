import 'package:flutter/widgets.dart';

/// Local route lifetime only. Reader and library operations use this to reject
/// stale results when another route covers them. No activity is recorded.
final appRouteObserver = RouteObserver<ModalRoute<dynamic>>();
