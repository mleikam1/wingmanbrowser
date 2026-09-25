import 'package:flutter/material.dart';
import 'wingman_components.dart';

Future<String?> showFocusNudge(
  BuildContext context, {
  required String goal,
  required String site,
  required bool canSave,
  required Listenable changes,
  required bool Function() canContinue,
}) => showWingmanSheet<String>(
  context: context,
  builder: (sheet) => ListenableBuilder(
    listenable: changes,
    builder: (context, _) {
      if (!canContinue()) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('This tab has changed. The previous task is hidden.'),
              TextButton(
                onPressed: () => Navigator.pop(sheet),
                child: const Text('Close reminder'),
              ),
            ],
          ),
        );
      }
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          24 + MediaQuery.viewInsetsOf(sheet).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'A moment for your goal',
                    style: Theme.of(sheet).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss focus reminder',
                  onPressed: () => Navigator.pop(sheet),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(goal, style: Theme.of(sheet).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              'You chose $site as a distraction. This permitted destination is a focus preference; core protection still applies.',
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  onPressed: () => Navigator.pop(sheet, 'task'),
                  child: const Text('Back to task'),
                ),
                if (canSave)
                  OutlinedButton(
                    onPressed: () => Navigator.pop(sheet, 'save'),
                    child: const Text('Save for later'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(sheet, 'continue'),
                  child: const Text('Continue'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Dismissing or choosing Continue silences this site for this task session. Mandatory denials cannot be dismissed.',
            ),
          ],
        ),
      );
    },
  ),
);
