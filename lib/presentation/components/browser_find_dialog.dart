import 'package:flutter/material.dart';

/// The route owns its editor until its exit animation has unmounted it.
class BrowserFindDialog extends StatefulWidget {
  const BrowserFindDialog({
    super.key,
    required this.onQuery,
    required this.onNext,
  });

  final ValueChanged<String> onQuery;
  final ValueChanged<bool> onNext;

  @override
  State<BrowserFindDialog> createState() => _BrowserFindDialogState();
}

class _BrowserFindDialogState extends State<BrowserFindDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Find in page'),
    content: TextField(
      controller: _text,
      autofocus: true,
      onChanged: widget.onQuery,
      decoration: const InputDecoration(labelText: 'Text to find'),
    ),
    actions: [
      TextButton(
        onPressed: () => widget.onNext(false),
        child: const Text('Previous'),
      ),
      TextButton(
        onPressed: () => widget.onNext(true),
        child: const Text('Next'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}
