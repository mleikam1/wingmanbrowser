import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../domain/search.dart';
import '../../state/browser_state.dart';
import '../widgets/brand.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.state,
    required this.onClear,
    required this.onDefaultBrowser,
    this.onGuard,
  });
  final BrowserState state;
  final VoidCallback onClear, onDefaultBrowser;
  final VoidCallback? onGuard;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Settings & privacy')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
            children: [
              const WingmanWordmark(),
              const SizedBox(height: 22),
              Text(
                "We've got your back, not your data.",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 28),
              const _Section('Make yourself at home'),
              if (onGuard != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Wingman Guard'),
                  subtitle: const Text('Your protections, your choices.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onGuard,
                ),
              DropdownButtonFormField<ThemeMode>(
                isExpanded: true,
                initialValue: state.settings.themeMode,
                decoration: const InputDecoration(labelText: 'Appearance'),
                items: const [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('Use device setting'),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text('Light'),
                  ),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    state.saveSettings(
                      state.settings.copyWith(themeMode: value),
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: state.settings.searchProviderId,
                decoration: const InputDecoration(labelText: 'Search engine'),
                items: SearchProvider.available
                    .map(
                      (provider) => DropdownMenuItem(
                        value: provider.id,
                        child: Text(provider.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    state.saveSettings(
                      state.settings.copyWith(searchProviderId: value),
                    );
                  }
                },
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 10, 4, 24),
                child: Text(
                  'Searches go directly to your selected provider, which processes your query under its own privacy policy.',
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Local address suggestions'),
                subtitle: const Text(
                  'From saved bookmarks and history. No keystrokes are sent to Wingman. Always off in private tabs.',
                ),
                value: state.settings.localSuggestions,
                onChanged: (value) => state.saveSettings(
                  state.settings.copyWith(localSuggestions: value),
                ),
              ),
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.language_rounded),
                  title: const Text('Set Wingman as Default Browser'),
                  subtitle: const Text(
                    'Your choice, through Android settings.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onDefaultBrowser,
                ),
              const _Section('Your Data'),
              const _InfoCard(
                icon: Icons.shield_outlined,
                title: 'Your browsing history is yours.',
                text:
                    'Wingman doesn’t sell your browsing history, build an advertising profile from the sites you visit, or inject Wingman ads into the websites you browse.\n\nHistory, bookmarks, tab details, and preferences remain on this device by default. History is retained for up to 90 days, with a limit of 5,000 entries. No Wingman account or cloud backend is required.',
              ),
              const SizedBox(height: 14),
              const _InfoCard(
                icon: Icons.visibility_off_outlined,
                title: 'What private browsing means',
                text:
                    'Private tabs aren’t saved in your history or restored after restart. Their site storage is isolated from normal tabs and cleared when the tab closes or is evicted from memory. On iOS, private site storage is nonpersistent. Android may temporarily write isolated site data to disk; cleanup runs when a tab closes and on the next launch.\n\nPrivate browsing does not make you anonymous to websites, search providers, your internet provider, or the network you use. Downloads you explicitly save are not private-session data.',
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Clear Browsing Data'),
                subtitle: Text(
                  kIsWeb
                      ? 'Clear Wingman history. Manage other website data in your host browser.'
                      : 'Choose history, cookies, cache, or site storage.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: onClear,
              ),
              const SizedBox(height: 24),
              const _Section('How Wingman Makes Money'),
              const _InfoCard(
                icon: Icons.volunteer_activism_outlined,
                title: 'Supported without selling your history',
                text:
                    'Wingman may earn money from advertising on its own Home and start experiences, clearly labeled sponsored placements, search partnerships, affiliate links you choose to open, and other disclosed commercial relationships.\n\nThis foundation has no live paid placements or commercial search agreement. A development build can opt in to Google’s test ads. Advertising never appears over a website or between normal page navigations.',
              ),
              const SizedBox(height: 14),
              const _InfoCard(
                icon: Icons.info_outline,
                title: 'An honest picture',
                text:
                    'Websites, search providers, your operating system, and network services can process technical information. If test ads are enabled and you choose to load one, Google’s advertising and consent services may process device and network information.\n\nWingman has no separate analytics, attribution, or crash-reporting service installed. Future services must be reviewed against the same privacy promise.',
              ),
              const SizedBox(height: 26),
              Text(
                'Wingman Browser · Foundation 0.1\nBuilt to browse without an account.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title, text;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(height: 1.5)),
        ],
      ),
    ),
  );
}
