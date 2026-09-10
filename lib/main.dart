import 'package:flutter/material.dart';
import 'state/browser_state.dart';
import 'presentation/browser_shell.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = BrowserState();
  await state.init();
  runApp(WingmanApp(state: state));
}

class WingmanApp extends StatelessWidget {
  const WingmanApp({super.key, required this.state});
  final BrowserState state;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => MaterialApp(
      title: 'Wingman Browser',
      debugShowCheckedModeBanner: false,
      theme: WingmanTheme.make(Brightness.light),
      darkTheme: WingmanTheme.make(Brightness.dark),
      themeMode: state.settings.themeMode,
      home: state.settings.onboardingComplete
          ? BrowserShell(state: state)
          : OnboardingScreen(
              onContinue: () => state.saveSettings(
                state.settings.copyWith(onboardingComplete: true),
              ),
            ),
    ),
  );
}
