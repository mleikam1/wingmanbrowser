import 'package:flutter/material.dart';
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
                  ? 'DuckDuckGo · Adult filtering: Strict, required by Wingman. Submitting sends your query and connection information directly to DuckDuckGo. Typing makes no network request; search terms are not saved by Wingman.'
                  : 'Library and Official searches run on this device. Typing makes no network request. Entering a supported address connects only after you submit.',
            ),
            const SizedBox(height: 12),
            Text(
              _web
                  ? 'Search previews use DuckDuckGo’s adult filter. They are not fully classified against Wingman’s other content rules. This preview opens reviewed pages only; images, pagination and provider forms are unavailable. Use this field for each new search.'
                  : webAvailable
                  ? 'Choose Web to search with DuckDuckGo’s required Strict adult filtering.'
                  : 'Web search is unavailable on this platform or under your current boundaries. The installed library remains available.',
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
