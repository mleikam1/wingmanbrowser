// Development-only entrypoint. Never imported by lib/main.dart.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/presentation/app_route_observer.dart';
import 'ui_gallery/official_commit_scenes.dart';
import 'ui_gallery/workspace_handoff_scenes.dart';
import 'ui_gallery/settings_library_scenes.dart';
import 'ui_gallery/foundation_scenes.dart';
import 'ui_gallery/gallery_clipboard_binding.dart';
import 'package:wingman_browser/presentation/components/wingman_components.dart';

void main() {
  if (!kDebugMode) {
    runApp(const SizedBox.shrink());
    return;
  }
  initializeGalleryClipboardIsolation();
  runApp(const WingmanUiGallery());
}

class WingmanUiGallery extends StatefulWidget {
  const WingmanUiGallery({super.key});
  @override
  State<WingmanUiGallery> createState() => _WingmanUiGalleryState();
}

class _WingmanUiGalleryState extends State<WingmanUiGallery> {
  bool dark = false, largeText = false;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    navigatorObservers: [appRouteObserver],
    theme: WingmanTheme.make(dark ? Brightness.dark : Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(largeText ? 2 : 1),
        platformBrightness: dark ? Brightness.dark : Brightness.light,
      ),
      child: child!,
    ),
    home: WingmanPage(
      title: 'Development gallery',
      actions: [
        IconButton(
          tooltip: 'Toggle theme',
          onPressed: () => setState(() => dark = !dark),
          icon: const Icon(Icons.contrast),
        ),
        IconButton(
          tooltip: 'Toggle 200% text',
          onPressed: () => setState(() => largeText = !largeText),
          icon: const Icon(Icons.text_fields),
        ),
      ],
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FoundationGalleryMenu(),
          OfficialCommitGalleryMenu(),
          WorkspaceHandoffGalleryMenu(),
          SettingsLibraryGalleryMenu(),
          WingmanComponentGallery(),
        ],
      ),
    ),
  );
}

class WingmanComponentGallery extends StatelessWidget {
  const WingmanComponentGallery({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('SYNTHETIC COMPONENT STATES · NO OWNER DATA'),
      const SizedBox(height: 24),
      const WingmanBrand(),
      const WingmanSection(title: 'Calm, clear, and connected'),
      const Text(
        'Local Roboto, semantic blue roles, responsive text and opaque surfaces.',
      ),
      const SizedBox(height: 16),
      const TextField(
        decoration: InputDecoration(
          labelText: 'Example input',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Synthetic action completed.')),
            ),
            child: const Text('Try an action'),
          ),
          const OutlinedButton(onPressed: null, child: Text('Unavailable')),
        ],
      ),
      const WingmanSection(title: 'Status and uncertainty'),
      const WingmanStatus(
        title: 'Limited coverage',
        message: 'Example: only signed local text is eligible.',
      ),
      const SizedBox(height: 12),
      const WingmanStatus(
        title: 'Could not confirm',
        message: 'Example: this selection does not state cancellation terms.',
        tone: WingmanTone.caution,
      ),
      const SizedBox(height: 12),
      const WingmanStatus(
        title: 'Could not save',
        message: 'Example storage failure. Your previous record is retained.',
        tone: WingmanTone.danger,
      ),
      const SizedBox(height: 12),
      const WingmanStatus(
        title: 'Saved locally',
        message: 'Example completed operation; nothing was submitted.',
        tone: WingmanTone.success,
      ),
      const WingmanEmptyState(
        icon: Icons.bookmark_outline,
        title: 'No saved items',
        message:
            'An empty-state example. Choose an eligible resource to begin.',
      ),
    ],
  );
}
