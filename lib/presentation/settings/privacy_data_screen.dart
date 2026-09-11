import 'package:flutter/material.dart';
import '../../state/browser_state.dart';
import '../components/wingman_components.dart';
import 'settings_actions.dart';
export 'settings_actions.dart' show PrivacyDataCategory, DataClearOutcome;

class PrivacyDataScreen extends StatefulWidget {
  const PrivacyDataScreen({
    super.key,
    required this.state,
    required this.isPrivate,
    required this.canContinue,
    required this.actions,
  });
  final BrowserState state;
  final bool isPrivate;
  final bool Function() canContinue;
  final SettingsActions actions;
  @override
  State<PrivacyDataScreen> createState() => _PrivacyDataScreenState();
}

class _PrivacyDataScreenState extends State<PrivacyDataScreen>
    with WidgetsBindingObserver {
  final Set<PrivacyDataCategory> _selected = {};
  bool _busy = false, _foreground = true;
  DataClearOutcome? _outcome;
  String? _error;
  Future<DataClearOutcome>? _pendingFuture;
  Set<PrivacyDataCategory> get _available => widget.actions.clearableCategories
      .where(
        (c) =>
            !widget.isPrivate ||
            c == PrivacyDataCategory.session ||
            c == PrivacyDataCategory.trustReceipt,
      )
      .toSet();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watchPending();
  }

  void _watchPending() {
    final pending = widget.actions.pendingDataClear?.call();
    if (pending == null) {
      if (_outcome?.pending == true) {
        setState(() {
          _outcome = null;
          _error =
              'The earlier operation is no longer pending, but this screen did not receive its completion result. No success is assumed.';
        });
      }
      return;
    }
    if (identical(pending, _pendingFuture)) return;
    _pendingFuture = pending;
    setState(() {
      _outcome = DataClearOutcome(pending: true);
      _error = null;
    });
    pending.then(
      (result) {
        if (!mounted || !identical(_pendingFuture, pending)) return;
        setState(() {
          _outcome = result;
          _error = result.failed.isEmpty
              ? null
              : 'Some selected data could not be cleared. Completed categories are listed below; no success is assumed for the others.';
        });
      },
      onError: (Object _) {
        if (!mounted || !identical(_pendingFuture, pending)) return;
        setState(() {
          _outcome = null;
          _error = 'The pending deletion failed. No completion is claimed.';
        });
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed);
    }
  }

  bool get _current =>
      mounted &&
      _foreground &&
      widget.canContinue() &&
      (ModalRoute.of(context)?.isCurrent ?? false);
  Future<void> _clear() async {
    if (_busy || _outcome?.pending == true || !_current || _selected.isEmpty) {
      return;
    }
    final chosen = Set<PrivacyDataCategory>.unmodifiable(
      _selected.intersection(_available),
    );
    if (chosen.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Clear selected data?'),
        scrollable: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final category in chosen)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  '${category.label}\n${category.explanation(isPrivate: widget.isPrivate)}',
                ),
              ),
            const Text(
              'This cannot erase exported copies, device backups, completed files or data held by other apps.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep data'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Clear selected'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_current) return;
    setState(() {
      _busy = true;
      _outcome = null;
      _error = null;
    });
    try {
      final result =
          await (widget.actions.onClearDataScoped?.call(
                chosen,
                () => _current,
              ) ??
              widget.actions.onClearData(chosen));
      if (mounted) {
        setState(() {
          _outcome = result;
          if (!result.pending && !result.completed.containsAll(chosen)) {
            _error =
                'Some selected data could not be cleared. Completed categories are listed below; no success is assumed for the others.';
          }
        });
      }
      if (result.pending && mounted) _watchPending();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Clearing could not be confirmed. Your selection is preserved; a pending native operation may still need to finish.',
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
      title: 'Privacy & data',
      child: !widget.canContinue()
          ? const WingmanEmptyState(
              icon: Icons.visibility_off_outlined,
              title: 'Session unavailable',
              message:
                  'Local data is hidden after its originating session closes.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const WingmanStatus(
                  title: 'Local by default',
                  message:
                      'No advertising, analytics, account sign-in or cloud-analysis SDK is active. A device or host browser can use its own services; Wingman does not claim universal network silence.',
                  tone: WingmanTone.info,
                ),
                const SizedBox(height: 20),
                Text(
                  widget.isPrivate
                      ? 'Private tools and activity stay in this session. Normal library data and quarantine counts are hidden here.'
                      : 'Reviewed bookmarks and reading state stay in local storage. Notes, tasks and saved findings are deleted within their tools. The Trust Receipt retains up to 200 typed events for 14 days; closed apps cannot run retention cleanup.',
                ),
                const SizedBox(height: 16),
                if (!widget.isPrivate) ...[
                  Text(
                    '${widget.state.protectedPreferences.bookmarkedIds.length} reviewed bookmarks · ${widget.state.protectedPreferences.readingIds.length} reading-list items',
                  ),
                  Text(
                    '${widget.state.quarantined.history} earlier history records quarantined. Titles and addresses are not displayed.',
                  ),
                ],
                const SizedBox(height: 20),
                const WingmanSection(title: 'Choose what to clear'),
                for (final category in PrivacyDataCategory.values)
                  if (_available.contains(category))
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(category.label),
                      subtitle: Text(
                        category.explanation(isPrivate: widget.isPrivate),
                      ),
                      value: _selected.contains(category),
                      onChanged: _busy || _outcome?.pending == true
                          ? null
                          : (v) => setState(() {
                              v == true
                                  ? _selected.add(category)
                                  : _selected.remove(category);
                              _outcome = null;
                              _error = null;
                            }),
                    ),
                if (_available.isEmpty)
                  const Text(
                    'No clearing action is available in this context.',
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed:
                      _busy || _selected.isEmpty || _outcome?.pending == true
                      ? null
                      : _clear,
                  child: Text(_busy ? 'Clearing…' : 'Review selected data'),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
                if (_outcome?.pending == true)
                  const WingmanStatus(
                    title: 'Deletion still pending',
                    message:
                        'A native deletion has not completed. No completion is claimed; another selection cannot replace the pending operation.',
                    tone: WingmanTone.caution,
                  ),
                if (_error != null)
                  WingmanStatus(
                    title: 'Not fully cleared',
                    message: _error!,
                    tone: WingmanTone.caution,
                  ),
                if (_outcome?.completed.isNotEmpty == true)
                  WingmanStatus(
                    title: 'Cleared',
                    message: _outcome!.completed.map((c) => c.label).join('\n'),
                    tone: WingmanTone.success,
                  ),
                const SizedBox(height: 24),
                const Text(
                  'Live website storage, new downloads and browsing history are not created by this offline-library build. Completed legacy download files are preserved. Exported receipts and reports are outside Wingman’s deletion boundary.',
                ),
                TextButton(
                  onPressed: () {
                    if (widget.canContinue()) widget.actions.onReceipt();
                  },
                  child: const Text('Open Trust Receipt'),
                ),
              ],
            ),
    ),
  );
}
