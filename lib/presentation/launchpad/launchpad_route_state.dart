import 'package:flutter/material.dart';
import '../app_route_observer.dart';
import '../components/wingman_components.dart';
import 'launchpad_actions.dart';

class _LaunchpadLifecycle extends WidgetsBindingObserver {
  _LaunchpadLifecycle(this.changed);
  final void Function(AppLifecycleState) changed;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => changed(state);
}

class _LaunchpadDialogObserver extends RouteAware {
  _LaunchpadDialogObserver(this.covered);
  final VoidCallback covered;
  @override
  void didPushNext() => covered();
}

mixin LaunchpadRouteState<T extends StatefulWidget> on State<T>
    implements RouteAware {
  LaunchpadActions get actions;
  bool busy = false;
  (Object, int)? _reorderAction;
  String? error;
  int _generation = 0;
  int? _operationGeneration;
  bool _ownedCover = false, _foreground = true;
  ModalRoute<dynamic>? _route;
  Listenable? _changes;
  late final _lifecycle = _LaunchpadLifecycle((state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _generation++;
  });
  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(_lifecycle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!identical(route, _route)) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) appRouteObserver.subscribe(this, route);
    }
    _listen();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _listen();
  }

  void _listen() {
    if (identical(_changes, actions.changes)) return;
    _changes?.removeListener(_scopeChanged);
    _changes = actions.changes;
    _changes?.addListener(_scopeChanged);
  }

  void _scopeChanged() {
    if (!actions.canContinue()) _generation++;
  }

  @override
  void didPushNext() {
    if (_ownedCover) {
      _ownedCover = false;
    } else {
      _generation++;
    }
  }

  @override
  void didPush() {}
  @override
  void didPopNext() {}
  @override
  void didPop() {
    _generation++;
  }

  @override
  void dispose() {
    _generation++;
    _changes?.removeListener(_scopeChanged);
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(_lifecycle);
    super.dispose();
  }

  bool get current =>
      mounted &&
      _foreground &&
      actions.canContinue() &&
      (_operationGeneration == null || _operationGeneration == _generation) &&
      (ModalRoute.of(context)?.isCurrent ?? false);

  // Keep the initiating reorder control focusable across a durable write.
  // Disabling it would discard keyboard focus; busy still blocks re-entry.
  bool reorderEnabled(Object id, int step) =>
      !busy || _reorderAction == (id, step);

  Future<bool> reorderChange(
    Object id,
    int step,
    Future<void> Function() operation,
  ) async {
    if (!current || busy) return false;
    _reorderAction = (id, step);
    try {
      return await change(operation);
    } finally {
      _reorderAction = null;
    }
  }

  Future<bool> change(Future<void> Function() operation) async {
    if (!current || busy) return false;
    _operationGeneration = _generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await operation();
      return current;
    } catch (_) {
      if (current) {
        setState(
          () => error =
              'The change could not be saved. Your previous Launchpad is retained.',
        );
      }
      return false;
    } finally {
      _operationGeneration = null;
      if (mounted) setState(() => busy = false);
    }
  }

  /// One owned confirmation may cover this route. Backgrounding or another
  /// route covering that dialog invalidates it permanently, even after return.
  Future<R?> ownedDialog<R>(WidgetBuilder builder) async {
    if (!current || busy) return null;
    final generation = _generation;
    final route = DialogRoute<R>(context: context, builder: builder);
    final observer = _LaunchpadDialogObserver(() => _generation++);
    _ownedCover = true;
    final pending = Navigator.of(context).push(route);
    _ownedCover = false;
    appRouteObserver.subscribe(observer, route);
    final result = await pending;
    await route.completed;
    appRouteObserver.unsubscribe(observer);
    return current && generation == _generation ? result : null;
  }

  Widget failure(String? storageError) => error == null && storageError == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: WingmanStatus(
            title: 'Change not saved',
            message: error ?? storageError!,
            tone: WingmanTone.caution,
          ),
        );

  Future<bool> confirm({
    required String title,
    required String message,
    required String accept,
    String cancel = 'Cancel',
  }) async =>
      await ownedDialog<bool>(
        (dialog) => AlertDialog(
          title: Text(title),
          scrollable: true,
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(accept),
            ),
          ],
        ),
      ) ==
      true;
}
