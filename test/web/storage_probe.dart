// Browser-only smoke application. Does not run in the normal unit-test suite.
// Build: flutter build web -t test/web/storage_probe.dart --output work/web-storage-probe
// Serve that directory on a fixed localhost port. Load once to write and reopen,
// then reload the page: both passes must display PASS. Uses a dedicated test DB.
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:wingman_browser/data/sqlite_browser_repository.dart';
import 'package:wingman_browser/domain/models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final report = <String>[];
  SqliteBrowserRepository repository() => SqliteBrowserRepository(
    factory: databaseFactoryFfiWeb,
    databasePath: 'wingman_storage_smoke.db',
  );
  var db = repository();
  try {
    final previous = await db.load();
    if (previous.settings.onboardingComplete) {
      check(
        previous.settings.searchProviderId == 'brave',
        'Search provider survived browser reload',
      );
      check(
        previous.settings.themeMode == ThemeMode.dark,
        'Theme survived browser reload',
      );
      check(
        previous.bookmarks.single.url == 'https://example.com/smoke',
        'Bookmark survived browser reload',
      );
      check(
        previous.tabs.single.id == 'normal',
        'Normal tab survived browser reload',
      );
      check(
        previous.history.single.url == 'https://example.com/smoke',
        'History survived browser reload',
      );
      report.add(
        'PASS: browser reload retained settings, bookmark, normal tab and history.',
      );
    } else {
      report.add(
        'First run: writing dedicated synthetic test data. Reload this page to verify persistence.',
      );
    }
    const normal = BrowserTab(
      id: 'normal',
      url: 'https://example.com/smoke',
      title: 'Synthetic test',
    );
    const private = BrowserTab(
      id: 'PRIVATE-ID',
      url: 'https://private.example.com',
      title: 'PRIVATE-TITLE',
      isPrivate: true,
    );
    final now = DateTime.now();
    await db.saveSession([normal, private], private.id);
    await db.recordVisit(normal, now);
    await db.recordVisit(private, now);
    await db.saveBookmarks([
      Bookmark(
        id: 'bookmark',
        url: normal.url,
        title: normal.title,
        createdAt: now,
      ),
    ]);
    await db.saveSettings(
      const BrowserSettings(
        themeMode: ThemeMode.dark,
        searchProviderId: 'brave',
        onboardingComplete: true,
      ),
    );
    await db.close();
    db = repository();
    final reopened = await db.load();
    check(
      reopened.tabs.length == 1 && reopened.tabs.single.id == normal.id,
      'Private tab metadata excluded',
    );
    check(reopened.activeId == normal.id, 'Private active ID excluded');
    check(
      reopened.history.length == 1 && reopened.history.single.url == normal.url,
      'Private history excluded',
    );
    check(reopened.bookmarks.single.url == normal.url, 'Bookmark persisted');
    check(
      reopened.settings.searchProviderId == 'brave' &&
          reopened.settings.themeMode == ThemeMode.dark,
      'Settings persisted',
    );
    report.add(
      'PASS: SQLite reopened from IndexedDB with normal-only tabs and history.',
    );
    report.add(
      'PASS: private URL, title and active ID absent from restored data.',
    );
    report.add('PASS: bookmarks, theme and search preference persisted.');
  } catch (error) {
    report.add(
      'FAIL: ${error.runtimeType}. Inspect the storage implementation.',
    );
  } finally {
    await db.close();
  }
  runApp(
    MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: SelectableText(
              'Wingman Web storage smoke test\n\n${report.join('\n\n')}',
              style: const TextStyle(fontSize: 22),
            ),
          ),
        ),
      ),
    ),
  );
}

void check(bool passed, String message) {
  if (!passed) throw StateError(message);
}
