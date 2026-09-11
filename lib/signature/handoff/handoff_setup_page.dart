import 'package:flutter/material.dart';
import 'handoff_controller.dart';
import 'handoff_gate.dart' show HandoffKeypad, handoffAttemptMessage;

/// Owner-only page. Root passes a freshly minted preview containing only exact
/// eligible bundled records. It cannot accept URLs or arbitrary page state.
class HandoffSetupPage extends StatefulWidget {
  const HandoffSetupPage({
    super.key,
    required this.controller,
    required this.preview,
  });
  final HandoffController controller;
  final HandoffPreview preview;
  @override
  State<HandoffSetupPage> createState() => _HandoffSetupPageState();
}

class _HandoffSetupPageState extends State<HandoffSetupPage>
    with WidgetsBindingObserver {
  int _step = 0;
  String _code = '', _confirmation = '', _message = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      widget.controller.interrupt();
      setState(() {
        _code = '';
        _confirmation = '';
        if (_step > 1) _step = 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Hand It Over')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_step == 0) ...[
                  Text(
                    'Preview exactly what you will share',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This version shares only the reviewed text below. It does '
                    'not open a website or copy a login, form, cookie, note, '
                    'bookmark, history item or other tab. The guest can read '
                    'these articles and ask to return to the owner.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'You will create a fresh 8–12 digit owner-return code. Keep '
                    'it to yourself. Restarting, going back or opening a link '
                    'will not end the session. There is no forgotten-code '
                    'bypass inside Wingman. This is not a device-wide kiosk; '
                    'other apps remain outside Wingman’s control.',
                  ),
                  const SizedBox(height: 24),
                  for (final resource in widget.preview.resources) ...[
                    Text(
                      resource.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(resource.body),
                    const SizedBox(height: 24),
                  ],
                  FilledButton(
                    key: const ValueKey('handoff-preview-confirm'),
                    onPressed: () => setState(() => _step = 1),
                    child: const Text('Share this text · set owner code'),
                  ),
                ] else ...[
                  Text(
                    _step == 1
                        ? 'Create an owner-return code'
                        : 'Confirm your code',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Use 8–12 digits that the guest does not know. This code '
                    'only returns to your Wingman session. It never changes '
                    'content protection.',
                  ),
                  const SizedBox(height: 24),
                  HandoffKeypad(
                    count: (_step == 1 ? _code : _confirmation).length,
                    enabled: !_busy,
                    onDigit: (digit) => setState(() {
                      if (_step == 1 && _code.length < 12) _code += digit;
                      if (_step == 2 && _confirmation.length < 12) {
                        _confirmation += digit;
                      }
                    }),
                    onDelete: () => setState(() {
                      if (_step == 1 && _code.isNotEmpty) {
                        _code = _code.substring(0, _code.length - 1);
                      } else if (_step == 2 && _confirmation.isNotEmpty) {
                        _confirmation = _confirmation.substring(
                          0,
                          _confirmation.length - 1,
                        );
                      }
                    }),
                  ),
                  if (_message.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(_message),
                  ],
                  const SizedBox(height: 16),
                  if (_busy)
                    const Center(child: CircularProgressIndicator())
                  else
                    FilledButton(
                      key: const ValueKey('handoff-code-confirm'),
                      onPressed: (_step == 1 ? _code : _confirmation).length < 8
                          ? null
                          : _step == 1
                          ? () => setState(() => _step = 2)
                          : _activate,
                      child: Text(
                        _step == 1 ? 'Continue' : 'Start Hand It Over',
                      ),
                    ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _step = 0;
                            _code = '';
                            _confirmation = '';
                            _message = '';
                          }),
                    child: const Text('Back to preview'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _activate() async {
    setState(() => _busy = true);
    final result = await widget.controller.activate(
      preview: widget.preview,
      code: _code,
      confirmation: _confirmation,
    );
    _code = '';
    _confirmation = '';
    if (!mounted) return; // The root gate replaces the entire owner navigator.
    setState(() {
      _busy = false;
      if (!result.success) {
        _step = 1;
        _message = handoffAttemptMessage(result);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _code = '';
    _confirmation = '';
    super.dispose();
  }
}
