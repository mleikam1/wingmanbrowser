import 'package:flutter/material.dart';
import '../../policy/policy_runtime.dart';
import '../components/wingman_components.dart';
import '../design_system/ui_preferences.dart';
import '../discovery/discovery_photos.dart';

class CustomizeHomeScreen extends StatefulWidget {
  const CustomizeHomeScreen({
    super.key,
    required this.controller,
    required this.policy,
    required this.eligible,
    required this.canContinue,
    required this.onSpaces,
    required this.isPrivate,
    this.onLaunchpad,
  });
  final UiPreferencesController controller;
  final PolicyRuntime policy;
  final bool Function(String) eligible;
  final bool Function() canContinue;
  final VoidCallback onSpaces;
  final bool isPrivate;
  final VoidCallback? onLaunchpad;
  @override
  State<CustomizeHomeScreen> createState() => _CustomizeHomeScreenState();
}

class _CustomizeHomeScreenState extends State<CustomizeHomeScreen> {
  bool _busy = false;
  String? _error;
  Future<void> _reset() async {
    if (_busy || !widget.canContinue()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Restore default Home?'),
        scrollable: true,
        content: const Text(
          'This restores Home section visibility, order and artwork. Your Launchpad, Spaces, tasks, saved findings and library stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep layout'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Restore defaults'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !widget.canContinue()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.reset();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The default layout could not be saved. Your saved record is retained.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _update(UiPreferences Function(UiPreferences) change) async {
    if (_busy || !widget.canContinue()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.update((preferences) {
        if (!mounted || !widget.canContinue()) {
          throw StateError('This Home session has ended.');
        }
        return change(preferences);
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The layout could not be saved. Your previous choices remain.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.controller, widget.policy]),
    builder: (context, _) {
      final prefs = widget.controller.snapshot;
      return WingmanPage(
        title: 'Customize Home',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isPrivate
                  ? 'These choices last only for this private session.'
                  : 'Choose your shortcuts, artwork and the sections that appear on Home.',
            ),
            if (_error ?? widget.controller.storageError
                case final String error) ...[
              const SizedBox(height: 16),
              WingmanStatus(
                title: 'Change not saved',
                message: error,
                tone: WingmanTone.caution,
              ),
            ],
            const WingmanSection(title: 'Home artwork'),
            const Text(
              'A small photo panel, with text kept on its own clear surface. Every photograph is stored with the app.',
            ),
            const SizedBox(height: 12),
            for (final artwork in HomeArtwork.values)
              _ArtworkChoice(
                artwork: artwork,
                selected: prefs.homeArtwork == artwork,
                onSelected: _busy
                    ? null
                    : () => _update((p) => p.copyWith(homeArtwork: artwork)),
              ),
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _busy
                  ? null
                  : () {
                      if (!widget.canContinue()) return;
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const PhotoCreditsScreen(),
                        ),
                      );
                    },
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Photo credits'),
            ),
            const SizedBox(height: 24),
            const WingmanSection(title: 'Home sections'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Official Routes'),
              value: prefs.showOfficial,
              onChanged: _busy
                  ? null
                  : (v) => _update((p) => p.copyWith(showOfficial: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active Finish Mode task'),
              value: prefs.showTask,
              onChanged: _busy
                  ? null
                  : (v) => _update((p) => p.copyWith(showTask: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Your Spaces'),
              value: prefs.showSpaces,
              onChanged: _busy
                  ? null
                  : (v) => _update((p) => p.copyWith(showSpaces: v)),
            ),
            const SizedBox(height: 20),
            const WingmanSection(title: 'Section order'),
            for (var index = 0; index < prefs.moduleOrder.length; index++)
              Row(
                children: [
                  Expanded(
                    child: Text(switch (prefs.moduleOrder[index]) {
                      'shortcuts' => 'Shortcuts',
                      'official' => 'Official Routes',
                      'task' => 'Finish Mode',
                      _ => 'Your Spaces',
                    }),
                  ),
                  IconButton(
                    tooltip: 'Move ${prefs.moduleOrder[index]} up',
                    onPressed: _busy || index == 0
                        ? null
                        : () => _update((p) {
                            final order = [...p.moduleOrder];
                            final value = order.removeAt(index);
                            order.insert(index - 1, value);
                            return p.copyWith(moduleOrder: order);
                          }),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: 'Move ${prefs.moduleOrder[index]} down',
                    onPressed: _busy || index == prefs.moduleOrder.length - 1
                        ? null
                        : () => _update((p) {
                            final order = [...p.moduleOrder];
                            final value = order.removeAt(index);
                            order.insert(index + 1, value);
                            return p.copyWith(moduleOrder: order);
                          }),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                ],
              ),
            const SizedBox(height: 24),
            const WingmanSection(title: 'Your Launchpad'),
            const Text(
              'Manage pinned shortcuts, folders and optional collections separately from these Home sections.',
            ),
            if (widget.onLaunchpad != null)
              OutlinedButton.icon(
                onPressed: _busy ? null : widget.onLaunchpad,
                icon: const Icon(Icons.apps),
                label: const Text('Customize Launchpad'),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : widget.onSpaces,
              icon: const Icon(Icons.dashboard_outlined),
              label: const Text('Manage Spaces'),
            ),
            TextButton(
              onPressed: _busy ? null : _reset,
              child: const Text('Restore default Home'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(
                  semanticsLabel: 'Saving Home layout',
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _ArtworkChoice extends StatelessWidget {
  const _ArtworkChoice({
    required this.artwork,
    required this.selected,
    required this.onSelected,
  });

  final HomeArtwork artwork;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final photo = DiscoveryPhoto.forArtwork(artwork);
    return Semantics(
      selected: selected,
      child: ListTile(
        key: ValueKey('home-artwork-${artwork.name}'),
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        minTileHeight: 64,
        selected: selected,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 56,
            height: 48,
            child: photo == null
                ? ColoredBox(
                    color: WingmanTokens.of(context).raised,
                    child: const Icon(Icons.crop_landscape),
                  )
                : DiscoveryPhotoView(photo: photo, decorative: true),
          ),
        ),
        title: Text(photo?.title ?? 'Plain Home'),
        subtitle: Text(photo?.credit ?? 'No photo panel'),
        trailing: Icon(
          selected ? Icons.check_circle : Icons.radio_button_unchecked,
          semanticLabel: selected ? 'Selected' : null,
        ),
        onTap: onSelected,
      ),
    );
  }
}
