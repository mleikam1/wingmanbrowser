import 'package:flutter/widgets.dart';

/// Reuses a controller safely across deferred/lazy mounts while each new
/// ScrollPosition restores this tab's latest memory-only reading position.
class TabScrollController extends ScrollController {
  TabScrollController({required this.readOffset})
    : super(keepScrollOffset: false);
  final double Function() readOffset;
  @override
  double get initialScrollOffset => readOffset();
}
