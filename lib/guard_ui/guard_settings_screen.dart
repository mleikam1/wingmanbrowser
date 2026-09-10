import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../guard/guard_models.dart';
import '../guard/filter_pack_repository.dart';
import '../guard_pin/guard_pin_service.dart';
import 'guard_controller.dart';

class GuardSettingsScreen extends StatefulWidget {
  const GuardSettingsScreen({super.key, required this.guard});
  final GuardController guard;
  @override
  State<GuardSettingsScreen> createState() => _GuardSettingsScreenState();
}

class _GuardSettingsScreenState extends State<GuardSettingsScreen> {
  GuardController get guard => widget.guard;
  bool busy = false;
  final Set<GuardCategory> focusChoices = {};
  int focusMinutes = 60;
  final focusHost = TextEditingController();
  final customMinutes = TextEditingController(text: '90');

  DateTime focusEnd() {
    final now = DateTime.now();
    if (focusMinutes == -1) {
      final evening = DateTime(now.year, now.month, now.day, 20);
      return evening.isAfter(now)
          ? evening
          : DateTime(now.year, now.month, now.day + 1);
    }
    if (focusMinutes == -2) return DateTime(now.year, now.month, now.day + 1);
    final minutes = focusMinutes == 0
        ? int.tryParse(customMinutes.text) ?? 0
        : focusMinutes;
    if (minutes < 1 || minutes > 10080) {
      throw StateError('Choose between 1 minute and 7 days (10,080 minutes).');
    }
    return now.add(Duration(minutes: minutes));
  }

  @override
  void initState() {
    super.initState();
    focusChoices.addAll(guard.configuration.focusCategories);
  }

  @override
  void dispose() {
    focusHost.dispose();
    customMinutes.dispose();
    guard.pin.lock();
    super.dispose();
  }

  void notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } on FormatException catch (error) {
      notice(error.message);
    } on StateError catch (error) {
      notice(error.message);
    } catch (_) {
      notice('This change could not be completed. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> input(
    String title, {
    bool secret = false,
    String? hint,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: secret,
          keyboardType: secret ? TextInputType.number : TextInputType.url,
          inputFormatters: secret
              ? [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(12),
                ]
              : null,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 300), controller.dispose);
    return result;
  }

  void pinResult(GuardPinAttempt result) {
    notice(switch (result.reason) {
      GuardPinReason.success => 'Family settings updated.',
      GuardPinReason.rateLimited =>
        'Try again in ${result.retryAfter.inSeconds + 1} seconds.',
      GuardPinReason.incorrectPin => 'That PIN did not match.',
      GuardPinReason.invalidPin => 'Use a PIN with 6–12 digits.',
      GuardPinReason.unavailable =>
        'Secure storage is unavailable. Settings remain locked.',
      GuardPinReason.cancelled => 'The PIN session ended. Please try again.',
      GuardPinReason.notConfigured => 'No Family PIN is set.',
    });
  }

  Future<void> unlock() async {
    final pin = await input(
      'Unlock Family settings',
      secret: true,
      hint: '6–12 digit PIN',
    );
    if (pin != null) {
      await run(() async {
        pinResult(await guard.pin.unlock(pin));
      });
    }
  }

  Future<void> setPin() async {
    String? current;
    if (guard.pin.hasPin) {
      current = await input('Current Family PIN', secret: true);
      if (current == null || !mounted) return;
    }
    final next = await input(
      'Choose a Family PIN',
      secret: true,
      hint: '6–12 digits',
    );
    if (next == null || !mounted) return;
    if (!GuardPinService.isValidPin(next)) {
      notice('Use a PIN with 6–12 digits.');
      return;
    }
    final repeat = await input('Confirm your new PIN', secret: true);
    if (repeat == null) return;
    if (repeat != next) {
      notice('The PINs did not match.');
      return;
    }
    await run(() async {
      pinResult(await guard.pin.setPin(next, currentPin: current));
    });
  }

  Future<void> addRule(bool allow) async {
    final value = await input(
      allow ? 'Always allow a site' : 'Always block a site',
      hint: 'example.com',
    );
    if (value != null) await run(() => guard.addRule(value, allow: allow));
  }

  Widget section(String title, String description, List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(description),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: guard,
    builder: (context, _) {
      final config = guard.configuration;
      final editable = !guard.locked && !busy;
      return Scaffold(
        appBar: AppBar(title: const Text('Wingman Guard')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    'A little backup.\nOn your terms.',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Choose the boundaries that help you. Your settings and routine website checks stay on this device.',
                  ),
                  const SizedBox(height: 20),
                  if (kIsWeb)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Web companion only: these preferences cannot filter pages after they open in another browser. Full Guard protection requires the Android or iOS app.',
                        ),
                      ),
                    ),
                  if (guard.problem != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(guard.problem!),
                      ),
                    ),
                  if (busy) const LinearProgressIndicator(),
                  if (guard.locked)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.lock_outline),
                        title: const Text('Family settings are locked'),
                        subtitle: const Text(
                          'Unlock to change rules or permit an exception.',
                        ),
                        trailing: TextButton(
                          onPressed: busy ? null : unlock,
                          child: const Text('Unlock'),
                        ),
                      ),
                    ),
                  section(
                    'Your browsing mode',
                    'Standard mode keeps native browser security on. Lifestyle categories are always your choice.',
                    [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Guard mode'),
                        subtitle: const Text(
                          'Enable your selected lifestyle categories',
                        ),
                        value: config.guardEnabled,
                        onChanged: editable
                            ? (value) => run(
                                () => guard.update(
                                  config.copyWith(guardEnabled: value),
                                ),
                              )
                            : null,
                      ),
                      for (final category in GuardCategory.values.where(
                        (c) => c.isLifestyle,
                      ))
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(category.label),
                          value: config.enabledCategories.contains(category),
                          onChanged: editable
                              ? (value) {
                                  final selected = {
                                    ...config.enabledCategories,
                                  };
                                  if (value == true) {
                                    selected.add(category);
                                  } else {
                                    selected.remove(category);
                                  }
                                  run(
                                    () => guard.update(
                                      config.copyWith(
                                        enabledCategories: selected,
                                      ),
                                    ),
                                  );
                                }
                              : null,
                        ),
                      const Text(
                        'Coverage is a small, curated starter set—not every website. Support, recovery and education sites are distinguished from commercial or recreational content. No URL keyword scanning.',
                      ),
                      if (config.adultFilteringEnabled)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'SafeSearch is requested on supported Google, Bing and DuckDuckGo search pages. Search providers control their results; this cannot guarantee every result is suitable.',
                          ),
                        ),
                    ],
                  ),
                  section(
                    'Focus for a while',
                    'Temporarily add boundaries without changing your lifestyle choices.',
                    [
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final category in GuardCategory.values.where(
                            (c) => c.isFocus,
                          ))
                            FilterChip(
                              label: Text(category.label),
                              selected: focusChoices.contains(category),
                              onSelected: editable
                                  ? (value) => setState(() {
                                      if (value) {
                                        focusChoices.add(category);
                                      } else {
                                        focusChoices.remove(category);
                                      }
                                    })
                                  : null,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: focusMinutes,
                        decoration: const InputDecoration(
                          labelText: 'Focus duration',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 30,
                            child: Text('30 minutes'),
                          ),
                          DropdownMenuItem(value: 60, child: Text('1 hour')),
                          DropdownMenuItem(value: 120, child: Text('2 hours')),
                          DropdownMenuItem(value: 480, child: Text('8 hours')),
                          DropdownMenuItem(
                            value: -1,
                            child: Text('Until tonight'),
                          ),
                          DropdownMenuItem(value: -2, child: Text('Today')),
                          DropdownMenuItem(
                            value: 0,
                            child: Text('Custom duration'),
                          ),
                        ],
                        onChanged: editable
                            ? (value) =>
                                  setState(() => focusMinutes = value ?? 60)
                            : null,
                      ),
                      if (focusMinutes == 0)
                        TextField(
                          controller: customMinutes,
                          enabled: editable,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Minutes (1–10,080)',
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: focusHost,
                        enabled: editable,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'Optional site to pause',
                          hintText: 'example.com',
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (guard.focusActive)
                        Text(
                          'Focus ends ${config.focusExpiresAt!.toLocal().toString().substring(0, 16)}.',
                        ),
                      Wrap(
                        spacing: 12,
                        children: [
                          FilledButton.tonal(
                            onPressed: editable
                                ? () => run(() async {
                                    final hosts = <String>{};
                                    if (focusHost.text.trim().isNotEmpty) {
                                      hosts.add(
                                        await guard.runtime.normalizer
                                            .normalize(focusHost.text),
                                      );
                                    }
                                    if (hosts.isEmpty && focusChoices.isEmpty) {
                                      throw StateError(
                                        'Choose a Focus category or a site first.',
                                      );
                                    }
                                    await guard.update(
                                      config.copyWith(
                                        focusCategories: focusChoices,
                                        focusHosts: hosts,
                                        focusExpiresAt: focusEnd(),
                                      ),
                                    );
                                  })
                                : null,
                            child: Text(
                              guard.focusActive
                                  ? 'Restart Focus'
                                  : 'Start Focus',
                            ),
                          ),
                          if (guard.focusActive)
                            TextButton(
                              onPressed: editable
                                  ? () => run(
                                      () => guard.update(
                                        config.copyWith(clearFocus: true),
                                      ),
                                    )
                                  : null,
                              child: const Text('End Focus'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  section(
                    'Site exceptions',
                    'Rules include subdomains. The most specific site rule wins; a block wins when both rules name the same domain. Allow rules never bypass malware, phishing or unsafe connections.',
                    [
                      for (final allow in [true, false]) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(allow ? 'Always allow' : 'Always block'),
                          trailing: IconButton(
                            tooltip: allow
                                ? 'Add allowed site'
                                : 'Add blocked site',
                            onPressed: editable ? () => addRule(allow) : null,
                            icon: const Icon(Icons.add),
                          ),
                        ),
                        for (final host
                            in (allow ? config.customAllow : config.customBlock)
                                .toList()
                              ..sort())
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(host),
                            trailing: IconButton(
                              tooltip: 'Remove $host',
                              onPressed: editable
                                  ? () => run(() {
                                      final sites = Set<String>.of(
                                        allow
                                            ? config.customAllow
                                            : config.customBlock,
                                      )..remove(host);
                                      return guard.update(
                                        allow
                                            ? config.copyWith(
                                                customAllow: sites,
                                              )
                                            : config.copyWith(
                                                customBlock: sites,
                                              ),
                                      );
                                    })
                                  : null,
                              icon: const Icon(Icons.close),
                            ),
                          ),
                      ],
                    ],
                  ),
                  section(
                    'Security and tracking',
                    'Android Safe Browsing and iOS fraudulent-site warnings remain enabled. Both platforms reject certificate errors. Wingman is not an antivirus scanner.',
                    [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Balanced tracking protection'),
                        subtitle: const Text(
                          'Blocks a starter set of 7 third-party tracker domains. Some sites may need a temporary exception from the browser menu.',
                        ),
                        value: config.trackingProtection,
                        onChanged: editable
                            ? (value) => run(
                                () => guard.update(
                                  config.copyWith(trackingProtection: value),
                                ),
                              )
                            : null,
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Warn about executable downloads'),
                        subtitle: const Text(
                          'Known harmful-domain rules always apply. File-type warnings do not prove a file is malicious.',
                        ),
                        value: config.dangerousDownloadProtection,
                        onChanged: editable
                            ? (value) => run(
                                () => guard.update(
                                  config.copyWith(
                                    dangerousDownloadProtection: value,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      if (guard.trackingExceptions.isNotEmpty)
                        Text(
                          'Temporary tracking exceptions: ${guard.trackingExceptions.join(', ')}. Cleared when the app restarts.',
                        ),
                    ],
                  ),
                  section(
                    'Family settings',
                    'A local PIN protects Guard settings and overrides inside Wingman. It is not device-wide parental control. Keep your PIN safe; there is no account recovery.',
                    [
                      if (!guard.pin.isSupported)
                        const Text(
                          'Family PIN is available only in the mobile app.',
                        )
                      else
                        Wrap(
                          spacing: 12,
                          children: [
                            OutlinedButton.icon(
                              onPressed: busy ? null : setPin,
                              icon: const Icon(Icons.lock_outline),
                              label: Text(
                                guard.pin.hasPin
                                    ? 'Change PIN'
                                    : 'Set Family PIN',
                              ),
                            ),
                            if (guard.pin.hasPin)
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () async {
                                        final pin = await input(
                                          'Remove Family PIN',
                                          secret: true,
                                        );
                                        if (pin != null) {
                                          await run(() async {
                                            pinResult(
                                              await guard.pin.removePin(pin),
                                            );
                                          });
                                        }
                                      },
                                child: const Text('Remove PIN'),
                              ),
                            if (guard.pin.hasPin && !guard.locked)
                              TextButton(
                                onPressed: guard.pin.lock,
                                child: const Text('Lock now'),
                              ),
                          ],
                        ),
                    ],
                  ),
                  section(
                    'Today on this device',
                    'Local totals only. No site log is created, and private-tab activity does not enter these saved counts.',
                    [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Guard blocks'),
                        trailing: Text('${guard.guardToday}'),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Risky pages / download warnings'),
                        trailing: Text('${guard.riskyToday}'),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Trackers blocked'),
                        trailing: Text(
                          !kIsWeb &&
                                  defaultTargetPlatform ==
                                      TargetPlatform.android
                              ? '${guard.trackersToday}'
                              : 'Unavailable',
                        ),
                      ),
                      if (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS)
                        const Text(
                          kIsWeb
                            ? 'The Web companion cannot block or count trackers in websites opened in your host browser.'
                            : 'iOS does not expose a reliable per-request tracker count. An unavailable count does not mean zero blocking.',
                        ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => run(guard.resetStatistics),
                        child: const Text('Reset local statistics'),
                      ),
                    ],
                  ),
                  section(
                    'Filter pack',
                    'Versioned, signature-verified rules stored on this device. Native threat providers have separate coverage. No full browsing URL is sent to Wingman infrastructure.',
                    [
                      Text(
                        'Version: ${guard.pack.version ?? 'Unavailable'}\nRules: ${guard.pack.ruleCount}\nIntegrity: ${guard.pack.integrityVerified ? 'Verified' : 'Unavailable'}',
                      ),
                      if (guard.pack.isStale(DateTime.now()))
                        const Text(
                          'This pack is more than 30 days old. Coverage may be out of date.',
                        ),
                      const Text(
                        'The production update service is not configured. The bundled pack continues to work offline.',
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => run(() async {
                                    final result = await guard.checkUpdates();
                                    notice(switch (result.outcome) {
                                      FilterUpdateOutcome.notConfigured =>
                                        'No update service is configured. Your verified local pack remains active.',
                                      FilterUpdateOutcome.updated =>
                                        'Verified rules updated.',
                                      FilterUpdateOutcome.current =>
                                        'Your rules are current.',
                                      FilterUpdateOutcome.throttled =>
                                        'Rules were checked recently. Try again later.',
                                      FilterUpdateOutcome.rejected =>
                                        'The update could not be verified. The last valid pack remains active.',
                                    });
                                  }),
                            child: const Text('Check for updates'),
                          ),
                          if (guard.pack.hasPrevious)
                            TextButton(
                              onPressed: editable
                                  ? () => run(() async {
                                      notice(
                                        await guard.rollback()
                                            ? 'Previous verified pack restored.'
                                            : 'No previous pack is available.',
                                      );
                                    })
                                  : null,
                              child: const Text('Restore previous pack'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
