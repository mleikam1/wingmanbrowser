import 'package:flutter/material.dart';

import '../../live_content/branding.dart';
import '../components/wingman_components.dart';

/// A publisher name always accompanies its reviewed logo. The monochrome
/// initials fallback is explicitly a neutral identifier, never a claimed logo.
class LivePublisherIdentity extends StatelessWidget {
  const LivePublisherIdentity({
    super.key,
    required this.name,
    this.branding,
    this.sponsored = false,
    this.now,
  });

  final String name;
  final PublisherBranding? branding;
  final bool sponsored;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = WingmanTokens.of(context);
    final approved = branding?.isCurrent(now ?? DateTime.now()) == true
        ? branding
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (approved == null)
              _InitialsBadge(name: name)
            else
              SizedBox(
                width: 42,
                height: 30,
                child: Image.asset(
                  approved.assetFor(dark: theme.brightness == Brightness.dark),
                  key: ValueKey('publisher-logo-${approved.asset}'),
                  fit: BoxFit.contain,
                  semanticLabel: '$name logo',
                  errorBuilder: (_, _, _) => _InitialsBadge(name: name),
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                sponsored ? 'Sponsored feature · $name' : name,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.action,
                ),
              ),
            ),
          ],
        ),
        if (approved != null &&
            approved.credit.isNotEmpty &&
            approved.credit != name)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(approved.credit, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _InitialsBadge extends StatelessWidget {
  const _InitialsBadge({required this.name});
  final String name;

  String get initials {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where(
          (word) => word.characters.any(
            (character) =>
                RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(character),
          ),
        )
        .toList();
    if (words.isEmpty) return '?';
    return (words.length == 1
            ? words.first.characters.take(2).toString()
            : '${words.first.characters.first}${words[1].characters.first}')
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WingmanTokens.of(context);
    return Semantics(
      label: 'Neutral publisher initials for $name',
      child: ExcludeSemantics(
        child: Container(
          key: ValueKey('publisher-initials-$name'),
          width: 32,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.raised,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            initials,
            textScaler: TextScaler.noScaling,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
