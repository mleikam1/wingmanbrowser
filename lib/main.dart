import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'guard/guard_runtime.dart';
import 'guard_pin/guard_pin_service.dart';
import 'guard_ui/guard_controller.dart';
import 'monetization/ad_route_observer.dart';
import 'state/browser_state.dart';
import 'presentation/browser_shell.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = BrowserState();
  await state.init();
  final guard = GuardController(
    state: state,
    runtime: await GuardRuntime.initialize(),
    pin: GuardPinService(),
  );
  await guard.initialize();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['EasyPrivacy tracking starter data'],
      '${await rootBundle.loadString('assets/guard_tracking/ATTRIBUTION.md')}\n\n${await rootBundle.loadString('assets/guard_tracking/CC-BY-SA-3.0.txt')}',
    );
  });
  runApp(WingmanApp(state: state, guard: guard));
}

class WingmanApp extends StatelessWidget {
  const WingmanApp({super.key, required this.state, this.guard});
  final BrowserState state;
  final GuardController? guard;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => MaterialApp(
      title: 'Wingman Browser',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [adRouteObserver],
      theme: WingmanTheme.make(Brightness.light),
      darkTheme: WingmanTheme.make(Brightness.dark),
      themeMode: state.settings.themeMode,
      home: state.settings.onboardingComplete
          ? BrowserShell(state: state, guard: guard)
          : OnboardingScreen(
              onContinue: () => state.saveSettings(
                state.settings.copyWith(onboardingComplete: true),
              ),
              onSetUpGuard: guard == null
                  ? null
                  : () {
                      guard!.requestSetup = true;
                      state.saveSettings(
                        state.settings.copyWith(onboardingComplete: true),
                      );
                    },
            ),
    ),
  );
}
