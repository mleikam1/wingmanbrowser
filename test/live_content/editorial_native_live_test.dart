import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/eligibility.dart';
import 'package:wingman_browser/live_content/models.dart';
import 'package:wingman_browser/live_content/rss_provider.dart';
import 'package:wingman_browser/live_content/rss_transport_native.dart';
import 'package:wingman_browser/policy/consumer_protection_policy.dart';

class _LiveHttp extends HttpOverrides {}

class _ObservedNative implements RssFeedTransport {
  final responses = <String, Map<String, Object?>>{};
  final addresses = <String, List<String>>{};
  late final NativeRssFeedTransport native = NativeRssFeedTransport(
    resolver: (host) async {
      final result = await InternetAddress.lookup(host);
      addresses[host] = result.map((address) => address.address).toList();
      return result;
    },
  );
  @override
  Future<RssFetchResponse> fetch(
    ApprovedLiveSource source,
    Map<String, String> validators,
  ) async {
    final started = DateTime.now().toUtc();
    try {
      final response = await native.fetch(source, validators);
      responses[source.source.id] = {
        'checkedAt': started.toIso8601String(),
        'completedAt': DateTime.now().toUtc().toIso8601String(),
        'status': response.status,
        'decodedBytes': response.body.length,
        'conditionalRequest': validators.isNotEmpty,
        'headers': {
          for (final name in [
            'content-type',
            'content-encoding',
            'content-length',
            'cache-control',
            'retry-after',
            'age',
            'date',
          ])
            if (response.headers.containsKey(name))
              name: response.headers[name],
        },
      };
      return response;
    } on RssFailure catch (error) {
      responses[source.source.id] = {
        'checkedAt': started.toIso8601String(),
        'completedAt': DateTime.now().toUtc().toIso8601String(),
        'error': error.code,
        'status': error.status,
        'conditionalRequest': validators.isNotEmpty,
      };
      rethrow;
    }
  }

  @override
  void cancel() => native.cancel();
}

void main() {
  test(
    'one paced real native publisher batch produces delivery diagnostics',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final registryBytes = await File(
        'assets/live_content/sources.json',
      ).readAsBytes();
      final registry = LiveSourceRegistry.fromJson(
        feedMap(jsonDecode(utf8.decode(registryBytes))),
      );
      final policy = await ConsumerProtectionPolicy.verifyBytes(
        await File(ConsumerProtectionPolicy.assetPath).readAsBytes(),
      );
      expect(policy.isUsable, isTrue);
      final eligibility = LiveContentEligibility(
        registry: registry,
        canOpenDestination: (uri) => policy.assessNavigation(uri).isAllowed,
      );
      final directory = Directory('work/rss-direct')
        ..createSync(recursive: true);
      final stateFile = File('${directory.path}/state.json');
      final snapshotFile = File('${directory.path}/snapshot.json');
      final state = stateFile.existsSync()
          ? feedMap(jsonDecode(stateFile.readAsStringSync()))
          : <String, dynamic>{
              'schemaVersion': 1,
              'sources': <String, dynamic>{},
            };
      final states = feedMap(state['sources']);
      // Shared workstation acceptance probes honor the longest existing hold.
      // This only extends pacing; never import backend items/validators as native
      // results, erase failures, clear cursors, or shorten a publisher instruction.
      final otherCheckpoint = File('work/editorial-repair/supply/states.json');
      if (otherCheckpoint.existsSync()) {
        for (final entry in feedMap(
          jsonDecode(otherCheckpoint.readAsStringSync()),
        ).entries) {
          if (!registry.sources.containsKey(entry.key) || entry.value is! Map) {
            continue;
          }
          final other = feedMap(entry.value);
          final existing = states[entry.key] is Map
              ? feedMap(states[entry.key])
              : <String, dynamic>{};
          final next = DateTime.tryParse(
            other['nextRefreshAt'] as String? ?? '',
          );
          final prior = DateTime.tryParse(
            existing['nextRefreshAt'] as String? ?? '',
          );
          if (next != null && (prior == null || next.isAfter(prior))) {
            existing['nextRefreshAt'] = next.toUtc().toIso8601String();
          }
          if (other['refreshSuspended'] == true) existing['paused'] = true;
          states[entry.key] = existing;
        }
      }
      state['sources'] = states;
      final transport = _ObservedNative();
      final provider = RssFeedProvider(
        registry: registry,
        eligibility: eligibility,
        allowsEditorialText: eligibility.acceptsFeedText,
        transport: transport,
      );
      addTearDown(provider.cancel);
      provider.restore(
        state: state,
        snapshot: snapshotFile.existsSync()
            ? LiveSnapshot.fromJson(
                feedMap(jsonDecode(snapshotFile.readAsStringSync())),
              )
            : null,
      );
      final result = await provider.fetch();
      final snapshot = result.snapshot!;
      // Persist completed attempt checkpoints before evaluating success, so a
      // failed test cannot permit an immediate repeat request to the publisher.
      await stateFile.writeAsString(
        jsonEncode(result.providerState),
        flush: true,
      );
      await snapshotFile.writeAsString(
        jsonEncode(snapshot.toJson()),
        flush: true,
      );
      final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        ':',
        '-',
      );
      final out = Directory('work/editorial-repair/native-live')
        ..createSync(recursive: true);
      final report = {
        'checkedAt': snapshot.generatedAt.toIso8601String(),
        'providerMode': 'native-direct-rss',
        'platform': Platform.operatingSystem,
        'registrySha256': sha256.convert(registryBytes).toString(),
        'networkRequests': transport.responses.length,
        'sourceDiagnostics': result.providerState!['sources'],
        'scheduler': result.providerState!['scheduler'],
        'transports': transport.responses,
        'resolvedPublisherAddresses': transport.addresses,
        'eligibleItems': snapshot.items.length,
        'warning': result.warning,
        'imageRequests': 0,
        'scope':
            'Actual production native DNS-pinned/TLS-verified transport on host; no image downloads, no user data, no claim of iPhone execution. Publisher checkpoints preserved and extended by coordinated probe holds.',
      };
      await File('${out.path}/$stamp.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
      expect(transport.responses.length, lessThanOrEqualTo(12));
      expect(snapshot.sources, hasLength(registry.sources.length));
      expect(
        snapshot.items.every(
          (item) => eligibility.accepts(item, now: DateTime.now().toUtc()),
        ),
        isTrue,
      );
    }, _LiveHttp()),
    skip: !const bool.fromEnvironment('WINGMAN_EDITORIAL_NATIVE_LIVE'),
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
