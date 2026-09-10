import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/data/browser_repository.dart';
import 'package:wingman_browser/domain/models.dart';
import 'package:wingman_browser/main.dart';
import 'package:wingman_browser/presentation/screens/home_screen.dart';
import 'package:wingman_browser/presentation/screens/settings_screen.dart';
import 'package:wingman_browser/presentation/screens/tab_switcher.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/state/browser_state.dart';

class MemoryRepository implements BrowserRepository {
  BrowserData data = const BrowserData();
  @override
  Future<BrowserData> load() async => data;
  @override
  Future<void> saveSession(List<BrowserTab> tabs, String activeId) async {}
  @override
  Future<void> recordVisit(BrowserTab tab, DateTime visitedAt) async {}
  @override
  Future<void> saveBookmarks(List<Bookmark> bookmarks) async {}
  @override
  Future<bool> addReadingListItem(
    BrowserTab tab, {
    required String id,
    required DateTime createdAt,
  }) async => !tab.isPrivate && !tab.isHome;
  @override
  Future<void> setReadingListRead(String id, DateTime? readAt) async {}
  @override
  Future<void> removeReadingListItem(String id) async {}
  @override
  Future<void> saveSettings(BrowserSettings settings) async {}
  @override
  Future<void> clearHistory() async {}
  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('first launch explains promise and enters actual home', (
    tester,
  ) async {
    final state = BrowserState(repository: MemoryRepository());
    await state.init();
    await tester.pumpWidget(WingmanApp(state: state));
    expect(find.text("We've got your back,\nnot your data."), findsOneWidget);
    await tester.ensureVisible(find.text('Let’s explore'));
    await tester.tap(find.text('Let’s explore'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-omnibox')), findsOneWidget);
    expect(state.settings.onboardingComplete, isTrue);
    expect(find.text("We've got your back, not your data."), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1024, 768),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets('home accessible at $size $brightness and large text', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = BrowserState(repository: MemoryRepository());
        await state.init();
        await tester.pumpWidget(
          MaterialApp(
            theme: WingmanTheme.make(brightness),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(1.6),
              ),
              child: Scaffold(
                body: HomeScreen(
                  state: state,
                  onNavigate: (_) {},
                  onSettings: () {},
                  onBookmarks: () {},
                  onPrivate: () {},
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byKey(const ValueKey('wingman-home')),
          const Offset(0, -700),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      });
    }
  }
  testWidgets('private tab switcher and settings work with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = BrowserState(repository: MemoryRepository());
    await state.init();
    state.newTab(isPrivate: true);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: TabSwitcher(
            state: state,
            onSelect: (_) {},
            onClose: state.closeTab,
            onNew: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Private tab'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          state: state,
          onClear: () {},
          onDefaultBrowser: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Search engine'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
