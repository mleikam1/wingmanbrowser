import 'package:flutter/material.dart';

class BrowserPageError extends StatelessWidget {
  const BrowserPageError({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onHome,
    this.onBack,
  });
  final String message;
  final VoidCallback onRetry, onHome;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 60,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'A bump in the connection.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 14),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
              TextButton(onPressed: onHome, child: const Text('Return home')),
              if (onBack != null)
                TextButton(onPressed: onBack, child: const Text('Go back')),
            ],
          ),
        ),
      ),
    ),
  );
}
