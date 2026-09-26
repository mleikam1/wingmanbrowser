import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/rss_transport.dart';
import 'package:wingman_browser/live_content/rss_transport_native.dart';

import 'rss_provider_test.dart' as fixtures;

class _DelayedTaskClient extends Fake implements HttpClient {
  _DelayedTaskClient(this.cancelTransport);
  final void Function() cancelTransport;
  late Future<ConnectionTask<Socket>> Function(Uri, String?, int?) factory;
  bool closed = false;
  @override
  bool autoUncompress = false;
  @override
  Duration? connectionTimeout;
  @override
  set findProxy(String Function(Uri)? callback) {}
  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? callback,
  ) => factory = callback!;

  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    final task = await factory(uri, null, null);
    cancelTransport();
    // Reproduce HttpClient closing before it subscribes to the connection
    // task. A cancellation must not become an unhandled asynchronous error.
    await Future<void>.delayed(Duration.zero);
    await task.socket;
    throw StateError('A cancelled connection must never create a request.');
  }

  @override
  void close({bool force = false}) => closed = true;
}

class _Http extends HttpOverrides {
  _Http(this.client);
  final HttpClient client;
  @override
  HttpClient createHttpClient(SecurityContext? context) => client;
}

// Use the actual dart:io HttpClient connection/cancellation chain while only
// replacing TCP establishment. No socket, DNS or publisher request is opened.
class _ActualHttp extends HttpOverrides {}

void main() {
  for (final differentZone in [false, true]) {
    test(
      'actual HttpClient cancellation preserves owner error zone: $differentZone',
      () async {
        final errors = <Object>[];
        final connected = Completer<void>();
        final finished = Completer<Object>();
        late void Function() cancelInOwnerZone;
        final transport = NativeRssFeedTransport(
          resolver: (_) async => [InternetAddress('93.184.216.34')],
          connector: (address, port) async {
            final pending = Completer<Socket>();
            connected.complete();
            return ConnectionTask.fromSocket(pending.future, () {
              if (!pending.isCompleted) {
                pending.completeError(
                  const SocketException('fixture cancellation'),
                );
              }
            });
          },
        );
        HttpOverrides.runWithHttpOverrides(() {
          runZonedGuarded(() {
            cancelInOwnerZone = Zone.current.bindCallback(transport.cancel);
            transport
                .fetch(fixtures.source(), {})
                .then(
                  (_) => finished.complete(
                    StateError('Unexpected completed request'),
                  ),
                  onError: (Object error, StackTrace stack) =>
                      finished.complete(error),
                );
          }, (error, stack) => errors.add(error));
        }, _ActualHttp());
        await connected.future;
        await Future<void>.delayed(Duration.zero);
        runZonedGuarded(
          () => differentZone ? transport.cancel() : cancelInOwnerZone(),
          (error, stack) => errors.add(error),
        );
        expect(
          await finished.future.timeout(const Duration(seconds: 2)),
          isA<RssFailure>().having((e) => e.code, 'reason', 'cancelled'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(errors, isEmpty);
      },
    );
  }
  test(
    'private cancellation before connection task subscription stays handled',
    () async {
      final pendingSocket = Completer<Socket>();
      var cancelled = 0;
      final transport = NativeRssFeedTransport(
        resolver: (_) async => [InternetAddress('93.184.216.34')],
        connector: (address, port) async {
          expect(address.address, '93.184.216.34');
          expect(port, 443);
          return ConnectionTask.fromSocket(pendingSocket.future, () {
            cancelled++;
            if (!pendingSocket.isCompleted) {
              pendingSocket.completeError(const RssFailure('cancelled'));
            }
          });
        },
      );
      final client = _DelayedTaskClient(transport.cancel);
      await HttpOverrides.runWithHttpOverrides(
        () => expectLater(
          transport.fetch(fixtures.source(), {}),
          throwsA(
            isA<RssFailure>().having((e) => e.code, 'reason', 'cancelled'),
          ),
        ),
        _Http(client),
      );
      expect(cancelled, greaterThanOrEqualTo(1));
      expect(client.closed, isTrue);
      await Future<void>.delayed(Duration.zero);
    },
  );
}
