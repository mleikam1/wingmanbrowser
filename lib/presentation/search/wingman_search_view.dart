import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../search/controller.dart';
import '../browser_shell.dart' show safeTextContextMenu;
import '../components/wingman_components.dart';

class WingmanSearchView extends StatefulWidget {
  const WingmanSearchView({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.onOpen,
    required this.canContinue,
    required this.resultAllowed,
  });
  final WingmanSearchController controller;
  final ScrollController scrollController;
  final ValueChanged<Uri> onOpen;
  final bool Function() canContinue;
  final bool Function(Uri) resultAllowed;
  @override
  State<WingmanSearchView> createState() => _WingmanSearchViewState();
}

class _WingmanSearchViewState extends State<WingmanSearchView> {
  late final _text = TextEditingController(text: widget.controller.query);
  late SearchLocale _locale = widget.controller.locale;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.canContinue()) return;
    FocusScope.of(context).unfocus();
    widget.controller.submit(_text.text, selectedLocale: _locale);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final model = widget.controller;
      final results = model.results
          .where((r) => widget.resultAllowed(r.url))
          .toList();
      return ListView(
        key: const ValueKey('wingman-search-results'),
        controller: widget.scrollController,
        padding: EdgeInsets.all(
          WingmanTokens.gutter(MediaQuery.sizeOf(context).width),
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const WingmanBrand(),
                  const SizedBox(height: 16),
                  Semantics(
                    header: true,
                    child: Text(
                      'Wingman Search',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('wingman-search-field'),
                    controller: _text,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    textInputAction: TextInputAction.search,
                    contextMenuBuilder: safeTextContextMenu,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Search the web',
                      suffixIcon: IconButton(
                        tooltip: 'Submit search',
                        onPressed: _submit,
                        icon: const Icon(Icons.search),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final kind in SearchKind.values)
                        ChoiceChip(
                          key: ValueKey('search-${kind.name}'),
                          label: Text(kind == SearchKind.web ? 'All' : 'News'),
                          selected: model.kind == kind,
                          onSelected: (_) {
                            if (widget.canContinue()) model.selectKind(kind);
                          },
                        ),
                      SizedBox(
                        width: 280,
                        child: DropdownButtonFormField<SearchLocale>(
                          key: const ValueKey('search-country'),
                          initialValue: _locale,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Country and language',
                          ),
                          items: [
                            for (final locale in SearchLocale.supported)
                              DropdownMenuItem(
                                value: locale,
                                child: Text(
                                  locale.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _locale = value);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Country and language apply when you submit. No remote suggestions while typing.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (model.fixture)
                    const WingmanStatus(
                      title: 'Fixture results',
                      message:
                          'Synthetic development examples. No Brave request was made.',
                    ),
                  if (model.loading)
                    Semantics(
                      label: 'Search in progress',
                      liveRegion: true,
                      child: const LinearProgressIndicator(),
                    ),
                  if (model.failure case final failure?)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: WingmanStatus(
                          title: 'Search unavailable',
                          message: failure.message,
                          tone: WingmanTone.caution,
                        ),
                      ),
                    ),
                  if (!model.loading &&
                      model.failure == null &&
                      results.isEmpty)
                    WingmanStatus(
                      title: model.status == 'filtered'
                          ? 'Results withheld'
                          : 'No results',
                      message: model.status == 'filtered'
                          ? 'The returned results did not meet Wingman’s protection checks. Try a different search.'
                          : 'No matching results were returned for this request. Try different words.',
                    ),
                  for (final result in results)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result.source,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 4),
                          Semantics(
                            link: true,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                alignment: Alignment.centerLeft,
                              ),
                              onPressed: () {
                                if (widget.canContinue() &&
                                    widget.resultAllowed(result.url)) {
                                  widget.onOpen(result.url);
                                }
                              },
                              child: Text(
                                result.title,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: WingmanTokens.of(context).action,
                                    ),
                              ),
                            ),
                          ),
                          if (result.description.isNotEmpty)
                            Text(result.description),
                          if (result.publishedAt case final date?)
                            Text(
                              'Published ${date.toIso8601String().substring(0, 10)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          TextButton.icon(
                            onPressed: () {
                              if (widget.canContinue() &&
                                  widget.resultAllowed(result.url)) {
                                Clipboard.setData(
                                  ClipboardData(text: result.url.toString()),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Result link copied'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy_outlined, size: 18),
                            label: const Text('Copy link'),
                          ),
                          const Divider(),
                        ],
                      ),
                    ),
                  if (model.moreAvailable)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        key: const ValueKey('search-more'),
                        onPressed: model.loading
                            ? null
                            : () {
                                if (widget.canContinue()) model.more();
                              },
                        child: const Text('More results'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    model.fixture
                        ? 'Synthetic fixture · Brave response contract'
                        : 'Results provided by Brave Search',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Search privacy & protection'),
                    children: [
                      const Text(
                        'Your submitted query goes through Wingman’s gateway to Brave. Wingman does not save query history or send typed suggestions. Brave’s standard API notice permits query retention for up to 90 days; the words you submit may identify you.',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Strict provider filtering and Wingman’s query, result and destination checks are always applied. Filtering can miss content. A listed destination is not verified safe. Result previews do not load publisher images or trackers.',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        kIsWeb
                            ? 'Opening a result leaves this companion for your host browser. Wingman cannot filter other browser tabs.'
                            : 'Selected links open through Wingman’s existing native destination protection. Websites receive ordinary connection information when visited.',
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}
