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

  test('native capability requires the expected restricted mode', () async {
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
        'mode': 'reviewedScriptlessWeb',
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
