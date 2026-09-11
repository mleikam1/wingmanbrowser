import 'package:flutter/material.dart';
import '../design_system/wingman_tokens.dart';

/// Opaque app navigation. No previous page is faded through a sensitive route.
class WingmanPageTransitions extends PageTransitionsBuilder {
  const WingmanPageTransitions();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return ColoredBox(
      color: WingmanTokens.of(context).canvas,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(.02, 0), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: child,
      ),
    );
  }
}

class WingmanRoute<T> extends MaterialPageRoute<T> {
  WingmanRoute({required super.builder, super.settings})
    : super(allowSnapshotting: false);
  @override
  Duration get transitionDuration => WingmanTokens.route;
  @override
  Duration get reverseTransitionDuration => WingmanTokens.route;
}
