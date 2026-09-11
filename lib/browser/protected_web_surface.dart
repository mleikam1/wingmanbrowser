import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../presentation/app_route_observer.dart';
import '../policy/strict_search_policy.dart';

/// A separate, restricted bridge. Retired browser commands remain retired.
/// Native code independently checks its build-pinned website/resource manifest.
abstract final class ProtectedWebBridge {
  static const channel = MethodChannel('wingman/protected-browser');
  static final Map<int, ProtectedWebController> _views = {};
  static bool _listening = false;

  static Future<ProtectedWebCapabilities> capabilities() async {
    if (kIsWeb) return const ProtectedWebCapabilities();
    try {
      final result = await channel.invokeMapMethod<String, Object?>(
        'capabilities',
      );
      return ProtectedWebCapabilities(
        supported:
            result?['supported'] == true &&
            result?['mode'] == 'reviewedScriptlessWeb',
        privateAvailable: result?['privateAvailable'] == true,
        strictSearchAvailable:
            result?['supported'] == true &&
            result?['mode'] == 'reviewedScriptlessWeb' &&
            result?['strictSearchAvailable'] == true,
      );
    } catch (_) {
      return const ProtectedWebCapabilities();
    }
  }

  static void _attach(int id, ProtectedWebController view) {
    if (!_listening) {
      channel.setMethodCallHandler((call) async {
        final arguments = call.arguments;
        if (arguments is! Map || arguments['viewId'] is! int) return;
        _views[arguments['viewId']]?._event(call.method, arguments);
      });
      _listening = true;
    }
    _views[id] = view;
  }

  static void _detach(int id, ProtectedWebController view) {
    if (identical(_views[id], view)) _views.remove(id);
  }
}

class ProtectedWebCapabilities {
  const ProtectedWebCapabilities({
    this.supported = false,
    this.privateAvailable = false,
    this.strictSearchAvailable = false,
  });
  final bool supported, privateAvailable, strictSearchAvailable;
}

class ProtectedWebStatus {
  const ProtectedWebStatus({
    this.url,
    this.title = '',
    this.progress = 0,
    this.loading = false,
    this.blockedResources,
    this.loadedResources,
    this.error,
  });
  final Uri? url;
  final String title;
  final int progress;
  final int? blockedResources, loadedResources;
  final bool loading;
  final String? error;
  bool get committed =>
      url != null && !loading && error == null && progress == 100;
}

/// Only current native events may become committed page metadata. No decisions,
/// page bodies, cookies or history are sent to an application server.
class ProtectedWebController extends ChangeNotifier {
  ProtectedWebController({required this.canOpen, required this.onNavigation});
  final bool Function(Uri) canOpen;
  final ValueChanged<Uri> onNavigation;
  int? _viewId;
  int _requestId = 0;
  bool _disposed = false, _active = true;
  ProtectedWebStatus status = const ProtectedWebStatus();

  void attach(int id) {
    if (_disposed || _viewId == id) return;
    final previous = _viewId;
    if (previous != null) {
      ProtectedWebBridge._detach(previous, this);
      unawaited(
        ProtectedWebBridge.channel
            .invokeMethod<void>('close', {'viewId': previous})
            .catchError((Object _) {}),
      );
    }
    _requestId++;
    _viewId = id;
    ProtectedWebBridge._attach(id, this);
  }

  Future<void> open(Uri uri) async {
    final id = _viewId;
    if (_disposed || !_active || id == null) return;
    final request = ++_requestId;
    if (!canOpen(uri)) {
      final stopping = suspend();
      _failure('This page is outside the current supported scope.');
      await stopping;
      return;
    }
    status = ProtectedWebStatus(url: uri, loading: true);
    notifyListeners();
    try {
      await ProtectedWebBridge.channel.invokeMethod<void>('setActive', {
        'viewId': id,
        'active': true,
      });
      if (_disposed || !_active || request != _requestId) return;
      if (!canOpen(uri)) {
        final stopping = suspend();
        _failure('This page is outside the current supported scope.');
        await stopping;
        return;
      }
      final search = const StrictSearchPolicy().acceptsCanonical(uri);
      await ProtectedWebBridge.channel
          .invokeMethod<void>(search ? 'openSearch' : 'open', {
            'viewId': id,
            if (search)
              'query': uri.queryParameters['q']
            else
              'url': uri.toString(),
            'requestId': request,
          });
    } catch (_) {
      if (!_disposed && request == _requestId) {
        _failure('This page could not open with the required protections.');
      }
    }
  }

  // Keep last committed metadata for an explicit pin from an overlaid menu.
  // Native content is destroyed; suspended events cannot change this snapshot.
  Future<void> suspend() async {
    _active = false;
    _requestId++;
    final id = _viewId;
    if (id == null) return;
    try {
      await ProtectedWebBridge.channel.invokeMethod<void>('setActive', {
        'viewId': id,
        'active': false,
      });
    } catch (_) {
      // Native lifetime/handoff gates independently remove the content view.
    }
  }

  Future<void> resume(Uri uri) async {
    if (_disposed) return;
    _active = true;
    await open(uri);
  }

  void _failure(String message) {
    if (_disposed) return;
    status = ProtectedWebStatus(error: message);
    notifyListeners();
  }

  void _event(String method, Map<dynamic, dynamic> value) {
    if (_disposed || !_active || value['viewId'] != _viewId) return;
    if (value['requestId'] != _requestId) return;
    if (method == 'rendererGone') {
      _failure('The page stopped. Reload to try again.');
      return;
    }
    final raw = value['url'];
    final uri = raw is String && raw.length <= 4096 ? Uri.tryParse(raw) : null;
    if (method == 'navigationRequested') {
      // The native delegate already canceled this request. The Shell must
      // explain a denied link through policy, not silently load it or erase
      // the current committed page. No candidate metadata is published here.
      if (uri != null) onNavigation(uri);
      return;
    }
    if (uri == null || !canOpen(uri)) {
      unawaited(suspend());
      _failure('This page is outside the current supported scope.');
      return;
    }
    if (method != 'pageState') return;
    int count(String key, int maximum) =>
        value[key] is int ? (value[key] as int).clamp(0, maximum) : 0;
    final rawTitle = value['title'];
    status = ProtectedWebStatus(
      url: uri,
      title: rawTitle is String
          ? rawTitle
                .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
                .characters
                .take(160)
                .toString()
          : '',
      progress: count('progress', 100),
      loading: value['isLoading'] == true,
      blockedResources: value['blockedResources'] is int
          ? count('blockedResources', 100000)
          : null,
      loadedResources: value['loadedResources'] is int
          ? count('loadedResources', 100000)
          : null,
      error: value['error'] == null
          ? null
          : 'This page could not finish within its supported scope.',
    );
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _active = false;
    _requestId++;
    final id = _viewId;
    if (id != null) {
      ProtectedWebBridge._detach(id, this);
      unawaited(
        ProtectedWebBridge.channel
            .invokeMethod<void>('close', {'viewId': id})
            .catchError((Object _) {}),
      );
    }
    super.dispose();
  }
}

class ProtectedWebSurface extends StatefulWidget {
  const ProtectedWebSurface({
    super.key,
    required this.tabId,
    required this.url,
    required this.isPrivate,
    required this.canOpen,
    required this.policyChanges,
    required this.onNavigation,
    required this.onStatus,
    this.revision = 0,
  });
  final String tabId;
  final Uri url;
  final bool isPrivate;
  final bool Function(Uri) canOpen;
  final Listenable policyChanges;
  final ValueChanged<Uri> onNavigation;
  final ValueChanged<ProtectedWebStatus> onStatus;
  final int revision;

  @override
  State<ProtectedWebSurface> createState() => _ProtectedWebSurfaceState();
}

class _ProtectedWebSurfaceState extends State<ProtectedWebSurface>
    with WidgetsBindingObserver, RouteAware {
  late final ProtectedWebController _controller;
  ModalRoute<dynamic>? _route;
  bool _covered = false, _background = false;
  @override
  void initState() {
    super.initState();
    _controller = ProtectedWebController(
      canOpen: (uri) =>
          mounted && !_covered && !_background && widget.canOpen(uri),
      onNavigation: (uri) => widget.onNavigation(uri),
    )..addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    widget.policyChanges.addListener(_recheck);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route && route != null) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    widget.onStatus(_controller.status);
  }

  void _recheck() {
    if (!widget.canOpen(widget.url)) {
      unawaited(_controller.suspend());
      if (mounted) setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant ProtectedWebSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.policyChanges != widget.policyChanges) {
      oldWidget.policyChanges.removeListener(_recheck);
      widget.policyChanges.addListener(_recheck);
    }
    if (oldWidget.url != widget.url || oldWidget.revision != widget.revision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_covered && !_background) {
          unawaited(_controller.resume(widget.url));
        }
      });
    }
  }

  void _suspend() {
    unawaited(_controller.suspend());
    if (mounted) setState(() {});
  }

  void _resume() {
    if (mounted && !_covered && !_background) {
      setState(() {});
      unawaited(_controller.resume(widget.url));
    }
  }

  @override
  void didPushNext() {
    _covered = true;
    _suspend();
  }

  @override
  void didPopNext() {
    _covered = false;
    _resume();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _background = state != AppLifecycleState.resumed;
    if (_background) {
      _suspend();
    } else {
      _resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !widget.canOpen(widget.url)) {
      return const Center(
        child: Text('This website is unavailable on this platform.'),
      );
    }
    final params = {'tabId': widget.tabId, 'private': widget.isPrivate};
    void created(int id) {
      _controller.attach(id);
      if (!_covered && !_background) unawaited(_controller.open(widget.url));
    }

    final view = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidView(
        viewType: 'wingman/protected-web',
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: created,
      ),
      TargetPlatform.iOS => UiKitView(
        viewType: 'wingman/protected-web',
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: created,
      ),
      _ => const Center(
        child: Text('Use the Android or iOS app for supported websites.'),
      ),
    };
    return Stack(
      fit: StackFit.expand,
      children: [
        view,
        if (_covered || _background)
          const ColoredBox(
            color: Color(0xff07182e),
            child: Center(
              child: Icon(Icons.shield_outlined, color: Colors.white, size: 48),
            ),
          )
        else if (_controller.status.error != null)
          ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_controller.status.error!),
              ),
            ),
          )
        else if (_controller.status.loading)
          Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(
              value: _controller.status.progress > 0
                  ? _controller.status.progress / 100
                  : null,
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    widget.policyChanges.removeListener(_recheck);
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }
}
