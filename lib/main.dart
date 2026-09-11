import 'package:flutter/material.dart';
import 'browser/browser_engine.dart';
import 'policy/policy_runtime.dart';
import 'state/browser_state.dart';
import 'presentation/app_route_observer.dart';
import 'presentation/browser_shell.dart';
import 'presentation/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Nothing from a previous session is rendered before these gates finish.
  try {
    final policy = await PolicyRuntime.initialize();
    await NativeBrowserService().quarantineLegacyContent();
    final state = BrowserState(policyRuntime: policy);
    await state.init();
    runApp(WingmanApp(state: state, policy: policy));
  } catch (_) {
    // Details can contain old addresses, SQL or platform data.
    runApp(
      MaterialApp(
        theme: WingmanTheme.make(Brightness.light),
        home: const Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Protected startup could not finish.\n\nClose and reopen Wingman to try again. Your existing saved data has not been opened.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WingmanApp extends StatelessWidget {
  const WingmanApp({super.key, required this.state, required this.policy});
  final BrowserState state;
  final PolicyRuntime policy;
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
      home: BrowserShell(state: state, policy: policy),
    ),
  );
}
