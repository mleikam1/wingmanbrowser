import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/product_edition.dart';
import '../../policy/policy_runtime.dart';
import '../../state/browser_state.dart';
import '../components/wingman_components.dart';
import 'library_transfer.dart';
export 'library_transfer.dart';

enum LibraryTransferMode { import, export }

class LibraryTransferScreen extends StatefulWidget {
  const LibraryTransferScreen({
    super.key,
    required this.state,
    required this.policy,
    required this.isPrivate,
    required this.canContinue,
    required this.mode,
    this.copyText,
  });
  final BrowserState state;
  final PolicyRuntime policy;
  final bool isPrivate;
  final bool Function() canContinue;
  final LibraryTransferMode mode;
  final Future<void> Function(String)? copyText;
  @override
  State<LibraryTransferScreen> createState() => _LibraryTransferScreenState();
}

class _LibraryTransferScreenState extends State<LibraryTransferScreen>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  ReviewedTransferPreview? _preview;
  String? _export, _message, _error;
  bool _busy = false, _foreground = true;
  int _generation = 0;
  bool get _available =>
      mounted &&
      _foreground &&
      !widget.isPrivate &&
      productEdition == ProductEdition.consumer &&
      widget.canContinue() &&
      (ModalRoute.of(context)?.isCurrent ?? false);
  bool _eligible(String id) => widget.policy.policy
      .evaluate(
        PolicyRequest.bundled(id),
        additional: widget.state.protectedPreferences.additional,
      )
      .isAllowed;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.policy.addListener(_invalidate);
    widget.state.addListener(_invalidate);
  }

  @override
  void dispose() {
    widget.policy.removeListener(_invalidate);
    widget.state.removeListener(_invalidate);
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _invalidate();
  }

  void _invalidate() {
    _generation++;
    if (mounted) {
      setState(() {
        _preview = null;
        _export = null;
        _message = null;
      });
    }
  }

  void _prepare() {
    if (!_available || _busy) return;
    setState(() {
      _preview = null;
      _export = null;
      _message = null;
      _error = null;
    });
    try {
      if (widget.mode == LibraryTransferMode.import) {
        final preview = ReviewedLibraryTransfer.preview(
          _input.text,
          eligible: _eligible,
          existing: widget.state.protectedPreferences.bookmarkedIds,
        );
        setState(() => _preview = preview);
      } else {
        final document = ReviewedLibraryTransfer.export(
          widget.state.protectedPreferences.bookmarkedIds,
          eligible: _eligible,
        );
        setState(() => _export = document);
      }
    } catch (_) {
      setState(
        () => _error =
            'The document could not be prepared. Use the supported format and limits; existing bookmarks are unchanged.',
      );
    }
  }

  Future<void> _commit() async {
    if (!_available || _busy) return;
    final preview = _preview, export = _export, generation = _generation;
    if (widget.mode == LibraryTransferMode.import &&
            (preview == null || preview.acceptedIds.isEmpty) ||
        widget.mode == LibraryTransferMode.export && export == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          widget.mode == LibraryTransferMode.import
              ? 'Merge reviewed bookmarks?'
              : 'Copy reviewed export?',
        ),
        scrollable: true,
        content: Text(
          widget.mode == LibraryTransferMode.import
              ? 'Add ${preview!.acceptedIds.length} reviewed items. Existing bookmarks remain. Eligibility is checked again before saving.'
              : 'The displayed document will be copied to the device clipboard. Resource IDs can reveal your interests; other apps and OS clipboard services may access it. Nothing is submitted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(
              widget.mode == LibraryTransferMode.import
                  ? 'Merge bookmarks'
                  : 'Copy export',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !_available || generation != _generation) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      if (widget.mode == LibraryTransferMode.import) {
        final added = await widget.state.importReviewedBookmarks(
          preview!.acceptedIds,
          isPrivate: widget.isPrivate,
        );
        if (mounted && _available) {
          setState(() {
            _message = '$added reviewed bookmarks added. Nothing was opened.';
            _preview = null;
            _input.clear();
          });
        }
      } else {
        // The reviewed snapshot stays fixed. No clipboard read or external share service.
        if (ReviewedLibraryTransfer.export(
              widget.state.protectedPreferences.bookmarkedIds,
              eligible: _eligible,
            ) !=
            export) {
          throw const FormatException('The reviewed export changed.');
        }
        await (widget.copyText ??
            ((text) => Clipboard.setData(ClipboardData(text: text))))(export!);
        if (mounted && _available) {
          setState(
            () => _message =
                'Copied to the device clipboard. Nothing was submitted.',
          );
        }
      }
    } catch (_) {
      if (mounted && _available) {
        setState(
          () => _error =
              'This operation could not be completed. No success is assumed; review the current data and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => WingmanPage(
    title: widget.mode == LibraryTransferMode.import
        ? 'Import bookmarks'
        : 'Export bookmarks',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isPrivate ||
            !widget.canContinue() ||
            productEdition != ProductEdition.consumer)
          const WingmanEmptyState(
            icon: Icons.lock_outline,
            title: 'Transfer unavailable in this session',
            message:
                'Normal bookmark documents are not exposed from private or Student sessions.',
          )
        else ...[
          const Text(
            'This flow supports Wingman reviewed-resource IDs only. It does not import live addresses, execute content or grant approval. File pickers and external file sharing are unavailable in this build.',
          ),
          const SizedBox(height: 16),
          if (widget.mode == LibraryTransferMode.import)
            TextField(
              key: const ValueKey('reviewed-import-input'),
              controller: _input,
              minLines: 5,
              maxLines: 10,
              maxLength: ReviewedLibraryTransfer.maximumBytes,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              contextMenuBuilder: _localMenu,
              onChanged: (_) => _invalidate(),
              decoration: const InputDecoration(
                labelText: 'Paste a Wingman bookmark document',
                helperText: '512 KiB maximum · No automatic clipboard reading',
                counterText: '',
              ),
            ),
          OutlinedButton(
            onPressed: _busy ? null : _prepare,
            child: const Text('Prepare preview'),
          ),
          if (_preview != null) ...[
            WingmanStatus(
              title: 'Import preview',
              message:
                  '${_preview!.acceptedIds.length} new · ${_preview!.duplicates} duplicate · ${_preview!.rejected} rejected',
              tone: WingmanTone.info,
            ),
            for (final id in _preview!.acceptedIds.take(20))
              Text(widget.policy.resource(id)?.title ?? 'No longer eligible'),
            if (_preview!.acceptedIds.length > 20)
              const Text('Only the first 20 reviewed titles are shown.'),
          ],
          if (_export != null) ...[
            const Text('Review the exact document:'),
            const SizedBox(height: 8),
            Text(_export!, key: const ValueKey('reviewed-export-preview')),
          ],
          if (_preview?.acceptedIds.isNotEmpty == true || _export != null)
            FilledButton(
              onPressed: _busy ? null : _commit,
              child: Text(
                _busy
                    ? 'Working…'
                    : widget.mode == LibraryTransferMode.import
                    ? 'Review merge'
                    : 'Review copy',
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null)
            WingmanStatus(
              title: 'Complete',
              message: _message!,
              tone: WingmanTone.success,
            ),
          if (_error != null)
            WingmanStatus(
              title: 'Not completed',
              message: _error!,
              tone: WingmanTone.caution,
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
