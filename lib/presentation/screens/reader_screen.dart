import 'package:flutter/material.dart';
import '../../browser/browser_engine.dart';

/// A transient plain-text view: no HTML renderer, links, remote media or file.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.article});
  final ReaderArticle article;
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  double _size = 20;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Reader'),
      actions: [
        IconButton(
          tooltip: 'Smaller reader text',
          onPressed: _size <= 16 ? null : () => setState(() => _size -= 2),
          icon: const Icon(Icons.text_decrease),
        ),
        IconButton(
          tooltip: 'Larger reader text',
          onPressed: _size >= 32 ? null : () => setState(() => _size += 2),
          icon: const Icon(Icons.text_increase),
        ),
      ],
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.article.title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                widget.article.sourceUrl,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Text from this page, kept in memory. Some pages do not provide a readable article. Return to the page for its full content.',
              ),
              const Divider(height: 40),
              SelectableText(
                widget.article.text,
                style: TextStyle(fontSize: _size, height: 1.65),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
