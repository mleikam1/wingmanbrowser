import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../presentation/app_route_observer.dart';
import '../../presentation/components/wingman_components.dart';
import '../privacy/privacy_journal.dart';

/// A user-written local draft, never an approval or an outgoing submission.
class LocalReviewRequest {
  const LocalReviewRequest._(this.domain, this.reason);
  final String domain, reason;
  static const maximumReasonLength = 500;

  factory LocalReviewRequest.parse(String domain, String reason) {
    final host = domain.trim().toLowerCase();
    final labels = host.split('.');
    const reserved = {
      'localhost',
      'local',
      'internal',
      'invalid',
      'test',
      'example',
      'onion',
      'home',
      'lan',
      'corp',
    };
    if (host.length > 253 ||
        labels.length < 2 ||
        !RegExp(r'^[a-z0-9.-]+$').hasMatch(host) ||
        !RegExp(r'^[a-z]{2,63}$').hasMatch(labels.last) ||
        reserved.contains(labels.last) ||
        labels.any(
          (label) =>
              label.isEmpty ||
              label.length > 63 ||
              label.startsWith('-') ||
              label.endsWith('-') ||
              label.startsWith('xn--'),
        )) {
      throw const FormatException(
        'Enter a public domain only, such as mozilla.org. Addresses, paths, account details, IP addresses and internationalized names are not supported.',
      );
    }
    final note = reason.trim();
    if (note.length > maximumReasonLength ||
        utf8.encode(note).length > 2000 ||
        RegExp(r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]').hasMatch(note) ||
        RegExp(r'://|www\.|@', caseSensitive: false).hasMatch(note)) {
      throw const FormatException(
        'Use a short, single-line reason without web addresses, email addresses or hidden control characters. Leave out personal details.',
      );
    }
    return LocalReviewRequest._(host, note);
  }

  String toText() => [
    'Wingman content review request — local draft',
    'Not submitted. No review service is connected.',
    'User-entered domain: $domain',
    'Reason: ${reason.isEmpty ? "Not provided" : reason}',
    'The domain has not been verified by this draft.',
    'This request does not approve content or change permanent protection.',
  ].join('\n');
}

class RequestReviewScreen extends StatefulWidget {
  const RequestReviewScreen({
    super.key,
    required this.journal,
    this.isPrivate = false,
    this.canContinue,
    this.copyText,
  });
  final PrivacyJournal journal;
  final bool isPrivate;
  final bool Function()? canContinue;
  final Future<void> Function(String)? copyText;

  @override
  State<RequestReviewScreen> createState() => _RequestReviewScreenState();
}

class _RequestReviewScreenState extends State<RequestReviewScreen>
    with WidgetsBindingObserver, RouteAware {
  final _domain = TextEditingController(), _reason = TextEditingController();
  LocalReviewRequest? _preview;
  String? _error, _outcome;
  bool _visible = true, _copying = false;
  int _generation = 0;
  ModalRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) appRouteObserver.subscribe(this, route);
    }
  }

  void _invalidate() {
    _generation++;
    if (mounted) {
      setState(() {
        _preview = null;
        _outcome = null;
      });
    }
  }

  @override
  void didPushNext() => _invalidate();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    if (!_visible) _invalidate();
    if (mounted) setState(() {});
  }

  bool _current(int generation) =>
      mounted &&
      _visible &&
      generation == _generation &&
      (_route?.isCurrent ?? true) &&
      (widget.canContinue?.call() ?? true);

  void _prepare() {
    FocusScope.of(context).unfocus();
    if (!_current(_generation)) return;
    try {
      final request = LocalReviewRequest.parse(_domain.text, _reason.text);
      setState(() {
        _preview = request;
        _error = null;
        _outcome = null;
      });
      widget.journal.record(
        PrivacyActivity.reviewRequestPrepared,
        PrivacyOutcome.completed,
      );
    } on FormatException catch (error) {
      setState(() {
        _preview = null;
        _error = error.message;
      });
    }
  }

  Future<void> _copy() async {
    final preview = _preview, generation = _generation;
    if (_copying || preview == null || !_current(generation)) return;
    final text = preview.toText();
    final token = widget.journal.begin(
      PrivacyActivity.reviewRequestExported,
      destination: PrivacyDestination.clipboard,
    );
    setState(() {
      _copying = true;
      _error = null;
      _outcome = null;
    });
    try {
      await (widget.copyText ??
          (text) => Clipboard.setData(ClipboardData(text: text)))(text);
      final current = _current(generation);
      widget.journal.finish(
        token,
        current ? PrivacyOutcome.completed : PrivacyOutcome.interrupted,
      );
      if (current) {
        setState(
          () => _outcome =
              'Copied to the device clipboard. Nothing was submitted.',
        );
      }
    } catch (_) {
      widget.journal.finish(token, PrivacyOutcome.failed);
      if (_current(generation)) {
        setState(
          () => _error = 'Copy could not be confirmed. Nothing was submitted.',
        );
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _domain.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WingmanPage(
    title: 'Request a review',
    child: !_visible || !(widget.canContinue?.call() ?? true)
        ? const WingmanStatus(
            title: 'Draft hidden',
            message: 'Return to Wingman to continue.',
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Suggest a useful destination.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Prepare a short request on this device. A review service is not connected, and this draft cannot unlock a website.',
              ),
              const SizedBox(height: 20),
              WingmanStatus(
                title: widget.isPrivate
                    ? 'Temporary private draft'
                    : 'Local draft only',
                message:
                    'No address has been filled in for you. Nothing is sent or saved. Copying is optional and moves the exact preview below to the device clipboard.',
              ),
              const WingmanSection(title: 'What would you like reviewed?'),
              TextField(
                key: const Key('review-domain'),
                controller: _domain,
                maxLength: 253,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                contextMenuBuilder: _localMenu,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Public domain',
                  hintText: 'mozilla.org',
                ),
                onChanged: (_) {
                  _invalidate();
                  setState(() => _error = null);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('review-reason'),
                controller: _reason,
                maxLength: LocalReviewRequest.maximumReasonLength,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                contextMenuBuilder: _localMenu,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  hintText: 'What public information would help?',
                ),
                onChanged: (_) {
                  _invalidate();
                  setState(() => _error = null);
                },
              ),
              const Text(
                'Leave out names, private paths, search terms, account information and personal circumstances. The draft does not verify domain ownership or remove every kind of sensitive information.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _copying ? null : _prepare,
                icon: const Icon(Icons.preview_outlined),
                label: const Text('Preview local request'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                WingmanStatus(
                  title: 'Check your draft',
                  message: _error!,
                  tone: WingmanTone.caution,
                ),
              ],
              if (_preview != null) ...[
                const WingmanSection(title: 'Exact export preview'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _preview!.toText(),
                      key: const Key('review-preview'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const WingmanStatus(
                  title: 'Before you copy',
                  message:
                      'Other apps or a device clipboard sync service may read copied text. Review every line. Wingman does not choose a recipient or submit the request.',
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _copying ? null : _copy,
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(_copying ? 'Copying…' : 'Copy reviewed request'),
                ),
              ],
              if (_outcome != null) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: WingmanStatus(
                    title: 'Draft copied',
                    message: _outcome!,
                  ),
                ),
              ],
            ],
          ),
  );
}

Widget _localMenu(BuildContext context, EditableTextState state) =>
    AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: state.contextMenuButtonItems
          .where(
            (item) => const {
              ContextMenuButtonType.cut,
              ContextMenuButtonType.copy,
              ContextMenuButtonType.paste,
              ContextMenuButtonType.selectAll,
            }.contains(item.type),
          )
          .toList(),
    );
