import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/presentation/design_system/app_build_info.dart';
import 'package:wingman_browser/presentation/design_system/ui_preferences.dart';
import 'package:wingman_browser/presentation/protection/policy_state_view.dart';
import 'package:wingman_browser/presentation/protection/protection_screen.dart';
import 'package:wingman_browser/presentation/settings/appearance_screen.dart';
import 'package:wingman_browser/presentation/settings/settings_screen.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/signature/commit_review/commit_review_screen.dart';
import 'package:wingman_browser/signature/privacy/privacy_journal.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'package:wingman_browser/state/browser_state.dart';
import '../support/protected_test_support.dart';

class _CaptureAnalyzer extends CommitReviewAnalyzer {
  const _CaptureAnalyzer();
  @override
  Future<CommitReviewReport> analyze(
    CommitReviewInput input, {
    DateTime? checkedAt,
  }) => super.analyze(input, checkedAt: DateTime.utc(2026, 9, 25, 12));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('WINGMAN_REDESIGN_CAPTURES');
  setUpAll(() async {
    final font = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  SettingsActions actions() => SettingsActions(
    onHomeCustomization: () {},
    onSpaces: () {},
    onProtection: () {},
    onReceipt: () {},
    onCompatibility: () {},
    onFinishMode: () {},
    onCommitReview: () {},
    onUpdates: () {},
    onClearData: (_) async => DataClearOutcome(),
    clearableCategories: {},
  );

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final scrollable = find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down &&
              widget.restorationId != 'editable',
        )
        .first;
    for (var i = 0; i < 80 && finder.evaluate().isEmpty; i++) {
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(
        (position.pixels + 350).clamp(0, position.maxScrollExtent),
      );
      await tester.pump();
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('private appearance never writes owner preferences', (
    tester,
  ) async {
    final policy = (await tester.runAsync(loadTestPolicy))!;
    final repository = MemoryBrowserRepository();
    final state = BrowserState(repository: repository, policyRuntime: policy);
    await state.init();
    final original = state.settings.themeMode;
    await tester.pumpWidget(
      MaterialApp(
        home: AppearanceScreen(
          state: state,
          canContinue: () => true,
          isPrivate: true,
        ),
      ),
    );
    await reveal(tester, find.text('Dark'));
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(state.settings.themeMode, original);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    policy.dispose();
  });

  testWidgets(
    'boundary separates category, unavailable policy, and unsupported operation',
    (tester) async {
      for (final code in [
        PolicyDecisionCode.blockMandatoryCategory,
        PolicyDecisionCode.blockPolicyUnavailable,
        PolicyDecisionCode.blockUnsupportedCapability,
      ]) {
        var resumed = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: PolicyStateView(
              decision: PolicyDecision(
                code,
                category: code == PolicyDecisionCode.blockMandatoryCategory
                    ? MandatoryCategory.gambling
                    : null,
              ),
              onHome: () {},
              onExplore: () {},
              onRequestReview: () {},
              onBack: () {},
              onResumeTask: () => resumed++,
              taskTitle: 'QA project',
              taskNextStep: 'Compare the options',
              taskProgress: '1 of 3 steps',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await reveal(tester, find.text('Back to my task'));
        await tester.tap(find.text('Back to my task'));
        expect(resumed, 1);
        expect(find.textContaining('Continue anyway'), findsNothing);
        if (code != PolicyDecisionCode.blockMandatoryCategory) {
          expect(find.textContaining('matched the'), findsNothing);
        }
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'redesign privacy boundary settings and evidence captures ${brightness.name}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final policy = (await tester.runAsync(loadTestPolicy))!;
        final state = BrowserState(
          repository: MemoryBrowserRepository(),
          policyRuntime: policy,
        );
        await state.init();
        final journal = PrivacyJournal(sessionKind: PrivacySessionKind.private);
        final preferences = UiPreferencesController(
          store: MemorySignatureDocumentStore(),
          ephemeral: false,
        );
        await preferences.initialize();
        final key = GlobalKey();
        final pages = <String, Widget>{
          '05-privacy': ProtectionScreen(
            state: state,
            policy: policy,
            isPrivate: false,
            canContinue: () => true,
            onReceipt: () {},
            onRequestReview: () {},
            onOpenApprovedResource: (_) {},
            onHome: () {},
          ),
          '06-boundary': PolicyStateView(
            decision: const PolicyDecision(
              PolicyDecisionCode.blockMandatoryCategory,
              category: MandatoryCategory.gambling,
            ),
            onHome: () {},
            onExplore: () {},
            onRequestReview: () {},
            onBack: () {},
            taskTitle: 'Compare project options',
            taskNextStep: 'Choose materials for the project',
            taskProgress: '1 of 3 steps',
            onResumeTask: () {},
          ),
          '07-commit': CommitReviewScreen(
            analyzer: const _CaptureAnalyzer(),
            policy: policy,
            additional: AdditionalRestrictions.new,
            journal: journal,
            savedAnalyses: () => [],
            onSave: (_) async {},
            onDelete: (_) async {},
            isPrivate: true,
          ),
          '08-settings': SettingsScreen(
            uiPreferences: preferences,
            state: state,
            policy: policy,
            isPrivate: false,
            canContinue: () => true,
            actions: actions(),
            buildInfo: AppBuildInfo.current,
          ),
        };
        for (final scale in [1.0, 2.0]) {
          for (final width
              in scale == 1
                  ? [390.0, 1440.0]
                  : [320.0, 390.0, 430.0, 768.0, 1024.0, 1440.0]) {
            tester.view.physicalSize = Size(width, width >= 1000 ? 1100 : 900);
            for (final entry in pages.entries) {
              await tester.pumpWidget(
                RepaintBoundary(
                  key: key,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: WingmanTheme.make(brightness),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                    home: entry.value,
                  ),
                ),
              );
              await tester.pumpAndSettle();
              await tester.runAsync(() async {
                await precacheImage(
                  const ResizeImage(
                    AssetImage('assets/brand/wingman-mark.png'),
                    width: 72,
                  ),
                  tester.element(find.byType(MaterialApp)),
                );
              });
              await tester.pumpAndSettle();
              if (entry.key == '07-commit' && scale == 1) {
                await reveal(tester, find.text('Use a practice example'));
                await tester.tap(find.text('Use a practice example'));
                await tester.pumpAndSettle();
                await reveal(tester, find.text('Check this selection'));
                await tester.runAsync(() async {
                  await tester.tap(find.text('Check this selection'));
                  await Future<void>.delayed(const Duration(milliseconds: 50));
                });
                await tester.pumpAndSettle();
                await reveal(tester, find.text('Here’s what the text says'));
              }
              expect(
                tester.takeException(),
                isNull,
                reason: '${entry.key} $brightness $width $scale',
              );
              if (capture && scale == 1) {
                if (width >= 1000) {
                  final scrollable = find
                      .byWidgetPredicate(
                        (widget) =>
                            widget is Scrollable &&
                            widget.axisDirection == AxisDirection.down &&
                            widget.restorationId != 'editable',
                      )
                      .first;
                  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
                  await tester.pumpAndSettle();
                }
                final boundary =
                    key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                await tester.runAsync(() async {
                  final image = await boundary.toImage(pixelRatio: 1);
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  final file = File(
                    'docs/ui/redesign/screenshots/${entry.key}-${width.toInt()}-${brightness.name}.png',
                  );
                  await file.parent.create(recursive: true);
                  await file.writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
              await tester.pumpWidget(const SizedBox());
            }
          }
        }
        journal.dispose();
        preferences.dispose();
        state.dispose();
        policy.dispose();
      },
    );
  }
}
