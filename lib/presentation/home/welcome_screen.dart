import 'package:flutter/material.dart';
import '../components/wingman_components.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onComplete});
  final Future<void> Function() onComplete;
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _busy = false;
  String? _error;
  Future<void> _finish() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onComplete();
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Your welcome preference could not be saved. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => WingmanPage(
    title: 'Welcome',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WingmanBrand(markSize: 56),
        const SizedBox(height: 32),
        Text(
          "We've got your back, not your data.",
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 20),
        const Text(
          'A calmer place to learn, plan and finish what matters. No account is required.',
        ),
        const SizedBox(height: 24),
        const WingmanStatus(
          title: 'Protection is part of Wingman',
          message:
              'Explore the offline library and local tools. Native Wingman opens ordinary websites with mandatory category and security filters. DuckDuckGo Strict adult filtering is required; search previews and changing pages can contain misses. The web companion opens searches in your host browser and cannot control it after navigation.',
        ),
        const SizedBox(height: 20),
        const Text(
          'Spaces, task notes and saved findings stay on this device. Private sessions keep their tools in memory and separate from normal saved activity.',
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _finish,
          child: Text(_busy ? 'Saving…' : 'Get started'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          WingmanStatus(
            title: 'Welcome not completed',
            message: _error!,
            tone: WingmanTone.caution,
          ),
        ],
      ],
    ),
  );
}
