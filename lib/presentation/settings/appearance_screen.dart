import 'package:flutter/material.dart';
import '../../policy/policy_runtime.dart';
import '../../state/browser_state.dart';
import '../components/wingman_components.dart';
import '../protection/additional_boundaries_screen.dart';

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({
    super.key,
    required this.state,
    required this.canContinue,
    this.accessibility = false,
    this.isPrivate = false,
  });
  final BrowserState state;
  final bool Function() canContinue;
  final bool accessibility;
  final bool isPrivate;
  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  bool _busy = false;
  String? _error;
  Future<void> _save({ThemeMode? themeMode, int? pageScale}) async {
    if (_busy || widget.isPrivate || !widget.canContinue()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.saveSettingsPatch(
        themeMode: themeMode,
        pageScale: pageScale,
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The display preference could not be saved. Your previous saved setting remains.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) => WingmanPage(
      title: widget.accessibility ? 'Accessibility' : 'Appearance',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.accessibility) ...[
            const WingmanSection(title: 'Appearance'),
            const Text(
              'Dark appearance changes colors. Private sessions have a separate label and data boundary.',
            ),
            const SizedBox(height: 16),
            ThemePreviewChoices(
              value: widget.state.settings.themeMode,
              onChanged: _busy || widget.isPrivate
                  ? null
                  : (mode) => _save(themeMode: mode),
            ),
            const SizedBox(height: 24),
          ],
          const WingmanSection(title: 'Reading size'),
          Text('Article text · ${widget.state.settings.pageScale}%'),
          Slider(
            value: widget.state.settings.pageScale.toDouble(),
            min: 75,
            max: 200,
            divisions: 5,
            label: '${widget.state.settings.pageScale}%',
            onChanged: _busy || widget.isPrivate
                ? null
                : (v) => _save(pageScale: v.round()),
          ),
          const Text(
            'This adjusts reviewed article text. Device accessibility text scaling still applies throughout Wingman.',
          ),
          const SizedBox(height: 24),
          if (widget.isPrivate)
            const WingmanStatus(
              title: 'Owner preferences stay separate',
              message:
                  'Appearance and reading size are read-only in this private session. Change saved preferences from a normal session.',
            ),
          const WingmanStatus(
            title: 'Device accessibility',
            message:
                'Use your device settings for larger text, screen readers and reduced motion. Wingman keeps labeled controls and does not shrink essential instructions to fit.',
            tone: WingmanTone.info,
          ),
          const SizedBox(height: 16),
          const WingmanStatus(
            title: 'Address-bar position',
            message:
                'The native address control stays above the bottom browser dock. Tap it to enter another address; each destination passes the current website policy.',
            tone: WingmanTone.info,
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            WingmanStatus(
              title: 'Saving not confirmed',
              message: _error!,
              tone: WingmanTone.caution,
            ),
        ],
      ),
    ),
  );
}

class SearchSettingsScreen extends StatefulWidget {
  const SearchSettingsScreen({
    super.key,
    required this.state,
    required this.canContinue,
    this.policy,
    this.isPrivate = false,
  });
  final BrowserState state;
  final bool Function() canContinue;
  final PolicyRuntime? policy;
  final bool isPrivate;
  @override
  State<SearchSettingsScreen> createState() => _SearchSettingsScreenState();
}

class _SearchSettingsScreenState extends State<SearchSettingsScreen> {
  bool _busy = false;
  String? _error;
  Future<void> _change(bool enabled) async {
    if (_busy || widget.isPrivate || !widget.canContinue()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.saveSettingsPatch(localSuggestions: enabled);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The preference could not be saved. Your previous saved setting remains.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.state, widget.policy]),
    builder: (context, _) {
      final additional = widget.state.protectedPreferences.additional;
      final blocked =
          additional.blockedCollections.contains('web-search') ||
          additional.blockedResourceIds.contains('web-search');
      final available =
          widget.policy?.searchAvailable(
            isPrivate: widget.isPrivate,
            additional: additional,
          ) ??
          false;
      return WingmanPage(
        title: 'Search',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const WingmanSection(title: 'Web search'),
            const WingmanSettingsRow(
              icon: Icons.lock_outline,
              title: 'DuckDuckGo · Adult filtering: Strict',
              subtitle: 'Publisher-fixed. There is no Moderate or Off setting.',
            ),
            WingmanStatus(
              title: blocked
                  ? 'Web search disabled'
                  : available
                  ? 'Web search available in this session'
                  : 'Web search unavailable in this session',
              message: blocked
                  ? 'Your additional boundary disables web search. Private tabs inherit this choice. Local library search remains available.'
                  : available
                  ? 'Search opens DuckDuckGo with required Strict adult filtering. Native browsing supports refinement, subsequent results and ordinary permitted destinations. Search previews and ads can contain filtering misses.'
                  : 'Native search requires a working browser engine and protection baseline. The web companion opens the strict provider in the host browser, whose protections Wingman cannot control. Windows and Linux native browsing are unavailable.',
              tone: WingmanTone.info,
            ),
            const WingmanStatus(
              title: 'Search previews have limited coverage',
              message:
                  'DuckDuckGo filters adult results. Wingman does not classify every result snippet or advertisement against all six content rules. Strict filtering can miss content; a result is not permission to open its destination.',
              tone: WingmanTone.caution,
            ),
            const Text(
              'Web search requests send your submitted query to DuckDuckGo, which also receives your connection’s IP address. Wingman sends no remote suggestions while you type. Search uses the provider’s ordinary website without a paid search service.',
            ),
            if (widget.policy != null)
              WingmanSettingsRow(
                icon: Icons.tune,
                title: 'Additional search boundary',
                subtitle: widget.isPrivate
                    ? 'View the inherited Disable web search setting'
                    : 'Disable web search without weakening the fixed baseline',
                onTap: () {
                  if (!widget.canContinue()) return;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AdditionalBoundariesScreen(
                        state: widget.state,
                        policy: widget.policy!,
                        isPrivate: widget.isPrivate,
                        canContinue: widget.canContinue,
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 24),
            const WingmanSection(title: 'On-device search'),
            const WingmanSettingsRow(
              icon: Icons.search,
              title: 'Approved resources',
              subtitle: 'Local signed library · No external recipient',
            ),
            const SizedBox(height: 16),
            const Text(
              'Queries are matched on this device. Official Routes searches its local identity catalog; identity evidence never grants live access.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Local approved-resource suggestions'),
              subtitle: const Text(
                'No history, clipboard or keystroke upload. Personal suggestions stay unavailable in private and shared views.',
              ),
              value: widget.state.settings.localSuggestions,
              onChanged: _busy || widget.isPrivate ? null : _change,
            ),
            if (widget.isPrivate)
              const WingmanStatus(
                title: 'Preferences are read-only in private',
                message:
                    'Private tabs inherit saved restrictions. Change owner preferences from a normal session.',
                tone: WingmanTone.info,
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              WingmanStatus(
                title: 'Saving not confirmed',
                message: _error!,
                tone: WingmanTone.caution,
              ),
          ],
        ),
      );
    },
  );
}

/// A real preference control with local, decorative previews of each theme.
class ThemePreviewChoices extends StatelessWidget {
  const ThemePreviewChoices({super.key, required this.value, this.onChanged});
  final ThemeMode value;
  final ValueChanged<ThemeMode>? onChanged;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final count =
          constraints.maxWidth >= 660 &&
              MediaQuery.textScalerOf(context).scale(16) < 25
          ? 3
          : 1;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final mode in [
            ThemeMode.light,
            ThemeMode.dark,
            ThemeMode.system,
          ])
            SizedBox(
              width: (constraints.maxWidth - 16 * (count - 1)) / count,
              child: Semantics(
                selected: value == mode,
                button: true,
                enabled: onChanged != null,
                child: Material(
                  color: WingmanTokens.of(context).surface,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: onChanged == null ? null : () => onChanged!(mode),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: value == mode
                              ? WingmanTokens.of(context).action
                              : WingmanTokens.of(context).divider,
                          width: value == mode ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ExcludeSemantics(
                            child: SizedBox(
                              height: 90,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: mode == ThemeMode.system
                                          ? Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Expanded(
                                                  child: ColoredBox(
                                                    color: WingmanTokens
                                                        .light
                                                        .raised,
                                                  ),
                                                ),
                                                Expanded(
                                                  child: ColoredBox(
                                                    color: WingmanTokens
                                                        .dark
                                                        .raised,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : ColoredBox(
                                              color:
                                                  (mode == ThemeMode.dark
                                                          ? WingmanTokens.dark
                                                          : WingmanTokens.light)
                                                      .raised,
                                            ),
                                    ),
                                    Positioned(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      height: 15,
                                      child: ColoredBox(
                                        color:
                                            (mode == ThemeMode.dark
                                                    ? WingmanTokens.dark
                                                    : WingmanTokens.light)
                                                .divider,
                                      ),
                                    ),
                                    Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 90,
                                            height: 9,
                                            decoration: BoxDecoration(
                                              color:
                                                  (mode == ThemeMode.dark
                                                          ? WingmanTokens.dark
                                                          : WingmanTokens.light)
                                                      .surface,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Container(
                                            width: 45,
                                            height: 21,
                                            decoration: BoxDecoration(
                                              color: WingmanTokens.light.action,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  switch (mode) {
                                    ThemeMode.light => 'Light',
                                    ThemeMode.dark => 'Dark',
                                    ThemeMode.system => 'Use device setting',
                                  },
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              if (value == mode)
                                Icon(
                                  Icons.check_circle_outline,
                                  color: WingmanTokens.of(context).action,
                                  size: 20,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
