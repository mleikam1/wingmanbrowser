import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:wingman_browser/config/ad_configuration.dart';
import 'package:wingman_browser/monetization/ad_consent.dart';
import 'package:wingman_browser/monetization/ad_policy_service.dart';
import 'package:wingman_browser/monetization/ad_provider.dart';
import 'package:wingman_browser/monetization/ad_route_observer.dart';
import 'package:wingman_browser/monetization/home_ad_slot.dart';

const _configuration = AdConfiguration(
  platform: AdPlatform.android,
  isDebug: true,
  testAdsEnabled: true,
);
final _quietEligibility = ChangeNotifier();

AdEligibilityContext _context({
  AdHostSurface surface = AdHostSurface.home,
  bool current = true,
  bool foreground = true,
  AdProtectionRequirements requirements = AdProtectionRequirements.standard,
}) => AdEligibilityContext(
  currentSurface: surface,
  isCurrentRoute: current,
  isForeground: foreground,
  protectionRequirements: requirements,
);

class _Prompt implements ConsentPrompt {
  _Prompt(this.calls);
  final List<String> calls;
  bool shown = false;
  bool disposed = false;
  @override
  Future<void> show() async {
    shown = true;
    calls.add('formShow');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    calls.add('formDispose');
  }
}

class _Consent implements ConsentGateway {
  _Consent(this.calls) : prompt = _Prompt(calls);
  final List<String> calls;
  final _Prompt prompt;
  bool permitted = true;
  bool failUpdate = false;
  Completer<void>? updateDelay;
  Completer<ConsentPrompt?>? formDelay;
  Completer<void>? permissionDelay;
  Completer<void>? optionsDelay;
  @override
  Future<void> update() async {
    calls.add('consentUpdate');
    await updateDelay?.future;
    if (failUpdate) throw StateError('private SDK error must not be logged');
  }

  @override
  Future<ConsentPrompt?> loadRequiredForm() async {
    calls.add('formLoad');
    return formDelay == null ? prompt : formDelay!.future;
  }

  @override
  Future<bool> canRequestAds() async {
    calls.add('consentPermission');
    await permissionDelay?.future;
    return permitted;
  }

  @override
  Future<bool> privacyOptionsRequired() async => true;
  @override
  Future<void> showPrivacyOptions() async {
    calls.add('privacyOptions');
    await optionsDelay?.future;
  }
}

class _Provider implements AdProviderGateway {
  _Provider(this.calls);
  final List<String> calls;
  final List<_Banner> banners = [];
  Completer<void>? initializationDelay;
  Completer<AdSize?>? sizeDelay;
  bool Function()? initializationLifetime;
  @override
  Future<bool> initialize({required bool Function() canContinue}) async {
    calls.add('initialize');
    initializationLifetime = canContinue;
    await initializationDelay?.future;
    return canContinue();
  }

  @override
  Future<AdSize?> bannerSize(int availableWidth) async {
    calls.add('size');
    return sizeDelay == null ? AdSize.banner : sizeDelay!.future;
  }

  @override
  AdBannerHandle createBanner({
    required String adUnitId,
    required AdSize size,
    required void Function(AdBannerHandle) onLoaded,
    required void Function(AdBannerHandle) onFailed,
  }) {
    expect(adUnitId, 'ca-app-pub-3940256099942544/6300978111');
    calls.add('create');
    final banner = _Banner(calls, size, onLoaded, onFailed);
    banners.add(banner);
    return banner;
  }
}

class _Banner implements AdBannerHandle {
  _Banner(this.calls, this.size, this.onLoaded, this.onFailed);
  final List<String> calls;
  @override
  final AdSize size;
  final void Function(AdBannerHandle) onLoaded;
  final void Function(AdBannerHandle) onFailed;
  bool disposed = false;
  @override
  Widget get widget => const Text('Fake approved test banner');
  @override
  Future<void> load() async => calls.add('load');
  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    calls.add('dispose');
  }
}

Widget _harness(
  _Consent consent,
  _Provider provider, {
  AdEligibilityContext? context,
  bool isPrivate = false,
  List<AdDemoStatus>? events,
  Listenable? changes,
  AdEligibilityContext Function()? readEligibility,
  bool Function()? readIsPrivate,
}) => MaterialApp(
  navigatorObservers: [adRouteObserver],
  home: Scaffold(
    body: SingleChildScrollView(
      child: HomeAdSlot.forTesting(
        key: const ValueKey('retained-home-slot'),
        isPrivate: isPrivate,
        eligibility: context ?? _context(),
        eligibilityChanges: changes ?? _quietEligibility,
        readEligibility: readEligibility ?? () => context ?? _context(),
        readIsPrivate: readIsPrivate ?? () => isPrivate,
        configuration: _configuration,
        consentGateway: consent,
        provider: provider,
        onStatusChanged: events?.add,
      ),
    ),
  ),
);

Future<void> _start(WidgetTester tester) async {
  await tester.tap(find.text('Load test advertisement'));
  await tester.pump();
}

void main() {
  testWidgets('missing live state fails closed despite eligible props', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [adRouteObserver],
        home: HomeAdSlot.forTesting(
          isPrivate: false,
          eligibility: _context(),
          configuration: _configuration,
          consentGateway: _Consent(calls),
          provider: _Provider(calls),
        ),
      ),
    );
    expect(find.text('Load test advertisement'), findsNothing);
    expect(calls, isEmpty);
  });

  for (final privateTransition in [false, true]) {
    for (final phase in ['update', 'permission', 'initialize', 'size']) {
      testWidgets(
        'same-route ${privateTransition ? 'private' : 'Guard'} transition cancels $phase before a frame',
        (tester) async {
          final calls = <String>[];
          final changes = ChangeNotifier();
          final delay = Completer<void>();
          final size = Completer<AdSize?>();
          final consent = _Consent(calls);
          final provider = _Provider(calls);
          switch (phase) {
            case 'update':
              consent.updateDelay = delay;
            case 'permission':
              consent.permissionDelay = delay;
            case 'initialize':
              provider.initializationDelay = delay;
            case 'size':
              provider.sizeDelay = size;
          }
          var private = false;
          var eligibility = _context();
          await tester.pumpWidget(
            _harness(
              consent,
              provider,
              changes: changes,
              readEligibility: () => eligibility,
              readIsPrivate: () => private,
            ),
          );
          await _start(tester);
          final before = List<String>.of(calls);
          if (privateTransition) {
            private = true;
          } else {
            eligibility = _context(
              requirements: AdProtectionRequirements.strict,
            );
          }
          changes.notifyListeners();
          expect(provider.initializationLifetime?.call() ?? false, isFalse);
          // Return before even one frame: the abandoned attempt must stay dead.
          private = false;
          eligibility = _context();
          changes.notifyListeners();
          if (phase == 'size') {
            size.complete(AdSize.banner);
          } else {
            delay.complete();
          }
          await tester.pump();
          expect(calls, before);
          expect(provider.banners, isEmpty);
          expect(find.text('Load test advertisement'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
          changes.dispose();
        },
      );
    }
  }

  testWidgets('live private read denies a stale button before notification', (
    tester,
  ) async {
    final calls = <String>[];
    var private = false;
    await tester.pumpWidget(
      _harness(_Consent(calls), _Provider(calls), readIsPrivate: () => private),
    );
    private = true;
    await tester.tap(find.text('Load test advertisement'));
    expect(calls, isEmpty);
  });

  testWidgets(
    'source replacement detaches old listener and disposes loaded banner synchronously',
    (tester) async {
      final calls = <String>[];
      final consent = _Consent(calls);
      final provider = _Provider(calls);
      final first = ChangeNotifier();
      final second = ChangeNotifier();
      await tester.pumpWidget(_harness(consent, provider, changes: first));
      await tester.pumpWidget(_harness(consent, provider, changes: second));
      await _start(tester);
      final banner = provider.banners.single;
      banner.onLoaded(banner);
      await tester.pump();
      first.notifyListeners();
      expect(banner.disposed, isFalse);
      second.notifyListeners();
      expect(banner.disposed, isTrue);
      await tester.pumpWidget(const SizedBox());
      second.notifyListeners();
      expect(tester.takeException(), isNull);
      first.dispose();
      second.dispose();
    },
  );

  testWidgets('ineligible contexts never start consent or provider work', (
    tester,
  ) async {
    for (final context in [
      const AdEligibilityContext(),
      _context(requirements: AdProtectionRequirements.unknown),
      _context(requirements: AdProtectionRequirements.strict),
      _context(current: false),
      _context(foreground: false),
      for (final surface in [
        AdHostSurface.browserPage,
        AdHostSurface.guardBlock,
        AdHostSurface.securityWarning,
        AdHostSurface.helpNow,
        AdHostSurface.support,
        AdHostSurface.settings,
      ])
        _context(surface: surface),
    ]) {
      final calls = <String>[];
      await tester.pumpWidget(
        _harness(_Consent(calls), _Provider(calls), context: context),
      );
      expect(find.text('Load test advertisement'), findsNothing);
      expect(tester.getSize(find.byType(HomeAdSlot)).height, 0);
      expect(calls, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    final calls = <String>[];
    await tester.pumpWidget(
      _harness(_Consent(calls), _Provider(calls), isPrivate: true),
    );
    expect(calls, isEmpty);
    expect(find.text('Load test advertisement'), findsNothing);
  });

  testWidgets('missing route-observer registration withholds the demo', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: HomeAdSlot.forTesting(
          isPrivate: false,
          eligibility: _context(),
          eligibilityChanges: _quietEligibility,
          readEligibility: _context,
          readIsPrivate: () => false,
          configuration: _configuration,
          consentGateway: _Consent(calls),
          provider: _Provider(calls),
        ),
      ),
    );
    expect(find.text('Load test advertisement'), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets(
    'explicit consent precedes the provider and only loaded ads show',
    (tester) async {
      final calls = <String>[];
      final provider = _Provider(calls);
      await tester.pumpWidget(_harness(_Consent(calls), provider));
      expect(calls, isEmpty);
      await _start(tester);
      expect(calls, [
        'consentUpdate',
        'formLoad',
        'formShow',
        'formDispose',
        'consentPermission',
        'initialize',
        'size',
        'create',
        'load',
      ]);
      expect(find.text('Fake approved test banner'), findsNothing);
      provider.banners.single.onLoaded(provider.banners.single);
      await tester.pump();
      expect(find.text('Fake approved test banner'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(provider.banners.single.disposed, isTrue);
    },
  );

  for (final fails in [false, true]) {
    testWidgets('consent ${fails ? 'failure' : 'refusal'} starts no SDK', (
      tester,
    ) async {
      final calls = <String>[];
      final consent = _Consent(calls)
        ..permitted = false
        ..failUpdate = fails;
      await tester.pumpWidget(_harness(consent, _Provider(calls)));
      await _start(tester);
      expect(calls, isNot(contains('initialize')));
      expect(calls, isNot(contains('create')));
      expect(find.text('Fake approved test banner'), findsNothing);
    });
  }

  for (final stage in ['update', 'form', 'permission']) {
    testWidgets('a delayed consent $stage cannot revive after a route return', (
      tester,
    ) async {
      final calls = <String>[];
      final consent = _Consent(calls);
      final provider = _Provider(calls);
      final events = <AdDemoStatus>[];
      final delay = Completer<void>();
      final form = Completer<ConsentPrompt?>();
      if (stage == 'update') consent.updateDelay = delay;
      if (stage == 'form') consent.formDelay = form;
      if (stage == 'permission') consent.permissionDelay = delay;
      await tester.pumpWidget(_harness(consent, provider, events: events));
      await _start(tester);
      await tester.pumpWidget(
        _harness(
          consent,
          provider,
          context: _context(current: false),
          events: events,
        ),
      );
      await tester.pumpWidget(_harness(consent, provider, events: events));
      if (stage == 'form') {
        form.complete(consent.prompt);
      } else {
        delay.complete();
      }
      await tester.pump();
      expect(calls, isNot(contains('initialize')));
      expect(events, [AdDemoStatus.consentStarted]);
      if (stage == 'form') {
        expect(consent.prompt.shown, isFalse);
        expect(consent.prompt.disposed, isTrue);
      }
      expect(find.text('Load test advertisement'), findsOneWidget);
      expect(find.text('Fake approved test banner'), findsNothing);
    });
  }

  testWidgets('a stricter choice during SDK init prevents sizing and request', (
    tester,
  ) async {
    final calls = <String>[];
    final consent = _Consent(calls);
    final delayed = Completer<void>();
    final provider = _Provider(calls)..initializationDelay = delayed;
    await tester.pumpWidget(_harness(consent, provider));
    await _start(tester);
    expect(calls.last, 'initialize');
    await tester.pumpWidget(
      _harness(
        consent,
        provider,
        context: _context(requirements: AdProtectionRequirements.strict),
      ),
    );
    await tester.pumpWidget(_harness(consent, provider));
    expect(provider.initializationLifetime!(), isFalse);
    delayed.complete();
    await tester.pump();
    expect(calls, isNot(contains('size')));
    expect(calls, isNot(contains('create')));
  });

  testWidgets('foreground loss during sizing prevents banner creation', (
    tester,
  ) async {
    final calls = <String>[];
    final consent = _Consent(calls);
    final delayed = Completer<AdSize?>();
    final provider = _Provider(calls)..sizeDelay = delayed;
    await tester.pumpWidget(_harness(consent, provider));
    await _start(tester);
    expect(calls.last, 'size');
    await tester.pumpWidget(
      _harness(consent, provider, context: _context(foreground: false)),
    );
    delayed.complete(AdSize.banner);
    await tester.pump();
    expect(calls, isNot(contains('create')));
    expect(find.text('Fake approved test banner'), findsNothing);
  });

  testWidgets('late banner callbacks cannot display or remove a newer ad', (
    tester,
  ) async {
    final calls = <String>[];
    final consent = _Consent(calls);
    final provider = _Provider(calls);
    final events = <AdDemoStatus>[];
    await tester.pumpWidget(_harness(consent, provider, events: events));
    await _start(tester);
    final old = provider.banners.single;
    await tester.pumpWidget(
      _harness(
        consent,
        provider,
        context: _context(surface: AdHostSurface.settings),
        events: events,
      ),
    );
    expect(old.disposed, isTrue);
    await tester.pumpWidget(_harness(consent, provider, events: events));
    old.onLoaded(old);
    await tester.pump();
    expect(find.text('Fake approved test banner'), findsNothing);
    expect(events, isNot(contains(AdDemoStatus.bannerLoaded)));
    await _start(tester);
    final fresh = provider.banners.last;
    fresh.onLoaded(fresh);
    await tester.pump();
    old.onFailed(old);
    await tester.pump();
    expect(find.text('Fake approved test banner'), findsOneWidget);
    expect(fresh.disposed, isFalse);
    expect(events.where((e) => e == AdDemoStatus.bannerLoaded).length, 1);
  });

  testWidgets(
    'loaded inventory disappears on strict Guard and never auto reloads',
    (tester) async {
      final calls = <String>[];
      final consent = _Consent(calls);
      final provider = _Provider(calls);
      await tester.pumpWidget(_harness(consent, provider));
      await _start(tester);
      final banner = provider.banners.single;
      banner.onLoaded(banner);
      await tester.pump();
      await tester.pumpWidget(
        _harness(
          consent,
          provider,
          context: _context(requirements: AdProtectionRequirements.strict),
        ),
      );
      expect(banner.disposed, isTrue);
      expect(find.text('Fake approved test banner'), findsNothing);
      expect(tester.getSize(find.byType(HomeAdSlot)).height, 0);
      await tester.pumpWidget(_harness(consent, provider));
      expect(calls.where((e) => e == 'consentUpdate').length, 1);
      expect(find.text('Load test advertisement'), findsOneWidget);
    },
  );

  testWidgets(
    'actual lifecycle invalidates even before shell context changes',
    (tester) async {
      final calls = <String>[];
      final consent = _Consent(calls)..updateDelay = Completer<void>();
      final provider = _Provider(calls);
      await tester.pumpWidget(_harness(consent, provider));
      await _start(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      consent.updateDelay!.complete();
      await tester.pump();
      expect(calls, ['consentUpdate']);
      expect(find.text('Load test advertisement'), findsOneWidget);
    },
  );

  testWidgets(
    'privacy options dispose inventory and cannot update a new route',
    (tester) async {
      final calls = <String>[];
      final consent = _Consent(calls)..optionsDelay = Completer<void>();
      final provider = _Provider(calls);
      await tester.pumpWidget(_harness(consent, provider));
      await _start(tester);
      final banner = provider.banners.single;
      banner.onLoaded(banner);
      await tester.pump();
      await tester.tap(find.text('Advertising privacy choices'));
      await tester.pump();
      expect(banner.disposed, isTrue);
      expect(calls.last, 'privacyOptions');
      await tester.pumpWidget(
        _harness(consent, provider, context: _context(current: false)),
      );
      await tester.pumpWidget(_harness(consent, provider));
      consent.optionsDelay!.complete();
      await tester.pump();
      expect(calls.where((e) => e == 'consentPermission').length, 1);
      expect(
        find.text('Your advertising privacy choices have been updated.'),
        findsNothing,
      );
      expect(find.text('Fake approved test banner'), findsNothing);
    },
  );
  testWidgets('actual route push cancels consent before a rebuild', (
    tester,
  ) async {
    final calls = <String>[];
    final consent = _Consent(calls)..formDelay = Completer<ConsentPrompt?>();
    final provider = _Provider(calls);
    await tester.pumpWidget(_harness(consent, provider));
    await _start(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final route = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Sensitive settings')),
    );
    unawaited(navigator.push(route));
    // No tester.pump: the widget's old eligibility still says Home/foreground.
    consent.formDelay!.complete(consent.prompt);
    await tester.pump();
    expect(consent.prompt.shown, isFalse);
    expect(consent.prompt.disposed, isTrue);
    expect(calls, isNot(contains('initialize')));
    await tester.pumpAndSettle();
    expect(find.text('Sensitive settings'), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Load test advertisement'), findsOneWidget);
    expect(calls.where((e) => e == 'consentUpdate').length, 1);
  });

  testWidgets('push and remove before a frame never revives old consent', (
    tester,
  ) async {
    final calls = <String>[];
    final consent = _Consent(calls)..updateDelay = Completer<void>();
    final provider = _Provider(calls);
    await tester.pumpWidget(_harness(consent, provider));
    await _start(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final route = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Transient settings')),
    );
    unawaited(navigator.push(route));
    navigator.pop();
    consent.updateDelay!.complete();
    await tester.pumpAndSettle();
    expect(calls, ['consentUpdate']);
    expect(find.text('Load test advertisement'), findsOneWidget);
  });
}
