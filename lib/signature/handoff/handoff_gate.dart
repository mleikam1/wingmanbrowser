import 'package:flutter/material.dart';
import '../../presentation/theme.dart';
import 'handoff_controller.dart';

export 'handoff_controller.dart';
export 'handoff_setup_page.dart';

/// Must sit ABOVE the owner MaterialApp/Navigator. The owner builder is never
/// invoked while gated; there is no offstage owner route under the guest UI.
class HandoffGate extends StatefulWidget {
  const HandoffGate({
    super.key,
    required this.controller,
    required this.ownerBuilder,
  });
  final HandoffController controller;
  final WidgetBuilder ownerBuilder;

  @override
  State<HandoffGate> createState() => _HandoffGateState();
}

class _HandoffGateState extends State<HandoffGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) widget.controller.interrupt();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      if (!widget.controller.blocksOwner) {
        return KeyedSubtree(
          key: const ValueKey('owner-application'),
          child: widget.ownerBuilder(context),
        );
      }
      return MaterialApp(
        key: const ValueKey('handoff-application'),
        title: 'Wingman · Hand It Over',
        debugShowCheckedModeBanner: false,
        theme: WingmanTheme.make(Brightness.light),
        darkTheme: WingmanTheme.make(Brightness.dark),
        // Framework route requests (including restored/deep route names) can
        // only create another copy of the guest screen, never an owner route.
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/handoff'),
          builder: (_) => _GuestPage(controller: widget.controller),
        ),
        // No owner preference or route is read for this separate application.
        home: _GuestPage(controller: widget.controller),
      );
    },
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class _GuestPage extends StatefulWidget {
  const _GuestPage({required this.controller});
  final HandoffController controller;
  @override
  State<_GuestPage> createState() => _GuestPageState();
}

class _GuestPageState extends State<_GuestPage> {
  bool _returning = false;
  int _index = 0;
  String _code = '', _message = '';
  int _revision = -1;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (_revision != controller.lifecycleRevision) {
      _revision = controller.lifecycleRevision;
      _code = '';
      _message = '';
    }
    final resources = controller.visibleResources;
    final resource = resources.isEmpty
        ? null
        : resources[_index.clamp(0, resources.length - 1)];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          controller.interrupt();
          setState(() {
            _returning = false;
            _code = '';
          });
        }
      },
      child: Scaffold(
        key: const ValueKey('handoff-guest'),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(_returning ? 'Owner return' : 'Shared view', maxLines: 2),
          toolbarHeight: handoffAppBarHeight(context),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: EdgeInsets.all(
                  MediaQuery.sizeOf(context).width < 360 ? 16 : 24,
                ),
                children: [
                  HandoffScopeNote(
                    icon: Icons.lock_outline_rounded,
                    title: 'Static read-only sharing',
                    message:
                        'Only the owner-selected reviewed text is available. '
                        'Other Wingman content stays out of reach. '
                        'This does not lock the device or other apps.',
                  ),
                  if (controller.canAuthenticate && !_returning) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      key: const ValueKey('handoff-return'),
                      onPressed: () => setState(() => _returning = true),
                      icon: const Icon(Icons.lock_open_rounded),
                      label: const Text('Return to owner'),
                    ),
                  ],
                  const SizedBox(height: 28),
                  if (controller.status == HandoffStatus.loading) ...[
                    const HandoffProgress(message: 'Securing the handoff…'),
                  ] else if (_returning && controller.canAuthenticate) ...[
                    Text(
                      'Enter the owner-return code',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter your fresh 8–12 digit code. The shared view stays locked until return is confirmed.',
                    ),
                    const SizedBox(height: 24),
                    HandoffKeypad(
                      count: _code.length,
                      enabled: !controller.busy,
                      onDigit: (digit) {
                        if (_code.length < 12) {
                          setState(() => _code += digit);
                        }
                      },
                      onDelete: () {
                        if (_code.isNotEmpty) {
                          setState(
                            () => _code = _code.substring(0, _code.length - 1),
                          );
                        }
                      },
                    ),
                    if (_message.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: HandoffScopeNote(
                          key: const ValueKey('handoff-error'),
                          icon: Icons.info_outline_rounded,
                          title: 'Owner content stays locked',
                          message: _message,
                        ),
                      ),
                    FilledButton(
                      key: const ValueKey('handoff-unlock'),
                      onPressed: _code.length >= 8 && !controller.busy
                          ? _unlock
                          : null,
                      child: const Text('Authenticate and return'),
                    ),
                    TextButton(
                      onPressed: () {
                        controller.interrupt();
                        setState(() {
                          _returning = false;
                          _code = '';
                        });
                      },
                      child: const Text('Keep sharing'),
                    ),
                  ] else if (controller.busy) ...[
                    HandoffProgress(
                      message: controller.returnAuthorized
                          ? 'Finishing authenticated return…'
                          : 'Checking the owner-return code…',
                    ),
                  ] else if (resource == null) ...[
                    HandoffScopeNote(
                      icon: Icons.lock_outline_rounded,
                      title: 'Shared view unavailable',
                      message: controller.status == HandoffStatus.unavailable
                          ? controller.returnUnconfirmed
                                ? 'Your code was verified, but storage did not '
                                      'confirm the return. Owner content is hidden '
                                      'here. Reopening Wingman may finish an already '
                                      'authorized return if its write completes.'
                                : 'Owner content remains locked. Secure storage could '
                                      'not confirm the handoff state. Close and reopen '
                                      'Wingman to retry; no owner data was erased.'
                          : 'This shared content is currently unavailable. '
                                'Its approval may have changed or expired. '
                                'The owner-return code is still required.',
                      key: const ValueKey('handoff-unavailable'),
                    ),
                  ] else ...[
                    Text(
                      'REVIEWED TEXT · ${_index + 1} OF ${resources.length}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      resource.title,
                      key: ValueKey('handoff-title-${resource.id}'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    // Plain Text intentionally has no text selection, links,
                    // image loading, input/autofill, context menu or HTML parser.
                    Text(
                      resource.body,
                      key: ValueKey('handoff-body-${resource.id}'),
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(height: 1.6),
                    ),
                    if (resources.length > 1) ...[
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          OutlinedButton(
                            onPressed: _index > 0
                                ? () => setState(() => --_index)
                                : null,
                            child: const Text('Previous article'),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text('${_index + 1} of ${resources.length}'),
                          ),
                          OutlinedButton(
                            onPressed: _index < resources.length - 1
                                ? () => setState(() => ++_index)
                                : null,
                            child: const Text('Next article'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _unlock() async {
    final code = _code;
    setState(() {
      _code = '';
      _message = '';
    });
    final result = await widget.controller.unlock(code);
    if (!mounted || result.success) return;
    setState(() => _message = handoffAttemptMessage(result));
  }

  @override
  void dispose() {
    _code = '';
    super.dispose();
  }
}

/// No EditableText/TextInput connection, OS keyboard, paste, selection, autofill
/// hints or password-manager session is created. Screen readers see digit keys
/// and entered count, never the stored entered code.
class HandoffKeypad extends StatelessWidget {
  const HandoffKeypad({
    super.key,
    required this.count,
    required this.enabled,
    required this.onDigit,
    required this.onDelete,
  });
  final int count;
  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        children: [
          Semantics(
            label: '$count digits entered',
            child: ExcludeSemantics(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: count == 0
                    ? Text(
                        'Enter 8–12 digits',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      )
                    : Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(
                          count,
                          (_) => Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.onSurface,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['', '0', 'delete'],
          ])
            Row(
              children: row.map((digit) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: digit.isEmpty
                        ? const SizedBox(height: 56)
                        : OutlinedButton(
                            key: ValueKey('handoff-key-$digit'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(56, 60),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: !enabled
                                ? null
                                : digit == 'delete'
                                ? onDelete
                                : () => onDigit(digit),
                            child: digit == 'delete'
                                ? const Icon(
                                    Icons.backspace_outlined,
                                    semanticLabel: 'Delete digit',
                                  )
                                : Text(
                                    digit,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                          ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    ),
  );
}

double handoffAppBarHeight(BuildContext context) =>
    (MediaQuery.textScalerOf(context).scale(28) *
            (MediaQuery.sizeOf(context).width < 400 ? 2 : 1.5))
        .clamp(kToolbarHeight, double.infinity);

/// Local, opaque explanatory surface. It contains no owner data or actions.
class HandoffScopeNote extends StatelessWidget {
  const HandoffScopeNote({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title, message;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(message, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    ),
  );
}

class HandoffProgress extends StatelessWidget {
  const HandoffProgress({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          if (MediaQuery.disableAnimationsOf(context))
            const Icon(Icons.hourglass_empty_rounded)
          else
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(),
            ),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

String handoffAttemptMessage(
  HandoffAttempt attempt,
) => switch (attempt.result) {
  HandoffResult.success => '',
  HandoffResult.invalidCode => 'Use 8–12 digits for the owner-return code.',
  HandoffResult.confirmationMismatch => 'The codes did not match. Try again.',
  HandoffResult.incorrectCode =>
    'That code did not match. Owner content stays locked.',
  HandoffResult.rateLimited =>
    'Too many attempts. Wait before trying again. The wait also applies after restarting Wingman.',
  HandoffResult.ineligible =>
    'The selected text is no longer eligible for sharing.',
  HandoffResult.canceled =>
    'Authentication was interrupted. Enter the code again.',
  HandoffResult.unavailable =>
    'Secure storage did not confirm the operation. Owner content is hidden here. Close and reopen Wingman to recheck its saved state.',
};
