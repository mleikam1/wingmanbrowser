import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wingman_browser/browser/browser_engine.dart';

// Opt-in external HTTPS fixture. These public synthetic values are not an
// account or a user's credentials; no OS trust or password vault is modified.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'synthetic HTTPS HTTP authentication remains isolated from private views',
    (tester) async {
      const address =
          'https://httpbin.org/basic-auth/wingman-fixture/test-only';
      var active = 'normal';
      var permitPrivate = false;
      final challenges = <String, int>{};
      final messages = <String>[];
      final engine = BrowserEnginePool(
        confirm: (_, _) async => false,
        prompt: (title, _, _) async {
          if (title == 'Website sign-in') {
            challenges[active] = (challenges[active] ?? 0) + 1;
            if (active != 'normal' && !permitPrivate) return null;
            return 'wingman-fixture';
          }
          if (title == 'Website password') return 'test-only';
          return null;
        },
        onPageChanged: (_, _, _, _) {},
        onMessage: messages.add,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: engine,
              builder: (_, _) {
                final ids = engine.liveTabIds;
                return ids.isEmpty
                    ? const SizedBox()
                    : IndexedStack(
                        index: ids.contains(active) ? ids.indexOf(active) : 0,
                        children: [for (final id in ids) engine.view(id)!],
                      );
              },
            ),
          ),
        ),
      );
      Future<void> settled() async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (engine.status(active).isLoading &&
            DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          engine.status(active).isLoading,
          false,
          reason: 'External HTTPS fixture did not settle',
        );
      }

      Future<bool> authenticated() async {
        final body = await engine.evaluateForTesting(
          active,
          '(()=>{try{return JSON.parse(document.body.innerText).authenticated === true;}catch{return false;}})()',
        );
        return body.toString() == 'true';
      }

      Future<void> open(String id, bool private) async {
        active = id;
        await engine.open(tabId: id, url: address, isPrivate: private);
        await tester.pump();
        await settled();
      }

      await open('normal', false);
      expect(
        await authenticated(),
        true,
        reason: 'Fixture/provider failure is inconclusive, not a privacy pass',
      );
      expect(challenges['normal'], 1);
      await open('private-denied', true);
      expect(
        challenges['private-denied'],
        1,
        reason: 'Private must receive its own challenge',
      );
      expect(
        await authenticated(),
        false,
        reason: 'Normal credentials must not silently authenticate private',
      );
      permitPrivate = true;
      await engine.reload(active);
      await tester.pump();
      await settled();
      expect(challenges['private-denied'], 2);
      expect(await authenticated(), true);
      await engine.close(active);
      active = 'normal';
      engine.activate(active);
      await engine.reload(active);
      await tester.pump();
      await settled();
      expect(await authenticated(), true);
      expect(
        challenges['normal'],
        1,
        reason: 'Closing private must not clear normal HTTP authentication',
      );
      permitPrivate = false;
      await open('private-fresh', true);
      expect(challenges['private-fresh'], 1);
      expect(await authenticated(), false);
      await tester.pumpWidget(const SizedBox());
      for (final id in engine.liveTabIds) {
        await engine.close(id);
      }
      engine.dispose();
      debugPrint(
        'AUTH synthetic normal/private challenge separation and normal session preservation passed',
      );
    },
    skip: !const bool.fromEnvironment('RUN_HTTPS_AUTH_FIXTURE'),
  );
}
