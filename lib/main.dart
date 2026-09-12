import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'browser/browser_engine.dart';
import 'browser/protected_web_surface.dart';
import 'config/product_edition.dart';
import 'data/sqlite_browser_repository.dart';
import 'policy/policy_runtime.dart';
import 'policy/consumer_protection_repository.dart';
import 'state/browser_state.dart';
import 'presentation/app_route_observer.dart';
import 'presentation/browser_shell.dart';
import 'presentation/theme.dart';
import 'presentation/components/wingman_components.dart';
import 'presentation/home/welcome_screen.dart';
import 'signature/handoff/handoff_gate.dart';
import 'signature/privacy/privacy_journal.dart';
import 'signature/signature_services.dart';
import 'signature/launchpad/launchpad.dart';
import 'signature/workspaces/discovery_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StartupSurface());
  try {
    // This secure marker is read before constructing or loading owner state.
    final journal = PrivacyJournal(sessionKind: PrivacySessionKind.handoff);
    final handoff = HandoffController(
      onStarted: () {
        journal.clear();
        journal.record(
          PrivacyActivity.handoffStarted,
          PrivacyOutcome.completed,
        );
      },
      onEnded: () => journal.record(
        PrivacyActivity.handoffEnded,
        PrivacyOutcome.completed,
      ),
    );
    await handoff.initialize();
    await NativeBrowserService().quarantineLegacyContent();
    // Restore and, when configured, refresh the independent signed browsing
    // baseline before any owner renderer is allocated. An update outage keeps
    // the last usable local generation; it never grants unfiltered access.
    final updates = ConsumerProtectionRepository(
      source: _consumerUpdateSource(),
    );
    await updates.init();
    await updates.checkForUpdates();
    final policy = await PolicyRuntime.initialize(
      consumerProtection: updates.policy,
    );
    policy.configureConsumerUpdateAvailability(
      configured:
          updates.status.sourceConfigured && updates.status.trustConfigured,
    );
    handoff.attachPolicy(policy);
    LiveBrowsingPolicy reviewed;
    try {
      reviewed = await LiveBrowsingPolicy.load();
    } catch (_) {
      reviewed = const LiveBrowsingPolicy.unavailable('curation-unavailable');
    }
    // Consumer renderer authority is independent of optional Home curation.
    final capabilities = await ProtectedWebBridge.capabilities();
    policy.configureLiveBrowsing(
      reviewed,
      nativeAvailable: capabilities.supported,
      privateAvailable: capabilities.privateAvailable,
      strictSearchAvailable: capabilities.strictSearchAvailable,
    );
    runApp(
      SignatureApplicationRoot(
        policy: policy,
        handoff: handoff,
        handoffJournal: journal,
        updates: updates,
      ),
    );
  } catch (_) {
    runApp(const StartupSurface(failed: true));
  }
}

ConsumerUpdateSource? _consumerUpdateSource() {
  const endpoint = String.fromEnvironment('WINGMAN_CONSUMER_UPDATE_URL');
  if (kIsWeb || endpoint.isEmpty) return null;
  try {
    return HttpsConsumerUpdateSource(manifestUri: Uri.parse(endpoint));
  } on ArgumentError {
    return null;
  } on FormatException {
    return null;
  }
}

/// Controllers live above the gate. Guest UI replaces the entire owner tree,
/// while these owner objects remain inaccessible and intact for authenticated return.
class SignatureApplicationRoot extends StatefulWidget {
  const SignatureApplicationRoot({
    super.key,
    required this.policy,
    required this.handoff,
    required this.handoffJournal,
    this.updates,
  });
  final PolicyRuntime policy;
  final HandoffController handoff;
  final PrivacyJournal handoffJournal;
  final ConsumerProtectionRepository? updates;
  @override
  State<SignatureApplicationRoot> createState() =>
      _SignatureApplicationRootState();
}

class _SignatureApplicationRootState extends State<SignatureApplicationRoot> {
  Future<_OwnerContext>? _owner;
  Future<_OwnerContext> _loadOwner() async {
    final repository = SqliteBrowserRepository();
    final state = BrowserState(
      repository: repository,
      policyRuntime: widget.policy,
    );
    await state.init();
    final signatures = SignatureServices(
      store: repository,
      launchpadEligibility: LaunchpadEligibilityService(
        resourceEligible: (id) => widget.policy.policy
            .evaluate(
              PolicyRequest.bundled(
                id,
                context: productEdition == ProductEdition.consumer
                    ? ContentContext.general
                    : ContentContext.student,
              ),
              additional: state.protectedPreferences.additional,
            )
            .isAllowed,
        resourceLookup: widget.policy.resource,
        websiteAvailable: () => widget.policy.liveAvailable(),
        evaluateWebsite: (uri) => widget.policy.policy.evaluate(
          PolicyRequest.navigation(
            uri,
            context: productEdition == ProductEdition.consumer
                ? ContentContext.general
                : ContentContext.student,
          ),
          additional: state.protectedPreferences.additional,
        ),
      ),
      eligible: (id) => widget.policy.policy
          .evaluate(
            PolicyRequest.bundled(
              id,
              context: productEdition == ProductEdition.consumer
                  ? ContentContext.general
                  : ContentContext.student,
            ),
            additional: state.protectedPreferences.additional,
          )
          .isAllowed,
    );
    // Optional tools don't hold the ordinary Home startup gate.
    unawaited(signatures.initialize());
    final session = DiscoverySession();
    if (productEdition == ProductEdition.consumer) {
      await session.restore(
        repository,
        permitted: (uri) => widget.policy.policy
            .evaluate(
              PolicyRequest.navigation(uri),
              additional: state.protectedPreferences.additional,
            )
            .isAllowed,
        resourceEligible: (id) => widget.policy.policy
            .evaluate(
              PolicyRequest.bundled(id),
              additional: state.protectedPreferences.additional,
            )
            .isAllowed,
      );
    }
    return _OwnerContext(state, signatures, session);
  }

  @override
  Widget build(BuildContext context) => HandoffGate(
    controller: widget.handoff,
    ownerBuilder: (_) => FutureBuilder<_OwnerContext>(
      future: _owner ??= _loadOwner(),
      builder: (context, result) {
        if (result.hasError) return const StartupSurface(failed: true);
        final owner = result.data;
        if (owner == null) return const StartupSurface();
        return WingmanApp(
          state: owner.state,
          policy: widget.policy,
          signatures: owner.signatures,
          session: owner.session,
          handoff: widget.handoff,
        );
      },
    ),
  );
  @override
  void dispose() {
    final owner = _owner;
    if (owner != null) {
      unawaited(owner.then((value) => value.close()).catchError((Object _) {}));
    }
    widget.handoff.dispose();
    widget.handoffJournal.dispose();
    widget.policy.dispose();
    unawaited(widget.updates?.close());
    super.dispose();
  }
}

class _OwnerContext {
  _OwnerContext(this.state, this.signatures, this.session);
  final BrowserState state;
  final SignatureServices signatures;
  final DiscoverySession session;
  Future<void> close() async {
    await signatures.flush();
    await session.flush();
    session.dispose();
    signatures.dispose();
    state.dispose();
  }
}

class StartupSurface extends StatelessWidget {
  const StartupSurface({super.key, this.failed = false});
  final bool failed;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: WingmanTheme.make(Brightness.light),
    darkTheme: WingmanTheme.make(Brightness.dark),
    themeMode: ThemeMode.system,
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: failed
                ? const Text(
                    'Protected startup could not finish.\n\nClose and reopen Wingman to try again. Your existing saved data has not been opened.',
                  )
                : const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      WingmanBrand(),
                      SizedBox(height: 24),
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Opening your protected session…'),
                    ],
                  ),
          ),
        ),
      ),
    ),
  );
}

class WingmanApp extends StatelessWidget {
  const WingmanApp({
    super.key,
    required this.state,
    required this.policy,
    this.signatures,
    this.session,
    this.handoff,
  });
  final BrowserState state;
  final PolicyRuntime policy;
  final SignatureServices? signatures;
  final DiscoverySession? session;
  final HandoffController? handoff;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => MaterialApp(
      title: 'Wingman Browser',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [appRouteObserver],
      theme: WingmanTheme.make(Brightness.light),
      darkTheme: WingmanTheme.make(Brightness.dark),
      themeMode: state.settings.themeMode,
      themeAnimationDuration: Duration.zero,
      home: !state.settings.onboardingComplete
          ? WelcomeScreen(
              onComplete: () =>
                  state.saveSettingsPatch(onboardingComplete: true),
            )
          : BrowserShell(
              state: state,
              policy: policy,
              signatures: signatures,
              session: session,
              handoff: handoff,
            ),
    ),
  );
}
