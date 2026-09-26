import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/browser/protected_web_surface.dart';
import 'package:wingman_browser/config/product_edition.dart';
import 'package:wingman_browser/signature/handoff/handoff_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final platformCalls = <MethodCall>[];
  final page = Uri.parse('https://example.com/');
  Completer<void>? creation;

  setUp(() {
    calls.clear();
    platformCalls.clear();
    creation = null;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      platformCalls.add(call);
      if (call.method == 'create') await creation?.future;
      return null;
    });
    messenger.setMockMethodCallHandler(ProtectedWebBridge.channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    messenger.setMockMethodCallHandler(ProtectedWebBridge.channel, null);
  });

  void macTestWidgets(String name, WidgetTesterCallback callback) {
    testWidgets(
      name,
      callback,
      variant: const TargetPlatformVariant({TargetPlatform.macOS}),
    );
  }

  for (final private in [false, true]) {
    macTestWidgets(
      'macOS $private session uses protected AppKit view contract',
      (tester) async {
        final policyChanges = ChangeNotifier();
        addTearDown(policyChanges.dispose);
        ProtectedWebController? controller;
        final seen = <Uri>[];
        await tester.pumpWidget(
          MaterialApp(
            home: ProtectedWebSurface(
              tabId: private ? 'private-owner' : 'normal-owner',
              url: page,
              isPrivate: private,
              restrictions: const {
                'blockedResourceIds': ['extra-site'],
              },
              canOpen: (uri) => uri == page,
              policyChanges: policyChanges,
              onNavigation: seen.add,
              onStatus: (_) {},
              onController: (value) => controller = value,
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(AppKitView), findsOneWidget);
        expect(find.byType(UiKitView), findsNothing);
        expect(find.byType(AndroidView), findsNothing);
        final create = platformCalls.singleWhere((c) => c.method == 'create');
        final args = create.arguments as Map;
        expect(args['viewType'], 'wingman/protected-web');
        final params =
            const StandardMessageCodec().decodeMessage(
                  ByteData.sublistView(args['params'] as Uint8List),
                )
                as Map;
        expect(params['tabId'], private ? 'private-owner' : 'normal-owner');
        expect(params['private'], private);
        expect(params['edition'], productEdition.name);
        expect(params['blockedResourceIds'], ['extra-site']);
        final open = calls.singleWhere((c) => c.method == 'open');
        final opened = open.arguments as Map;
        expect(opened['viewId'], args['id']);
        expect(opened['url'], page.toString());
        expect(controller?.attached, isTrue);
        expect(seen, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(calls.where((c) => c.method == 'close'), hasLength(1));
        expect(controller?.attached, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  macTestWidgets('macOS never allocates a view for a denied initial address', (
    tester,
  ) async {
    final policyChanges = ChangeNotifier();
    addTearDown(policyChanges.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ProtectedWebSurface(
          tabId: 'denied',
          url: page,
          isPrivate: false,
          canOpen: (_) => false,
          policyChanges: policyChanges,
          onNavigation: (_) => fail('No navigation should be requested.'),
          onStatus: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AppKitView), findsNothing);
    expect(platformCalls.where((c) => c.method == 'create'), isEmpty);
    expect(calls.where((c) => c.method == 'open'), isEmpty);
  });

  macTestWidgets('macOS rechecks policy after delayed native view creation', (
    tester,
  ) async {
    var allowed = true;
    creation = Completer<void>();
    final policyChanges = ChangeNotifier();
    addTearDown(policyChanges.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ProtectedWebSurface(
          tabId: 'revoked',
          url: page,
          isPrivate: true,
          canOpen: (_) => allowed,
          policyChanges: policyChanges,
          onNavigation: (_) {},
          onStatus: (_) {},
        ),
      ),
    );
    expect(platformCalls.where((c) => c.method == 'create'), hasLength(1));
    allowed = false;
    policyChanges.notifyListeners();
    creation!.complete();
    await tester.pump();
    await tester.pump();
    expect(calls.where((c) => c.method == 'open'), isEmpty);
    expect(calls.where((c) => c.method == 'openSearch'), isEmpty);
    expect(find.byType(AppKitView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Windows stays unsupported and cannot allocate Apple views',
    (tester) async {
      final policyChanges = ChangeNotifier();
      addTearDown(policyChanges.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ProtectedWebSurface(
            tabId: 'unsupported',
            url: page,
            isPrivate: false,
            canOpen: (_) => true,
            policyChanges: policyChanges,
            onNavigation: (_) {},
            onStatus: (_) {},
          ),
        ),
      );
      expect(
        find.textContaining('Protected native browsing is unavailable'),
        findsOneWidget,
      );
      expect(platformCalls, isEmpty);
      expect(calls, isEmpty);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  test('macOS does not claim the secure owner-return handoff gate', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(PlatformHandoffStore().supported, isFalse);
  });

  test('macOS WK capability reports request totals as unobservable', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    messenger.setMockMethodCallHandler(
      ProtectedWebBridge.channel,
      (_) async => {
        'supported': true,
        'mode': 'consumerWeb',
        'privateAvailable': true,
        'strictSearchAvailable': true,
        'resourceCountersObservable': false,
        'defaultBrowserAvailable': false,
      },
    );
    final capabilities = await ProtectedWebBridge.capabilities();
    expect(capabilities.supported, isTrue);
    expect(capabilities.privateAvailable, isTrue);
    expect(capabilities.strictSearchAvailable, isTrue);
    expect(capabilities.resourceCountersObservable, isFalse);
    expect(capabilities.defaultBrowser, isFalse);
    expect(const ProtectedWebStatus().blockedResources, isNull);
  });
}
