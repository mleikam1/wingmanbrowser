import 'package:flutter/material.dart';
import '../components/wingman_components.dart';
import '../browser_shell.dart' show safeTextContextMenu;

const launchpadIcons = <String, IconData>{
  'link': Icons.link,
  'book': Icons.menu_book_outlined,
  'science': Icons.science_outlined,
  'sports': Icons.sports_basketball_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'tools': Icons.build_outlined,
  'home': Icons.home_outlined,
  'star': Icons.star_border,
  'folder': Icons.folder_outlined,
  'globe': Icons.language,
  'school': Icons.school_outlined,
  'receipt': Icons.receipt_long_outlined,
  'checklist': Icons.checklist,
};

/// Bundled Material symbols or bounded text. This widget never fetches artwork.
class LaunchpadIcon extends StatelessWidget {
  const LaunchpadIcon({super.key, required this.iconKey, this.size = 48});
  final String iconKey;
  final double size;
  @override
  Widget build(BuildContext context) {
    final colors = WingmanTokens.of(context);
    final initials = RegExp(r'^initials:[A-Z0-9]{1,2}$').hasMatch(iconKey)
        ? iconKey.substring(9)
        : null;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.raised,
          borderRadius: BorderRadius.circular(14),
        ),
        child: initials == null
            ? Icon(
                launchpadIcons[iconKey] ?? Icons.link,
                color: colors.action,
                size: size / 2,
              )
            : Text(
                initials,
                style: TextStyle(
                  fontSize: size / 2.5,
                  fontWeight: FontWeight.w700,
                  color: colors.action,
                ),
              ),
      ),
    );
  }
}

class LaunchpadIconPicker extends StatelessWidget {
  const LaunchpadIconPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in launchpadIcons.entries)
            Semantics(
              selected: value == entry.key,
              child: IconButton.filledTonal(
                tooltip: '${entry.key} icon',
                isSelected: value == entry.key,
                onPressed: enabled ? () => onChanged(entry.key) : null,
                icon: Icon(entry.value),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: ValueKey(value.startsWith('initials:') ? 'initials' : value),
        initialValue: value.startsWith('initials:') ? value.substring(9) : '',
        enabled: enabled,
        maxLength: 2,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        contextMenuBuilder: safeTextContextMenu,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
          labelText: 'Or use initials',
          helperMaxLines: 8,
          helperText:
              'One or two letters A–Z or numbers. No artwork is downloaded.',
        ),
        onChanged: (text) {
          final initials = text.toUpperCase();
          if (RegExp(r'^[A-Z0-9]{1,2}$').hasMatch(initials)) {
            onChanged('initials:$initials');
          }
        },
      ),
    ],
  );
}
