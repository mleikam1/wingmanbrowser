// Development-only fixtures. No owner storage, native channels or policy bypass.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wingman_browser/presentation/components/wingman_components.dart';
import 'package:wingman_browser/presentation/home/home_screen.dart';
import 'package:wingman_browser/presentation/home/welcome_screen.dart';
import 'package:wingman_browser/presentation/design_system/ui_preferences.dart';
import 'package:wingman_browser/signature/workspaces/workspace_models.dart';

class FoundationGalleryMenu extends StatelessWidget {
  const FoundationGalleryMenu({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const WingmanSection(title: 'Home & first run'),
      const Text(
        'SYNTHETIC DEVELOPMENT SCENES · No owner state or native services.',
      ),
      for (final scene in [
        'Empty Home',
        'Populated Home',
        'Private Home',
        'Policy unavailable',
        'Home storage failure',
        'Welcome',
        'Welcome save failure',
      ])
        WingmanSettingsRow(
          icon: Icons.home_outlined,
          title: scene,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => _FoundationScene(scene)),
          ),
        ),
    ],
  );
}

class _FoundationScene extends StatelessWidget {
  const _FoundationScene(this.scene);
  final String scene;
  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    void intercepted() => ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Synthetic navigation intercepted. Choose the functional feature scene from the gallery.',
        ),
      ),
    );
    final task = FinishWorkspace(
      id: 'synthetic-task',
      goal: 'Plan a weekend project',
      checklist: const [
        ChecklistItem('step-one', 'Choose one project', done: true),
        ChecklistItem('step-two', 'Read a planning guide', done: true),
        ChecklistItem('step-three', 'Write down the next step'),
      ],
    );
    final page = scene.startsWith('Welcome')
        ? WelcomeScreen(
            onComplete: () async {
              if (scene == 'Welcome save failure') {
                throw StateError('Synthetic storage failure');
              }
              Navigator.pop(context);
            },
          )
        : HomeScreen(
            preferences: UiPreferences(),
            resources: const [],
            onSearch: intercepted,
            onSettings: intercepted,
            onProtection: intercepted,
            onOfficial: intercepted,
            onLibrary: intercepted,
            onCustomize: intercepted,
            onExplore: intercepted,
            onOpen: (_) => intercepted(),
            onSpaces: intercepted,
            onTask: (_) => intercepted(),
            task: scene == 'Populated Home' ? task : null,
            spaceCards: scene == 'Populated Home'
                ? [
                    for (final kind in SpaceKind.values)
                      Card(
                        child: WingmanSettingsRow(
                          icon: Icons.dashboard_outlined,
                          title: kind.label,
                          subtitle: 'Synthetic chosen Space',
                          onTap: intercepted,
                        ),
                      ),
                  ]
                : const [],
            isPrivate: scene == 'Private Home',
            policyUsable: scene != 'Policy unavailable',
            storageError: scene == 'Home storage failure'
                ? 'Synthetic write failure. The earlier saved layout is retained.'
                : null,
          );
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: WingmanTokens.of(context).raised,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Return to gallery',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                  const Expanded(child: Text('SYNTHETIC · NO OWNER DATA')),
                ],
              ),
            ),
            Expanded(child: page),
          ],
        ),
      ),
    );
  }
}
