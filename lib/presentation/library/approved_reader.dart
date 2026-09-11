import 'package:flutter/material.dart';
import '../../policy/policy_runtime.dart';
import '../../signature/compatibility/compatibility_profiles.dart';
import '../components/wingman_components.dart';

class ApprovedReader extends StatelessWidget {
  const ApprovedReader({
    super.key,
    required this.resourceId,
    required this.policy,
    required this.compatibilityRegistry,
    required this.additional,
    required this.contentContext,
    required this.isPrivate,
    required this.pageScale,
    required this.onBack,
    this.onScaleChanged,
    this.onBookmark,
    this.onReading,
    this.onCommit,
    this.bookmarked = false,
    this.inReadingList = false,
    this.canContinue,
  });
  final String resourceId;
  final PolicyRuntime policy;
  final CompatibilityProfileRegistry compatibilityRegistry;
  final AdditionalRestrictions additional;
  final ContentContext contentContext;
  final bool isPrivate, bookmarked, inReadingList;
  final int pageScale;
  final VoidCallback onBack;
  final ValueChanged<int>? onScaleChanged;
  final VoidCallback? onBookmark, onReading, onCommit;
  final bool Function()? canContinue;
  bool get _current => canContinue?.call() ?? true;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: policy,
    builder: (context, _) {
      final decision = policy.policy.evaluate(
        PolicyRequest.bundled(
          resourceId,
          context: contentContext,
          isPrivate: isPrivate,
        ),
        additional: additional,
      );
      if (!decision.isAllowed || !_current) {
        return WingmanPage(
          title: 'Reader unavailable',
          onBack: onBack,
          child: const WingmanStatus(
            title: 'This article is not currently eligible',
            message:
                'Its body and title remain hidden. Return to the library to choose available reviewed content.',
            tone: WingmanTone.caution,
          ),
        );
      }
      final resource = policy.resource(resourceId)!;
      return WingmanPage(
        title: 'Reader',
        maxWidth: 760,
        onBack: onBack,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              resource.title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(resource.summary),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!isPrivate && onBookmark != null)
                  OutlinedButton.icon(
                    onPressed: () {
                      if (_current) onBookmark!();
                    },
                    icon: Icon(
                      bookmarked ? Icons.bookmark : Icons.bookmark_border,
                    ),
                    label: Text(bookmarked ? 'Bookmarked' : 'Bookmark'),
                  ),
                if (!isPrivate && onReading != null)
                  OutlinedButton.icon(
                    onPressed: () {
                      if (_current) onReading!();
                    },
                    icon: const Icon(Icons.menu_book_outlined),
                    label: Text(
                      inReadingList ? 'In reading list' : 'Read later',
                    ),
                  ),
                if (onCommit != null)
                  TextButton(
                    onPressed: () {
                      if (_current) onCommit!();
                    },
                    child: const Text('Before You Commit'),
                  ),
              ],
            ),
            if (onScaleChanged != null)
              Row(
                children: [
                  IconButton(
                    tooltip: 'Smaller article text',
                    onPressed: pageScale <= 75
                        ? null
                        : () {
                            if (_current) {
                              onScaleChanged!((pageScale - 25).clamp(75, 200));
                            }
                          },
                    icon: const Icon(Icons.text_decrease),
                  ),
                  Expanded(
                    child: Text(
                      'Article text $pageScale% · Device scaling also applies',
                    ),
                  ),
                  IconButton(
                    tooltip: 'Larger article text',
                    onPressed: pageScale >= 200
                        ? null
                        : () {
                            if (_current) {
                              onScaleChanged!((pageScale + 25).clamp(75, 200));
                            }
                          },
                    icon: const Icon(Icons.text_increase),
                  ),
                ],
              ),
            const SizedBox(height: 24),
            CompatibleReaderText(
              resourceId: resourceId,
              registry: compatibilityRegistry,
              additional: additional,
              context: contentContext,
              isPrivate: isPrivate,
              style: TextStyle(fontSize: 18 * pageScale / 100, height: 1.65),
            ),
            const SizedBox(height: 24),
            const Divider(),
            Text(
              'Reviewed ${resource.reviewedAt.toUtc().toIso8601String().split('T').first} · Expires ${resource.expiresAt.toUtc().toIso8601String().split('T').first}',
            ),
            const SizedBox(height: 12),
            const Text(
              'Original Wingman text, installed with the app. References support the review; they are not approved live destinations.',
            ),
            const SizedBox(height: 8),
            for (final source in resource.sourceUrls)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  source,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const Text(
              'This is the bundled text reader, not website extraction. Live-page Reader, selection sharing and external opening are unavailable.',
            ),
          ],
        ),
      );
    },
  );
}
