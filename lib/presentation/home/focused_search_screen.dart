import 'package:flutter/material.dart';
import '../../policy/policy_runtime.dart';
import '../browser_shell.dart' show safeTextContextMenu;
import '../components/wingman_components.dart';

class SearchIntent {
  const SearchIntent(this.query, {this.official = false});
  final String query;
  final bool official;
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
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(
    context,
    SearchIntent(_text.text.trim(), official: _official),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.policy,
    builder: (context, _) {
      final suggestions =
          !widget.localSuggestions ||
              widget.isPrivate ||
              _official ||
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
                  label: const Text('Library'),
                  selected: !_official,
                  onSelected: (_) => setState(() => _official = false),
                ),
                ChoiceChip(
                  label: const Text('Official'),
                  selected: _official,
                  onSelected: (_) => setState(() => _official = true),
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
            const Text(
              'Search runs on this device. Entering an address opens only a reviewed scope supported by this native app. Page requests go directly to the website after you submit; typing makes no network request.',
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
