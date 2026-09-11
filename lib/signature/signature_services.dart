import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/product_edition.dart';
import '../policy/policy_runtime.dart';
import 'privacy/privacy_journal.dart';
import 'storage/document_store.dart';
import 'workspaces/workspace_controller.dart';
import '../presentation/design_system/ui_preferences.dart';

class SignatureServices extends ChangeNotifier {
  SignatureServices({
    required SignatureDocumentStore store,
    required bool Function(String) eligible,
    this.isPrivate = false,
  }) : ephemeral = isPrivate || productEdition != ProductEdition.consumer,
       ui = UiPreferencesController(
         store: store,
         ephemeral: isPrivate || productEdition != ProductEdition.consumer,
       ),
       _store = SessionSignatureDocumentStore(
         store,
         ephemeral: isPrivate || productEdition != ProductEdition.consumer,
       ),
       workspaces = WorkspaceController(
         store: store,
         eligible: eligible,
         ephemeral: isPrivate || productEdition != ProductEdition.consumer,
       ) {
    journal = PrivacyJournal(
      awaitingRestoration: true,
      sessionKind: ephemeral
          ? PrivacySessionKind.private
          : PrivacySessionKind.normal,
    );
  }
  final bool isPrivate, ephemeral;
  final SignatureDocumentStore _store;
  final WorkspaceController workspaces;
  final UiPreferencesController ui;
  late final PrivacyJournal journal;
  bool initialized = false;
  bool _closed = false;

  Future<void> initialize() async {
    Map<String, Object?>? saved;
    var failed = false;
    await Future.wait([
      ui.initialize(),
      workspaces.initialize(),
      (() async {
        try {
          saved = await _store.readDocument('privacy');
        } catch (_) {
          failed = true;
        }
      })(),
    ]);
    if (_closed) return;
    journal.hydrate(
      initialState: saved,
      restorationFailed: failed,
      persist: ephemeral ? null : (row) => _store.writeDocument('privacy', row),
    );
    initialized = true;
    notifyListeners();
  }

  PrivacyConfiguration configuration(PolicyRuntime policy) =>
      PrivacyConfiguration(
        historyRecording: PrivacySetting.disabled,
        sync: PrivacySetting.disabled,
        cloudAi: PrivacySetting.disabled,
        liveWebContent: MandatorySafetyPolicy.liveContentSupported
            ? PrivacySetting.enabled
            : PrivacySetting.disabled,
        policyVersion: MandatorySafetyPolicy.version,
        policyFreshness: policy.status.usable
            ? PrivacyPolicyFreshness.current
            : policy.status.expiresAt != null &&
                  !policy.status.expiresAt!.isAfter(policy.clock.now())
            ? PrivacyPolicyFreshness.expired
            : PrivacyPolicyFreshness.unavailable,
      );
  Future<void> flush() async {
    await Future.wait([journal.flush(), workspaces.flush(), ui.flush()]);
  }

  @override
  void dispose() {
    _closed = true;
    journal.dispose();
    workspaces.dispose();
    ui.dispose();
    super.dispose();
  }
}
