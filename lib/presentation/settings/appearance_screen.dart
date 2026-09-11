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
  });
  final BrowserState state;
  final bool Function() canContinue;
  final bool accessibility;
  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  bool _busy = false;
  String? _error;
  Future<void> _save({ThemeMode? themeMode, int? pageScale}) async {
    if (_busy || !widget.canContinue()) return;
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
            for (final mode in ThemeMode.values)
              ListTile(
                leading: Icon(
                  widget.state.settings.themeMode == mode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                selected: widget.state.settings.themeMode == mode,
                onTap: _busy ? null : () => _save(themeMode: mode),
                title: Text(switch (mode) {
                  ThemeMode.system => 'Use device setting',
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                }),
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
            onChanged: _busy ? null : (v) => _save(pageScale: v.round()),
          ),
          const Text(
            'This adjusts reviewed article text. Device accessibility text scaling still applies throughout Wingman.',
          ),
          const SizedBox(height: 24),
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
                  ? 'Search opens the first, text-only DuckDuckGo results page. Image search, pagination and page forms are unavailable. Website access remains limited to reviewed destination pages.'
                  : 'Web search requires a supported Android or iOS native session and a current policy. The web companion has local tools only; native desktop apps are not available.',
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
