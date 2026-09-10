import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../domain/search.dart';
import '../../domain/local_suggestions.dart';
import '../../monetization/home_ad_slot.dart';
import '../../state/browser_state.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/omnibox.dart';

/// Owned modules have explicit composition here; website content is elsewhere.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.state,
    required this.onNavigate,
    required this.onSettings,
    required this.onBookmarks,
    required this.onPrivate,
    this.guardCard,
  });
  final BrowserState state;
  final ValueChanged<String> onNavigate;
  final VoidCallback onSettings;
  final VoidCallback onBookmarks;
  final VoidCallback onPrivate;
  final Widget? guardCard;
  @override
  Widget build(BuildContext context) {
    final private = state.activeTab.isPrivate;
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      key: const ValueKey('wingman-home'),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const WingmanWordmark(),
                  const Spacer(),
                  IconButton(
                    onPressed: onSettings,
                    tooltip: 'Settings and privacy',
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ],
              ),
              SizedBox(
                height: MediaQuery.sizeOf(context).width > 650 ? 72 : 42,
              ),
              if (private) ...[
                const _Eyebrow(
                  icon: Icons.visibility_off_outlined,
                  text: 'PRIVATE BROWSING',
                ),
                const SizedBox(height: 16),
                Text(
                  'A little more\nspace to yourself.',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.6,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Pages in private tabs stay out of your saved history. Websites and your network can still see your activity.',
                ),
              ] else ...[
                const _Eyebrow(
                  icon: Icons.wb_sunny_outlined,
                  text: 'A GOOD PLACE TO START',
                ),
                const SizedBox(height: 16),
                Text(
                  "The web is yours.\nGo explore.",
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.6,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  "We've got your back, not your data.",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Omnibox(
                onSubmit: onNavigate,
                isPrivate: private,
                localSuggestions: (input) =>
                    const LocalSuggestionService().suggest(
                      input,
                      bookmarks: state.bookmarks,
                      history: state.history,
                      isPrivate: private,
                      enabled: state.settings.localSuggestions,
                    ),
                searchProvider: SearchProvider.byId(
                  state.settings.searchProviderId,
                ).name,
              ),
              if (guardCard != null) ...[
                const SizedBox(height: 20),
                guardCard!,
              ],
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your launchpad',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onBookmarks,
                    child: const Text('Bookmarks'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _QuickLink(
                    label: 'Wikipedia',
                    icon: Icons.menu_book_rounded,
                    color: const Color(0xff50647b),
                    onTap: () => onNavigate('https://www.wikipedia.org'),
                  ),
                  _QuickLink(
                    label: 'YouTube',
                    icon: Icons.play_arrow_rounded,
                    color: const Color(0xffbd5148),
                    onTap: () => onNavigate('https://www.youtube.com'),
                  ),
                  _QuickLink(
                    label: 'OpenAI',
                    icon: Icons.auto_awesome_outlined,
                    color: WingmanTheme.green,
                    onTap: () => onNavigate('https://openai.com'),
                  ),
                  _QuickLink(
                    label: 'Bookmarks',
                    icon: Icons.bookmark_border_rounded,
                    color: const Color(0xff977120),
                    onTap: onBookmarks,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cards = [
                    _HomeCard(
                      icon: Icons.shield_outlined,
                      title: private
                          ? 'Private, with perspective'
                          : 'Your history. Your business.',
                      body: private
                          ? 'Private browsing is not a VPN. Close your private tabs to end their session.'
                          : 'Your browsing history stays on this device by default. No account needed.',
                      action: 'Meet your privacy settings',
                      onTap: onSettings,
                      tint: scheme.primaryContainer.withValues(alpha: .38),
                    ),
                    _HomeCard(
                      icon: Icons.volunteer_activism_outlined,
                      title: 'A browser worth backing',
                      body:
                          'Clearly labeled sponsorships on Wingman surfaces can help keep browsing free. We don’t insert Wingman ads into websites.',
                      action: 'How Wingman makes money',
                      onTap: onSettings,
                    ),
                  ];
                  return constraints.maxWidth > 650
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 16),
                            Expanded(child: cards[1]),
                          ],
                        )
                      : Column(
                          children: [
                            cards[0],
                            const SizedBox(height: 14),
                            cards[1],
                          ],
                        );
                },
              ),
              if (!private) ...[
                const SizedBox(height: 12),
                const HomeAdSlot(isPrivate: false),
              ],
              const SizedBox(height: 26),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    kIsWeb ? Icons.open_in_new : Icons.lock_outline,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      kIsWeb
                          ? 'Wingman Web opens websites in your browser. Your mobile Wingman app is a full browser.'
                          : 'Made for a little more peace of mind.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              if (!kIsWeb && !private)
                TextButton.icon(
                  onPressed: onPrivate,
                  icon: const Icon(Icons.visibility_off_outlined, size: 18),
                  label: const Text('Open a private tab'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.7,
          ),
        ),
      ),
    ],
  );
}

class _QuickLink extends StatelessWidget {
  const _QuickLink({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 94,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 9),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onTap,
    this.tint,
  });
  final IconData icon;
  final String title, body, action;
  final VoidCallback onTap;
  final Color? tint;
  @override
  Widget build(BuildContext context) => Card(
    color: tint,
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 18),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 9),
          Text(
            body,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
            ),
            child: Text('$action →'),
          ),
        ],
      ),
    ),
  );
}
