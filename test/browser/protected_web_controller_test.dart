import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/browser/protected_web_surface.dart';
import 'package:wingman_browser/policy/strict_search_policy.dart';
import 'package:wingman_browser/signature/workspaces/discovery_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();
  final moon = Uri.parse('https://science.nasa.gov/moon/facts/');
  final calls = <MethodCall>[];
  Future<void> native(String method, Map<String, Object?> value) async {
    final done = Completer<void>();
    await messenger.handlePlatformMessage(
      'wingman/protected-browser',
      codec.encodeMethodCall(MethodCall(method, value)),
      (_) => done.complete(),
    );
    await done.future;
  }

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(ProtectedWebBridge.channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(ProtectedWebBridge.channel, null),
  );

  test('unapproved open never sends a website load to native', () async {
    final controller = ProtectedWebController(
      canOpen: (_) => false,
      onNavigation: (_) {},
    )..attach(71);
    await controller.open(moon);
    expect(calls.where((c) => c.method == 'open'), isEmpty);
    expect(controller.status.url, isNull);
    expect(controller.status.error, isNotNull);
    controller.dispose();
  });

  test(
    'canonical search sends a query through its separate native capability',
    () async {
      final uri = const StrictSearchPolicy().buildQuery('moon + facts');
      final controller = ProtectedWebController(
        canOpen: (candidate) => candidate == uri,
        onNavigation: (_) {},
      )..attach(81);
      await controller.open(uri);
      expect(calls.where((c) => c.method == 'open'), isEmpty);
      final sent =
          calls.singleWhere((c) => c.method == 'openSearch').arguments as Map;
      expect(sent['query'], 'moon + facts');
      expect(sent.containsKey('url'), isFalse);
      expect(sent.keys.toSet(), {'viewId', 'requestId', 'query'});
      controller.dispose();
    },
  );

  test(
    'revocation during activation prevents search from reaching native',
    () async {
      var allowed = true;
      final activation = Completer<void>();
      messenger.setMockMethodCallHandler(ProtectedWebBridge.channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'setActive' &&
            (call.arguments as Map)['active'] == true) {
          await activation.future;
        }
        return null;
      });
      final controller = ProtectedWebController(
        canOpen: (_) => allowed,
        onNavigation: (_) {},
      )..attach(82);
      final pending = controller.open(
        const StrictSearchPolicy().buildQuery('moon'),
      );
      await Future<void>.delayed(Duration.zero);
      allowed = false;
      activation.complete();
      await pending;
      expect(calls.where((c) => c.method == 'openSearch'), isEmpty);
      expect(controller.status.url, isNull);
      controller.dispose();
    },
  );

  test(
    'only current approved native events become committed page metadata',
    () async {
      final controller = ProtectedWebController(
        canOpen: (uri) => uri == moon,
        onNavigation: (_) {},
      )..attach(72);
      await controller.open(moon);
      final request = (calls.last.arguments as Map)['requestId'] as int;
      final result = <String, Object?>{
        'viewId': 72,
        'requestId': request,
        'url': moon.toString(),
        'title': 'Moon facts',
        'progress': 100,
        'isLoading': false,
        'loadedResources': 4,
        'blockedResources': 3,
      };
      await native('pageState', {...result, 'requestId': request - 1});
      expect(controller.status.committed, isFalse);
      await native('pageState', {...result, 'viewId': 999});
      expect(controller.status.committed, isFalse);
      await native('pageState', result);
      expect(controller.status.committed, isTrue);
      expect(controller.status.title, 'Moon facts');
      await native('pageState', {
        ...result,
        'url': 'https://unreviewed.invalid/',
        'title': 'Unreviewed title',
      });
      expect(controller.status.committed, isFalse);
      expect(controller.status.title, isEmpty);
      expect(controller.status.url, isNull);
      controller.dispose();
    },
  );

  test('a policy change while activation is pending prevents a load', () async {
    var allowed = true;
    final activation = Completer<void>();
    messenger.setMockMethodCallHandler(ProtectedWebBridge.channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'setActive' &&
          (call.arguments as Map)['active'] == true) {
        await activation.future;
      }
      return null;
    });
    final controller = ProtectedWebController(
      canOpen: (_) => allowed,
      onNavigation: (_) {},
    )..attach(73);
    final opening = controller.open(moon);
    await Future<void>.delayed(Duration.zero);
    allowed = false;
    activation.complete();
    await opening;
    expect(calls.where((c) => c.method == 'open'), isEmpty);
    controller.dispose();
  });

  test(
    'covered or disposed views reject events and never replay a click',
    () async {
      final clicked = <Uri>[];
      final controller = ProtectedWebController(
        canOpen: (_) => true,
        onNavigation: clicked.add,
      )..attach(74);
      await controller.open(moon);
      final request = (calls.last.arguments as Map)['requestId'];
      await controller.suspend();
      await native('navigationRequested', {
        'viewId': 74,
        'requestId': request,
        'url': moon.toString(),
      });
      expect(clicked, isEmpty);
      controller.dispose();
      controller.dispose();
      await native('pageState', {
        'viewId': 74,
        'requestId': request,
        'url': moon.toString(),
        'progress': 100,
      });
      expect(calls.where((c) => c.method == 'close'), hasLength(1));
      expect(clicked, isEmpty);
    },
  );

  test(
    'a canceled unreviewed link is forwarded for policy explanation only',
    () async {
      final clicked = <Uri>[];
      final controller = ProtectedWebController(
        canOpen: (uri) => uri == moon,
        onNavigation: clicked.add,
      )..attach(75);
      await controller.open(moon);
      final request = (calls.last.arguments as Map)['requestId'];
      final unknown = Uri.parse('https://unreviewed.invalid/');
      await native('navigationRequested', {
        'viewId': 75,
        'requestId': request,
        'url': unknown.toString(),
      });
      expect(clicked, [unknown]);
      expect(calls.where((c) => c.method == 'open'), hasLength(1));
      expect(controller.status.url, moon);
      expect(controller.status.title, isEmpty);
      controller.dispose();
    },
  );

  test(
    'late failure from a rejected open cannot overwrite a newer load',
    () async {
      final stop = Completer<void>();
      messenger.setMockMethodCallHandler(ProtectedWebBridge.channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'setActive' &&
            (call.arguments as Map)['active'] == false) {
          await stop.future;
        }
        return null;
      });
      final controller = ProtectedWebController(
        canOpen: (uri) => uri == moon,
        onNavigation: (_) {},
      )..attach(76);
      final denied = controller.open(Uri.parse('https://unreviewed.invalid/'));
      await Future<void>.delayed(Duration.zero);
      await controller.resume(moon);
      stop.complete();
      await denied;
      expect(controller.status.url, moon);
      expect(controller.status.error, isNull);
      expect(controller.status.loading, isTrue);
      controller.dispose();
    },
  );

  test(
    'rebound views close their old owner and ignore stale renderer termination',
    () async {
      final controller = ProtectedWebController(
        canOpen: (uri) => uri == moon,
        onNavigation: (_) {},
      )..attach(77);
      await controller.open(moon);
      final oldRequest = (calls.last.arguments as Map)['requestId'];
      controller.attach(78);
      await controller.open(moon);
      final request = (calls.last.arguments as Map)['requestId'];
      await native('rendererGone', {'viewId': 77, 'requestId': oldRequest});
      await native('rendererGone', {'viewId': 78, 'requestId': oldRequest});
      expect(controller.status.error, isNull);
      await native('rendererGone', {'viewId': 78, 'requestId': request});
      expect(controller.status.error, isNotNull);
      controller.dispose();
      final closed = calls
          .where((c) => c.method == 'close')
          .map((c) => (c.arguments as Map)['viewId']);
      expect(closed, [77, 78]);
    },
  );

  test(
    'menu suspension preserves renderer request and resumes without reloading',
    () async {
      final controller = ProtectedWebController(
        canOpen: (_) => true,
        onNavigation: (_) {},
      )..attach(90);
      await controller.open(moon);
      final request = (calls.last.arguments as Map)['requestId'];
      await native('pageState', {
        'viewId': 90,
        'requestId': request,
        'url': moon.toString(),
        'title': 'Moon',
        'progress': 100,
        'isLoading': false,
        'canGoBack': true,
      });
      await controller.suspend();
      await controller.resume(moon);
      expect(calls.where((c) => c.method == 'open'), hasLength(1));
      expect(calls.where((c) => c.method == 'close'), isEmpty);
      await native('pageState', {
        'viewId': 90,
        'requestId': request,
        'url': moon.toString(),
        'title': 'Still here',
        'progress': 100,
        'canGoForward': true,
      });
      expect(controller.status.title, 'Still here');
      expect(controller.status.canGoForward, isTrue);
      await controller.forward();
      await controller.find('Moon');
      expect(calls.any((c) => c.method == 'forward'), isTrue);
      expect(calls.any((c) => c.method == 'find'), isTrue);
      controller.dispose();
    },
  );

  test(
    'blocked links preserve committed page and hidden new windows cannot open',
    () async {
      final windows = <Uri>[];
      final notices = <String>[];
      final controller = ProtectedWebController(
        canOpen: (_) => true,
        onNavigation: (_) {},
        onNewWindow: windows.add,
        onBlocked: notices.add,
      )..attach(91);
      await controller.open(moon);
      final request = (calls.last.arguments as Map)['requestId'];
      final event = {
        'viewId': 91,
        'requestId': request,
        'url': moon.toString(),
      };
      await native('pageState', {...event, 'title': 'Moon', 'progress': 100});
      await native('navigationBlocked', {
        ...event,
        'url': 'https://blocked.invalid/',
      });
      expect(controller.status.committed, isTrue);
      expect(controller.status.title, 'Moon');
      expect(notices, hasLength(1));
      await controller.suspend();
      await native('newWindowRequested', event);
      expect(windows, isEmpty);
      await controller.resume(moon);
      await native('newWindowRequested', event);
      expect(windows, [moon]);
      controller.dispose();
    },
  );

  test(
    'pagination search URLs retain provider fields instead of becoming first page',
    () async {
      final uri = const StrictSearchPolicy().rewriteProviderInput(
        'https://safe.duckduckgo.com/?q=moon&s=30&dc=31&kp=1&kac=-1',
      )!;
      final controller = ProtectedWebController(
        canOpen: (_) => true,
        onNavigation: (_) {},
      )..attach(92);
      await controller.open(uri);
      expect(calls.where((c) => c.method == 'openSearch'), isEmpty);
      final args =
          calls.singleWhere((c) => c.method == 'open').arguments as Map;
      expect(args['url'], uri.toString());
      expect(Uri.parse(args['url'] as String).queryParameters['s'], '30');
      controller.dispose();
    },
  );

  test(
    'URL-free find results preserve the page and allow the next load',
    () async {
      final controller = ProtectedWebController(
        canOpen: (_) => true,
        onNavigation: (_) {},
      )..attach(93);
      await controller.open(moon);
      final request = (calls.last.arguments as Map)['requestId'];
      await native('pageState', {
        'viewId': 93,
        'requestId': request,
        'url': moon.toString(),
        'title': 'Moon',
        'progress': 100,
        'canGoBack': true,
      });
      final committed = controller.status;
      await controller.find('Moon');
      await native('findResult', {
        'viewId': 93,
        'requestId': request,
        'activeMatchOrdinal': 0,
        'numberOfMatches': 3,
        'isDoneCounting': true,
      });
      expect(identical(controller.status, committed), isTrue);
      expect(
        calls.where(
          (c) =>
              c.method == 'setActive' &&
              (c.arguments as Map)['active'] == false,
        ),
        isEmpty,
      );
      final next = Uri.parse('https://www.nasa.gov/');
      await controller.open(next);
      expect(calls.where((c) => c.method == 'open'), hasLength(2));
      expect(controller.currentUrl, next);
      controller.dispose();
    },
  );

  test(
    'popup adoption preserves native request and token events are fenced',
    () async {
      final windows = <(Uri, String?)>[];
      var closed = 0;
      final controller = ProtectedWebController(
        canOpen: (uri) => uri == moon,
        onNavigation: (_) {},
        onNewWindowWithToken: (uri, token) => windows.add((uri, token)),
        onCloseRequested: () => closed++,
      )..attach(94);
      await controller.adoptWindow(moon, 'owned-token-123');
      final adopt =
          calls.singleWhere((c) => c.method == 'adoptWindow').arguments as Map;
      expect(adopt.keys.toSet(), {'viewId', 'requestId', 'windowToken'});
      expect(adopt['windowToken'], 'owned-token-123');
      expect(
        calls.where((c) => c.method == 'open' || c.method == 'openSearch'),
        isEmpty,
      );
      final event = <String, Object?>{
        'viewId': 94,
        'requestId': adopt['requestId'],
        'url': moon.toString(),
      };
      await native('newWindowRequested', {
        ...event,
        'windowToken': 'child-token',
      });
      await native(
        'newWindowRequested',
        event,
      ); // URL-only Android adapter stays supported.
      await native('newWindowRequested', {
        ...event,
        'windowToken': '../invalid',
      });
      await native('newWindowRequested', {
        ...event,
        'url': 'https://blocked.invalid/',
        'windowToken': 'child-token',
      });
      await controller.suspend();
      await native('newWindowRequested', {
        ...event,
        'windowToken': 'hidden-token',
      });
      expect(windows, [(moon, 'child-token'), (moon, null)]);
      await native('closeRequested', {...event, 'requestId': 0});
      expect(closed, 0);
      await native(
        'closeRequested',
        event,
      ); // Script child can close while its tab is hidden.
      expect(closed, 1);
      controller.dispose();
      await native('closeRequested', event);
      expect(closed, 1);
    },
  );

  test(
    'expired popup never becomes a GET when a covered tab resumes',
    () async {
      messenger.setMockMethodCallHandler(ProtectedWebBridge.channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'adoptWindow') {
          throw PlatformException(code: 'expired');
        }
        return null;
      });
      final controller = ProtectedWebController(
        canOpen: (_) => true,
        onNavigation: (_) {},
      )..attach(96);
      await controller.adoptWindow(moon, 'expired-token');
      await controller.suspend();
      await controller.resume(moon);
      expect(
        calls.where((c) => c.method == 'open' || c.method == 'openSearch'),
        isEmpty,
      );
      expect(controller.status.error, contains('expired'));
      await controller.open(
        moon,
      ); // An explicit address action may start a new request.
      expect(calls.where((c) => c.method == 'open'), hasLength(1));
      controller.dispose();
    },
  );

  test('revoked popup is closed without replaying its POST as GET', () async {
    final controller = ProtectedWebController(
      canOpen: (_) => false,
      onNavigation: (_) {},
    )..attach(95);
    await controller.adoptWindow(moon, 'owned-token');
    expect(calls.map((c) => c.method), ['close']);
    expect(controller.status.error, isNotNull);
    controller.dispose();
  });

  test('native capability requires the consumer engine contract', () async {
    messenger.setMockMethodCallHandler(
      ProtectedWebBridge.channel,
      (_) async => {
        'supported': true,
        'privateAvailable': true,
        'mode': 'unrestricted',
        'strictSearchAvailable': true,
      },
    );
    final unsupported = await ProtectedWebBridge.capabilities();
    expect(unsupported.supported, isFalse);
    expect(unsupported.strictSearchAvailable, isFalse);
    messenger.setMockMethodCallHandler(
      ProtectedWebBridge.channel,
      (_) async => {
        'supported': true,
        'privateAvailable': false,
        'mode': 'consumerWeb',
        'strictSearchAvailable': true,
      },
    );
    final result = await ProtectedWebBridge.capabilities();
    expect(result.supported, isTrue);
    expect(result.privateAvailable, isFalse);
    expect(result.strictSearchAvailable, isTrue);
  });

  test(
    'live tab trail preserves Home and offline history without persisting it',
    () {
      final tab = DiscoveryTab();
      tab.visit('moon-phases');
      tab.visitWebsite(moon);
      expect(tab.resourceId, isNull);
      expect(tab.website, moon);
      tab.visit(null);
      expect(tab.trail, [null, 'moon-phases', 'web:$moon', null]);
      tab.position--;
      expect(tab.website, moon);
      tab.position--;
      expect(tab.resourceId, 'moon-phases');
      tab.visitWebsite(moon.replace(fragment: 'surface'));
      expect(tab.trail.length, 3);
      expect(tab.website!.fragment, 'surface');
    },
  );
}
