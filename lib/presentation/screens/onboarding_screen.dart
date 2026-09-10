import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/brand.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.onContinue});
  final VoidCallback onContinue;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const WingmanWordmark(large: true),
                const SizedBox(height: 56),
                Text(
                  "We've got your back,\nnot your data.",
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.5,
                    height: 1.16,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  kIsWeb
                      ? 'A calmer start to your web. The Wingman mobile app brings the same care to a full browser.'
                      : 'Meet your everyday browser. Fast to get around. Thoughtful about what stays yours.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 28),
                const _Promise(
                  Icons.devices_outlined,
                  'Your history stays local by default.',
                ),
                const _Promise(
                  Icons.shield_outlined,
                  'We don’t sell browsing history or build ad profiles from the sites you visit.',
                ),
                const _Promise(
                  Icons.favorite_border,
                  'Disclosed ads and partnerships on Wingman surfaces can fund the browser.',
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onContinue,
                    child: const Text('Let’s explore'),
                  ),
                ),
                const SizedBox(height: 14),
                const Center(
                  child: Text('No account. No permissions to get started.'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Promise extends StatelessWidget {
  const _Promise(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 23, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 14),
        Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
      ],
    ),
  );
}
