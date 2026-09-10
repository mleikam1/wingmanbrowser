import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ClearBrowsingDataDialog extends StatefulWidget {
  const ClearBrowsingDataDialog({super.key});
  @override
  State<ClearBrowsingDataDialog> createState() =>
      _ClearBrowsingDataDialogState();
}

class _ClearBrowsingDataDialogState extends State<ClearBrowsingDataDialog> {
  final selection = <String>{'history'};
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Clear Browsing Data'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Choose what to remove from this device. Clearing site data may sign you out and reload pages. Saved bookmarks remain.',
          ),
          const SizedBox(height: 16),
          for (final item in <String, String>{
            'history': 'Browsing history',
            if (!kIsWeb) ...{
              'cookies': 'Cookies / sign-ins',
              'cache': 'Cached files',
              'storage': 'Site storage and form data',
            },
          }.entries)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.value),
              value: selection.contains(item.key),
              onChanged: (value) => setState(() {
                if (value == true) {
                  selection.add(item.key);
                } else {
                  selection.remove(item.key);
                }
              }),
            ),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            const Text(
              'On Android, clearing site storage also clears cookies and cached files.',
            ),
          if (kIsWeb)
            const Text(
              'To clear data belonging to other websites, use your host browser’s settings.',
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: selection.isEmpty
            ? null
            : () => Navigator.pop(context, selection),
        child: const Text('Clear selected'),
      ),
    ],
  );
}
