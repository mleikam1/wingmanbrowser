import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../presentation/app_route_observer.dart';
import '../config/product_edition.dart';
import 'browser_engine.dart' show BrowserEngine;
import '../policy/strict_search_policy.dart';

/// Native browser transport. Each adapter validates its mandatory baseline
/// before allocating a renderer; pages have no privileged Dart/JS bridge.
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
            result?['supported'] == true && result?['mode'] == 'consumerWeb',
        privateAvailable: result?['privateAvailable'] == true,
        downloads: result?['downloads'] == true,
        uploads: result?['uploads'] == true,
        defaultBrowser: result?['defaultBrowserAvailable'] == true,
        strictSearchAvailable:
            result?['supported'] == true &&
            result?['mode'] == 'consumerWeb' &&
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
    this.uploads = false,
    this.downloads = false,
    this.defaultBrowser = false,
  });
  final bool supported, privateAvailable, strictSearchAvailable;
  final bool uploads, downloads, defaultBrowser;
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
    this.canGoBack = false,
    this.canGoForward = false,
  });
  final Uri? url;
  final String title;
  final int progress;
  final int? blockedResources, loadedResources;
  final bool loading, canGoBack, canGoForward;
  final String? error;
  bool get committed =>
      url != null && !loading && error == null && progress == 100;
}

/// Only current native events may become committed page metadata. No decisions,
/// page bodies, cookies or history are sent to an application server.
class ProtectedWebController extends ChangeNotifier implements BrowserEngine {
  ProtectedWebController({
    required this.canOpen,
    required this.onNavigation,
    this.onNewWindow,
    this.onNewWindowWithToken,
    this.onCloseRequested,
    this.onBlocked,
  });
  final bool Function(Uri) canOpen;
  final ValueChanged<Uri> onNavigation;
  final ValueChanged<Uri>? onNewWindow;
  final void Function(Uri, String?)? onNewWindowWithToken;
  final VoidCallback? onCloseRequested;
  final ValueChanged<String>? onBlocked;
  int? _viewId;
  int _requestId = 0;
  bool _disposed = false, _active = true;
  bool _failedWindowAdoption = false;
  @override
  Uri? get currentUrl => status.url;
  @override
  bool get attached => _viewId != null && !_disposed;
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

  /// Adopt WebKit's existing child window without replacing its request with
  /// GET or severing its opener. The token is native-owned and single-use.
  Future<void> adoptWindow(Uri uri, String token) async {
    final id = _viewId;
    if (_disposed || !_active || id == null) return;
    _failedWindowAdoption = false;
    final request = ++_requestId;
    if (!canOpen(uri)) {
      _failedWindowAdoption = true;
      _failure('The new window is outside the current supported scope.');
      await command('close');
      return;
    }
    status = ProtectedWebStatus(url: uri, loading: true);
    notifyListeners();
    try {
      await ProtectedWebBridge.channel.invokeMethod<void>('adoptWindow', {
        'viewId': id,
        'requestId': request,
        'windowToken': token,
      });
    } catch (_) {
      if (!_disposed && request == _requestId) {
        _failedWindowAdoption = true;
        _failure('The new window expired or its owning session changed.');
        await command('close');
      }
    }
  }

  @override
  Future<void> open(Uri uri) async {
    final id = _viewId;
    if (_disposed || !_active || id == null) return;
    _failedWindowAdoption = false;
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
      final query = uri.queryParameters['q'];
      final search =
          query != null &&
          const StrictSearchPolicy().acceptsCanonical(uri) &&
          uri == const StrictSearchPolicy().buildQuery(query);
      await ProtectedWebBridge.channel
          .invokeMethod<void>(search ? 'openSearch' : 'open', {
            'viewId': id,
            if (search)
              'query': uri.queryParameters['q']
            else
              'url': uri.toString(),
            'requestId': request,
          });
    } catch (error) {
      if (!_disposed && request == _requestId) {
        _failure(
          error is PlatformException &&
                  error.message ==
                      "This site's encoded address cannot be checked safely. Use its standard address."
              ? error.message!
              : 'This page could not open with the required protections.',
        );
      }
    }
  }

  // Hide/pause without destroying the renderer, navigation stack or data.
  // Events cannot trigger navigation while a route or app overlay covers it.
  @override
  Future<void> suspend() async {
    _active = false;
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

  @override
  Future<void> resume(Uri uri) async {
    if (_disposed) return;
    _active = true;
    if (_failedWindowAdoption) return;
    if (status.url == null || status.error != null) {
      await open(uri);
    } else {
      await command('setActive', {'active': true});
    }
  }

  Future<void> command(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final id = _viewId;
    if (_disposed || id == null) return;
    try {
      await ProtectedWebBridge.channel.invokeMethod<Object?>(method, {
        'viewId': id,
        ...arguments,
      });
    } on PlatformException {
      if (!_disposed && _active) {
        onBlocked?.call('This browser action could not complete. Try again.');
      }
    }
  }

  @override
  Future<void> back() => command('back');
  @override
  Future<void> forward() => command('forward');
  @override
  Future<void> reload() => command('reload');
  @override
  Future<void> stop() => command('stop');
  @override
  Future<void> find(String query) => command('find', {'query': query});
  @override
  Future<void> findNext({bool forward = true}) =>
      command('findNext', {'forward': forward});
  @override
  Future<void> share() => command('share');

  void _failure(String message) {
    if (_disposed) return;
    status = ProtectedWebStatus(error: message);
    notifyListeners();
  }

  void _event(String method, Map<dynamic, dynamic> value) {
    if (_disposed || value['viewId'] != _viewId) return;
    if (value['requestId'] != _requestId) return;
    if (method == 'rendererGone') {
      _failure('The page stopped. Reload to try again.');
      return;
    }
    if (method == 'closeRequested') {
      onCloseRequested?.call();
      return;
    }
    final raw = value['url'];
    final uri = raw is String && raw.length <= 4096 ? Uri.tryParse(raw) : null;
    if (method == 'navigationBlocked') {
      if (_active) {
        onBlocked?.call(
          value['reason'] ==
                  "This site's encoded address cannot be checked safely. Use its standard address."
              ? "This site's encoded address cannot be checked safely. Use its standard address."
              : 'This destination is blocked by your protection policy.',
        );
      }
      return;
    }
    if (method == 'newWindowRequested') {
      final token = value['windowToken'];
      if (token != null &&
          (token is! String ||
              !RegExp(r'^[A-Za-z0-9-]{1,100}$').hasMatch(token))) {
        return;
      }
      if (_active && uri != null && canOpen(uri)) {
        if (onNewWindowWithToken != null) {
          onNewWindowWithToken!(uri, token as String?);
        } else {
          onNewWindow?.call(uri);
        }
      }
      return;
    }
    if (method == 'navigationRequested') {
      if (!_active) return;
      // The native delegate already canceled this request. The Shell must
      // explain a denied link through policy, not silently load it or erase
      // the current committed page. No candidate metadata is published here.
      if (uri != null) onNavigation(uri);
      return;
    }
    // Auxiliary callbacks (for example findResult) do not carry a page URL.
    // Only pageState can update or invalidate the committed document.
    if (method != 'pageState') return;
    if (uri == null || !canOpen(uri)) {
      unawaited(suspend());
      _failure('This page is outside the current supported scope.');
      return;
    }
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
      canGoBack: value['canGoBack'] == true,
      canGoForward: value['canGoForward'] == true,
      blockedResources: value['blockedResources'] is int
          ? count('blockedResources', 100000)
          : null,
      loadedResources: value['loadedResources'] is int
          ? count('loadedResources', 100000)
          : null,
      error: value['error'] == null
          ? null
          : const {
              "The site's TLS certificate is invalid. The connection was blocked.",
              'The secure connection could not be verified. Wingman did not bypass it.',
            }.contains(value['error'])
          ? 'The secure connection could not be verified. The connection was blocked.'
          : 'This page could not load. Check your connection or try another page.',
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
    this.active = true,
    this.onController,
    this.onNewWindow,
    this.onNewWindowWithToken,
    this.onCloseRequested,
    this.windowToken,
    this.onBlocked,
    this.restrictions = const {},
  });
  final String tabId;
  final Uri url;
  final bool isPrivate;
  final bool Function(Uri) canOpen;
  final Listenable policyChanges;
  final ValueChanged<Uri> onNavigation;
  final ValueChanged<ProtectedWebStatus> onStatus;
  final int revision;
  final bool active;
  final ValueChanged<ProtectedWebController>? onController;
  final ValueChanged<Uri>? onNewWindow;
  final void Function(Uri, String?)? onNewWindowWithToken;
  final VoidCallback? onCloseRequested;
  final String? windowToken;
  final ValueChanged<String>? onBlocked;
  final Map<String, Object?> restrictions;

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
      canOpen: (uri) => mounted && widget.canOpen(uri),
      onNavigation: (uri) => widget.onNavigation(uri),
      onNewWindow: (uri) => widget.onNewWindow?.call(uri),
      onNewWindowWithToken: (uri, token) {
        if (widget.onNewWindowWithToken != null) {
          widget.onNewWindowWithToken!(uri, token);
        } else {
          widget.onNewWindow?.call(uri);
        }
      },
      onCloseRequested: () => widget.onCloseRequested?.call(),
      onBlocked: (message) => widget.onBlocked?.call(message),
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
    if (oldWidget.active != widget.active) {
      if (widget.active) {
        _resume();
      } else {
        _suspend();
      }
    }
    if (oldWidget.restrictions.toString() != widget.restrictions.toString()) {
      unawaited(_controller.command('updateRestrictions', widget.restrictions));
    }
    if (oldWidget.url != widget.url || oldWidget.revision != widget.revision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active && !_covered && !_background) {
          unawaited(_controller.open(widget.url));
        }
      });
    }
  }

  void _suspend() {
    unawaited(_controller.suspend());
    if (mounted) setState(() {});
  }

  void _resume() {
    if (mounted && widget.active && !_covered && !_background) {
      setState(() {});
      unawaited(_controller.resume(widget.url));
    }
  }

  @override
  void didPushNext() {
    if (appRouteObserver.showsBrowserControls) return;
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
    final params = {
      'tabId': widget.tabId,
      'private': widget.isPrivate,
      'edition': productEdition.name,
      ...widget.restrictions,
      if (widget.windowToken != null) 'windowToken': widget.windowToken,
    };
    void created(int id) {
      final token = widget.windowToken;
      _controller.attach(id);
      widget.onController?.call(_controller);
      if (widget.active && !_covered && !_background) {
        unawaited(
          token == null
              ? _controller.open(widget.url)
              : _controller.adoptWindow(widget.url, token),
        );
      }
    }

    final view = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidView(
        viewType: 'wingman/protected-web',
        gestureRecognizers: {
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        },
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: created,
      ),
      TargetPlatform.iOS => UiKitView(
        viewType: 'wingman/protected-web',
        gestureRecognizers: {
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        },
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
