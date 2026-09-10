import 'package:flutter/widgets.dart';

/// Local route lifetime only. Register on the app Navigator so consent/ad work
/// is invalidated synchronously when any route or popup covers owned Home.
/// This observer records no route names, URLs, analytics or user activity.
final adRouteObserver = RouteObserver<ModalRoute<dynamic>>();
