import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'package:wingman_browser/signature/workspaces/discovery_session.dart';
import 'package:wingman_browser/policy/strict_search_policy.dart';

void main() {
  test(
    'normal destinations restore, private tabs and search queries never persist',
    () async {
      final store = MemorySignatureDocumentStore();
      final session = DiscoverySession();
      await session.restore(
        store,
        permitted: (_) => true,
        resourceEligible: (_) => true,
      );
      session.current.visitWebsite(Uri.parse('https://example.com/account'));
      session.tabs.add(
        DiscoveryTab(isPrivate: true)
          ..visitWebsite(Uri.parse('https://private.invalid/secret')),
      );
      session.tabs.add(
        DiscoveryTab()..visitWebsite(
          const StrictSearchPolicy().buildQuery('private query words'),
        ),
      );
      session.active = 1;
      await session.flush();
      final saved = await store.readDocument('browserSession');
      expect(saved.toString(), isNot(contains('private.invalid')));
      expect(saved.toString(), isNot(contains('private query words')));
      expect((saved!['tabs'] as List), hasLength(2));
      final restored = DiscoverySession();
      await restored.restore(
        store,
        permitted: (_) => true,
        resourceEligible: (_) => true,
      );
      expect(
        restored.current.website.toString(),
        'https://example.com/account',
      );
      expect(restored.tabs.every((t) => !t.isPrivate), isTrue);
      expect(restored.tabs.last.website, isNull);
      session.dispose();
      restored.dispose();
    },
  );

  test(
    'restoration rechecks policy and never revives a now blocked destination',
    () async {
      final store = MemorySignatureDocumentStore();
      await store.writeDocument('browserSession', {
        'version': 1,
        'active': 'old',
        'tabs': [
          {'id': 'old', 'entry': 'web:https://blocked.invalid/'},
          {'id': 'private', 'entry': 'javascript:alert(1)'},
        ],
      });
      final session = DiscoverySession();
      await session.restore(
        store,
        permitted: (_) => false,
        resourceEligible: (_) => false,
      );
      expect(session.current.website, isNull);
      expect(session.tabs.every((t) => t.currentEntry == null), isTrue);
      session.dispose();
    },
  );
}
