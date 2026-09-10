import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/data/browser_repository.dart';
import 'package:wingman_browser/domain/models.dart';
import 'package:wingman_browser/domain/bookmark_transfer.dart';
import 'package:wingman_browser/monetization/ad_route_observer.dart';
import 'package:wingman_browser/presentation/bookmark_files.dart';
import 'package:wingman_browser/presentation/screens/library_screen.dart';
import 'package:wingman_browser/state/browser_state.dart';

class _Repository implements BrowserRepository {
  List<Bookmark> bookmarks = [];
  List<ReadingListItem> reading = [];
  bool failWrites = false;
  Completer<void>? bookmarkWrite;
  @override
  Future<BrowserData> load() async =>
      BrowserData(bookmarks: bookmarks, readingList: reading);
  @override
  Future<void> saveBookmarks(List<Bookmark> value) async {
    await bookmarkWrite?.future;
    if (failWrites) throw StateError('synthetic storage failure');
    bookmarks = List.of(value);
  }

  @override
  Future<bool> addReadingListItem(
    BrowserTab tab, {
    required String id,
    required DateTime createdAt,
  }) async {
    if (tab.isPrivate ||
        tab.isHome ||
        reading.any((item) => item.url == tab.url)) {
      return false;
    }
    reading = [
      ReadingListItem(
        id: id,
        url: tab.url,
        title: tab.title,
        createdAt: createdAt,
      ),
      ...reading,
    ];
    return true;
  }

  @override
  Future<void> setReadingListRead(String id, DateTime? readAt) async {
    reading = [
      for (final item in reading)
        if (item.id == id) item.withReadAt(readAt) else item,
    ];
  }

  @override
  Future<void> removeReadingListItem(String id) async {
    reading = reading.where((item) => item.id != id).toList();
  }

  @override
  Future<void> saveSession(List<BrowserTab> tabs, String activeId) async {}
  @override
  Future<void> recordVisit(BrowserTab tab, DateTime visitedAt) async {}
  @override
  Future<void> saveSettings(BrowserSettings settings) async {}
  @override
  Future<void> clearHistory() async {}
  @override
  Future<void> close() async {}
}

class _Files implements BookmarkFiles {
  Uint8List? selection;
  Completer<Uint8List?>? pendingSelection;
  Uint8List? exported;
  int exports = 0;
  @override
  Future<Uint8List?> selectImport() async =>
      pendingSelection == null ? selection : await pendingSelection!.future;
  @override
  Future<void> export(Uint8List bytes, Rect? origin) async {
    exported = bytes;
    exports++;
  }
}

void main() {
  late _Repository repository;
  late BrowserState data;
  late _Files files;
  late GlobalKey<NavigatorState> navigator;
  final visited = <String>[];
  Future<void> initialize() async {
    repository = _Repository();
    files = _Files();
    visited.clear();
    data = BrowserState(repository: repository);
    await data.init();
  }

  tearDown(() {
    data.dispose();
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });
  Future<void> show(
    WidgetTester tester, {
    LibraryKind kind = LibraryKind.bookmarks,
    BookmarkImportDecoder? decode,
    bool asRoute = false,
  }) async {
    navigator = GlobalKey<NavigatorState>();
    final library = LibraryScreen(
      state: data,
      kind: kind,
      files: files,
      decode:
          decode ??
          (bytes, urls) async =>
              BookmarkTransferCodec.parse(bytes, existingUrls: urls),
      onNavigate: visited.add,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [adRouteObserver],
        home: asRoute ? const Scaffold(body: Text('Browser page')) : library,
      ),
    );
    await tester.pumpAndSettle();
    if (asRoute) {
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => library),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> chooseFile(WidgetTester tester) async {
    await tester.tap(find.text('Import file'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Uint8List html(String body) => Uint8List.fromList(
    utf8.encode('<!DOCTYPE NETSCAPE-Bookmark-file-1><DL>$body</DL>'),
  );

  testWidgets('canceling chooser or inert preview never imports or navigates', (
    tester,
  ) async {
    await initialize();
    await show(tester);
    await chooseFile(tester);
    expect(find.text('Preview bookmark import'), findsNothing);
    files.selection = html(
      '<DT><A HREF="https://example.com/article">&lt;script&gt;alert(1)&lt;/script&gt;</A><DT><A HREF="javascript:alert(2)">Unsafe</A>',
    );
    await chooseFile(tester);
    expect(find.text('1 new · 0 duplicates · 1 rejected'), findsOneWidget);
    expect(find.text('<script>alert(1)</script>'), findsOneWidget);
    expect(data.bookmarks, isEmpty);
    expect(visited, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(data.bookmarks, isEmpty);
    expect(repository.bookmarks, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'confirmed import persists; duplicate preview cannot import again',
    (tester) async {
      await initialize();
      files.selection = html(
        '<DT><A HREF="https://example.com/article">Article</A>',
      );
      await show(tester);
      await chooseFile(tester);
      await tester.tap(find.text('Import 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.bookmarks.single.url, 'https://example.com/article');
      expect(find.text('1 bookmarks imported.'), findsOneWidget);
      expect(visited, isEmpty);
      await chooseFile(tester);
      expect(find.text('0 new · 1 duplicates · 0 rejected'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Import 0'))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed import gives no success or optimistic library entry', (
    tester,
  ) async {
    await initialize();
    repository.failWrites = true;
    files.selection = html(
      '<DT><A HREF="https://example.com/article">Article</A>',
    );
    await show(tester);
    await chooseFile(tester);
    await tester.tap(find.text('Import 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(data.bookmarks, isEmpty);
    expect(repository.bookmarks, isEmpty);
    expect(find.text('1 bookmarks imported.'), findsNothing);
    expect(
      find.textContaining('The library change could not be saved.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('export creates a file only after destination confirmation', (
    tester,
  ) async {
    await initialize();
    data.navigate('https://example.com/?a=1&b=2');
    await data.toggleBookmark();
    await show(tester);
    await tester.tap(find.text('Export bookmarks'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(files.exports, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(files.exports, 0);
    await tester.tap(find.text('Export bookmarks'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Choose destination'));
    await tester.pumpAndSettle();
    expect(files.exports, 1);
    expect(utf8.decode(files.exported!), contains('&amp;'));
    expect(visited, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reading list marks read and removes a persisted item', (
    tester,
  ) async {
    await initialize();
    data.navigate('https://example.com/article');
    expect(await data.addToReadingList(), isTrue);
    await show(tester, kind: LibraryKind.readingList);
    await tester.tap(find.byTooltip('Manage saved page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark read'));
    await tester.pumpAndSettle();
    expect(repository.reading.single.isRead, isTrue);
    await tester.tap(find.byTooltip('Manage saved page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(data.readingList, isEmpty);
    expect(repository.reading, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'reading list accepts an explicit address from Home without visiting it',
    (tester) async {
      await initialize();
      await show(tester, kind: LibraryKind.readingList);
      await tester.tap(find.text('Add address'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
        find.byType(TextField),
        'https://example.com/later',
      );
      await tester.tap(find.text('Save address'));
      await tester.pumpAndSettle();
      expect(repository.reading.single.url, 'https://example.com/later');
      expect(data.activeTab.isHome, isTrue);
      expect(visited, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('private library cannot persist a typed address', (tester) async {
    await initialize();
    data.newTab(isPrivate: true);
    await show(tester, kind: LibraryKind.readingList);
    expect(find.text('Add address'), findsNothing);
    expect(repository.reading, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  BookmarkImportPreview preview() => BookmarkTransferCodec.parse(
    html('<DT><A HREF="https://example.com/later">Later</A>'),
  );

  Future<void> pumpRoutes(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  testWidgets(
    'popped library discards a decoder result during exit animation',
    (tester) async {
      await initialize();
      files.selection = Uint8List(0);
      final decoded = Completer<BookmarkImportPreview>();
      await show(tester, asRoute: true, decode: (_, _) => decoded.future);
      await chooseFile(tester);
      navigator.currentState!.pop();
      decoded.complete(preview());
      await pumpRoutes(tester);
      expect(find.text('Browser page'), findsOneWidget);
      expect(find.text('Preview bookmark import'), findsNothing);
      expect(repository.bookmarks, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('rapid route coverage and return cannot revive an import', (
    tester,
  ) async {
    await initialize();
    files.selection = Uint8List(0);
    final decoded = Completer<BookmarkImportPreview>();
    await show(tester, decode: (_, _) => decoded.future);
    await chooseFile(tester);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other route')),
      ),
    );
    await tester.pump();
    navigator.currentState!.pop();
    await pumpRoutes(tester);
    decoded.complete(preview());
    await pumpRoutes(tester);
    expect(find.text('Preview bookmark import'), findsNothing);
    expect(repository.bookmarks, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('background and resume discard pending decode', (tester) async {
    await initialize();
    files.selection = Uint8List(0);
    final decoded = Completer<BookmarkImportPreview>();
    await show(tester, decode: (_, _) => decoded.future);
    await chooseFile(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    decoded.complete(preview());
    await pumpRoutes(tester);
    expect(find.text('Preview bookmark import'), findsNothing);
    expect(repository.bookmarks, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'system picker return waits for resume then permits explicit import',
    (tester) async {
      await initialize();
      files.pendingSelection = Completer<Uint8List?>();
      await show(tester);
      await chooseFile(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      files.pendingSelection!.complete(
        html('<DT><A HREF="https://example.com/later">Later</A>'),
      );
      await pumpRoutes(tester);
      expect(find.text('Preview bookmark import'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpRoutes(tester);
      expect(find.text('Preview bookmark import'), findsOneWidget);
      await tester.tap(find.text('Import 1'));
      await tester.pumpAndSettle();
      expect(repository.bookmarks.single.url, 'https://example.com/later');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('covered export confirmation cannot revive after returning', (
    tester,
  ) async {
    await initialize();
    data.navigate('https://example.com/later');
    await data.toggleBookmark();
    await show(tester);
    await tester.tap(find.text('Export bookmarks'));
    await pumpRoutes(tester);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other route')),
      ),
    );
    await tester.pump();
    navigator.currentState!.pop();
    await pumpRoutes(tester);
    await tester.tap(find.text('Choose destination'));
    await tester.pumpAndSettle();
    expect(files.exports, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('backgrounded address confirmation does not persist on return', (
    tester,
  ) async {
    await initialize();
    await show(tester, kind: LibraryKind.readingList);
    await tester.tap(find.text('Add address'));
    await pumpRoutes(tester);
    await tester.enterText(find.byType(TextField), 'https://example.com/later');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.tap(find.text('Save address'));
    await tester.pumpAndSettle();
    expect(repository.reading, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'confirmed pending import finishes durably without messaging another route',
    (tester) async {
      await initialize();
      files.selection = html(
        '<DT><A HREF="https://example.com/later">Later</A>',
      );
      repository.bookmarkWrite = Completer<void>();
      await show(tester, asRoute: true);
      await chooseFile(tester);
      await tester.tap(find.text('Import 1'));
      await pumpRoutes(tester);
      navigator.currentState!.pop();
      repository.bookmarkWrite!.complete();
      await pumpRoutes(tester);
      expect(repository.bookmarks.single.url, 'https://example.com/later');
      expect(find.text('Browser page'), findsOneWidget);
      expect(find.text('1 bookmarks imported.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
