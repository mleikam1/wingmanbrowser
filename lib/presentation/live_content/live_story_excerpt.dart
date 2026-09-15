import 'package:flutter/material.dart';

import '../components/wingman_components.dart';

/// Visual ellipsis preserves the original permitted publisher text in semantics
/// and the existing story-details view; this component never rewrites a summary.
class LiveStoryExcerpt extends StatelessWidget {
  const LiveStoryExcerpt({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      semanticsLabel: 'Publisher excerpt: $text',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        height: 1.4,
        color: WingmanTokens.of(context).secondaryText,
      ),
    ),
  );
}
