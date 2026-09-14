import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../policy/policy_runtime.dart';
import '../browser_shell.dart' show safeTextContextMenu;
import '../components/wingman_components.dart';

class SearchIntent {
  const SearchIntent(this.query, {this.official = false, this.web = false});
  final String query;
  final bool official, web;
}

class FocusedSearchScreen extends StatefulWidget {
  const FocusedSearchScreen({
    super.key,
    required this.policy,
    required this.additional,
    required this.contentContext,
    required this.isPrivate,
    required this.localSuggestions,
    this.initialQuery = '',
  });
  final PolicyRuntime policy;
  final AdditionalRestrictions Function() additional;
  final ContentContext contentContext;
  final bool isPrivate, localSuggestions;
  final String initialQuery;
  @override
  State<FocusedSearchScreen> createState() => _FocusedSearchScreenState();
}

class _FocusedSearchScreenState extends State<FocusedSearchScreen> {
  late final _text = TextEditingController(text: widget.initialQuery);
  bool _official = false;
  late bool _web = widget.policy.searchAvailable(
    isPrivate: widget.isPrivate,
    additional: widget.additional(),
  );
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(
    context,
    SearchIntent(_text.text, official: _official, web: _web),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.policy,
    builder: (context, _) {
      final webAvailable = widget.policy.searchAvailable(
        isPrivate: widget.isPrivate,
        additional: widget.additional(),
      );
      final suggestions =
          !widget.localSuggestions ||
              widget.isPrivate ||
              _official ||
              _web ||
              _text.text.trim().isEmpty
          ? <ApprovedResource>[]
          : widget.policy
                .search(
                  _text.text.trim(),
                  additional: widget.additional(),
                  context: widget.contentContext,
                )
                .where(
                  (r) => widget.policy.policy
                      .evaluate(
                        PolicyRequest.bundled(
                          r.id,
                          context: widget.contentContext,
                          isPrivate: widget.isPrivate,
                        ),
                        additional: widget.additional(),
                      )
                      .isAllowed,
                )
                .take(5)
                .toList();
      return WingmanPage(
        title: 'Search',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('protected-search'),
              controller: _text,
              autofocus: true,
              maxLength: 512,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              textInputAction: TextInputAction.search,
              contextMenuBuilder: safeTextContextMenu,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Search or enter address',
                counterText: '',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Clear search',
                  onPressed: () => setState(_text.clear),
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Web'),
                  selected: _web,
                  onSelected: webAvailable
                      ? (_) => setState(() {
                          _web = true;
                          _official = false;
                        })
                      : null,
                ),
                ChoiceChip(
                  label: const Text('Library'),
                  selected: !_official && !_web,
                  onSelected: (_) => setState(() {
                    _official = false;
                    _web = false;
                  }),
                ),
                ChoiceChip(
                  label: const Text('Official'),
                  selected: _official,
                  onSelected: (_) => setState(() {
                    _official = true;
                    _web = false;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Search'),
            ),
            const SizedBox(height: 20),
            Text(
              _web
                  ? 'Search with DuckDuckGo'
                  : 'Search your library on this device',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(
              _web
                  ? 'Your search terms aren’t saved by Wingman.'
                  : 'Typing stays local. Addresses open after you submit.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            ExpansionTile(
              key: const ValueKey('search-privacy-details'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 16),
              title: const Text('Search privacy & protection'),
              children: [
                Text(
                  _web
                      ? 'Submitting sends your query and connection information directly to DuckDuckGo. Typing makes no network request. Wingman requires DuckDuckGo’s Strict adult filter; previews and ads can contain filtering misses.'
                      : 'Library and Official searches run on this device. Entering a supported address connects only after you submit.',
                ),
                const SizedBox(height: 8),
                Text(
                  _web
                      ? kIsWeb
                            ? 'Web search opens in your host browser. Wingman cannot enforce its native destination filters after you leave this app.'
                            : 'Search previews and ads are not fully classified against Wingman’s other category rules. Destination filters apply when links open.'
                      : webAvailable
                      ? 'Choose Web to search with DuckDuckGo.'
                      : 'Web search is unavailable under your current boundaries. The installed library remains available.',
                ),
              ],
            ),
            if (widget.isPrivate) ...[
              const SizedBox(height: 12),
              const Text(
                'Private search does not use saved activity or retain suggestions.',
              ),
            ],
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 24),
              const WingmanSection(title: 'Reviewed matches'),
              for (final resource in suggestions)
                WingmanSettingsRow(
                  icon: Icons.menu_book_outlined,
                  title: resource.title,
                  subtitle: 'Search this title in the local library',
                  onTap: () =>
                      Navigator.pop(context, SearchIntent(resource.title)),
                ),
            ],
          ],
        ),
      );
    },
  );
}
