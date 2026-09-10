import 'package:flutter/material.dart';

class Omnibox extends StatefulWidget {
  const Omnibox({
    super.key,
    required this.onSubmit,
    this.url = '',
    this.isPrivate = false,
    this.compact = false,
    this.hasPageError = false,
    this.localSuggestions,
    this.searchProvider = 'DuckDuckGo',
  });
  final ValueChanged<String> onSubmit;
  final String url;
  final bool isPrivate;
  final bool compact;
  final bool hasPageError;
  final Iterable<String> Function(String input)? localSuggestions;
  final String searchProvider;
  @override
  State<Omnibox> createState() => _OmniboxState();
}

class _OmniboxState extends State<Omnibox> {
  late final TextEditingController controller = TextEditingController(
    text: widget.url,
  );
  final focus = FocusNode();
  final scroll = ScrollController();
  bool _selectionSubmitted = false;
  @override
  void initState() {
    super.initState();
    focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!focus.hasFocus) {
      if (widget.url.isNotEmpty) controller.text = widget.url;
      _showAddressStart();
    }
  }

  void _showAddressStart() {
    controller.selection = const TextSelection.collapsed(offset: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !focus.hasFocus && scroll.hasClients) scroll.jumpTo(0);
    });
  }

  @override
  void didUpdateWidget(Omnibox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url && !focus.hasFocus) {
      controller.text = widget.url;
      _showAddressStart();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    scroll.dispose();
    focus.dispose();
    super.dispose();
  }

  void submit(String text) {
    if (text.trim().isEmpty) return;
    focus.unfocus();
    widget.onSubmit(text);
    if (widget.url.isEmpty) controller.clear();
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<String>(
    textEditingController: controller,
    focusNode: focus,
    optionsBuilder: (value) => widget.isPrivate
        ? const <String>[]
        : widget.localSuggestions?.call(value.text) ?? const <String>[],
    onSelected: (value) {
      _selectionSubmitted = true;
      submit(value);
    },
    fieldViewBuilder: (_, _, _, onFieldSubmitted) => _field((text) {
      _selectionSubmitted = false;
      onFieldSubmitted();
      if (!_selectionSubmitted) submit(text);
    }),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width.clamp(240, 600) - 48,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            shrinkWrap: true,
            children: [
              for (final option in options)
                ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: Text(
                    option,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: const Text('On this device'),
                  onTap: () => onSelected(option),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _field(ValueChanged<String> onSubmitted) => TextField(
    key: ValueKey(widget.compact ? 'browser-omnibox' : 'home-omnibox'),
    controller: controller,
    scrollController: scroll,
    focusNode: focus,
    keyboardType: TextInputType.url,
    textInputAction: TextInputAction.go,
    autocorrect: false,
    enableSuggestions: false,
    enableIMEPersonalizedLearning: !widget.isPrivate,
    smartDashesType: SmartDashesType.disabled,
    smartQuotesType: SmartQuotesType.disabled,
    // Keep the edited value until onSubmitted captures it. The default IME
    // completion unfocuses first, which would restore the previous page URL.
    onEditingComplete: () {},
    onTap: () {
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    },
    onSubmitted: onSubmitted,
    decoration: InputDecoration(
      hintText: widget.compact
          ? 'Search or enter address'
          : 'Search or enter a website',
      helperText: widget.compact
          ? null
          : 'Search with ${widget.searchProvider}',
      prefixIcon: Icon(
        widget.hasPageError
            ? Icons.warning_amber_rounded
            : widget.isPrivate
            ? Icons.visibility_off_outlined
            : (widget.url.startsWith('https://')
                  ? Icons.lock_outline
                  : Icons.search_rounded),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 52, minHeight: 48),
      suffixIcon: IconButton(
        tooltip: 'Go',
        icon: const Icon(Icons.arrow_forward_rounded),
        onPressed: () => submit(controller.text),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: widget.compact ? 12 : 22,
      ),
    ),
  );
}
