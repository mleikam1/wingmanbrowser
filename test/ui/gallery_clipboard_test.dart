import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/ui_gallery/gallery_clipboard_binding.dart';

class _RecordingMessenger implements BinaryMessenger {
  final sent = <(String, ByteData?)>[];
  final received = <(String, ByteData?)>[];
  final handlers = <String, MessageHandler?>{};
  final response = const JSONMethodCodec().encodeSuccessEnvelope('forwarded');
  @override
  Future<ByteData?> send(String channel, ByteData? message) async {
    sent.add((channel, message));
    return response;
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {
    handlers[channel] = handler;
  }

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) async {
    received.add((channel, data));
    callback?.call(response);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const codec = JSONMethodCodec();
  test(
    'synthetic clipboard calls never reach the host and reads stay empty',
    () async {
      final host = _RecordingMessenger();
      final messenger = GalleryClipboardMessenger(host);
      Future<Object?> call(String method, [Object? args]) async =>
          codec.decodeEnvelope(
            (await messenger.send(
              'flutter/platform',
              codec.encodeMethodCall(MethodCall(method, args)),
            ))!,
          );
      expect(
        await call('Clipboard.setData', {'text': 'SYNTHETIC-DO-NOT-FORWARD'}),
        isNull,
      );
      expect(await call('Clipboard.getData', 'text/plain'), isNull);
      expect(await call('Clipboard.hasStrings'), {'value': false});
      await expectLater(
        call('Clipboard.futureOperation'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'gallery-clipboard-disabled',
          ),
        ),
      );
      expect(host.sent, isEmpty);
    },
  );
  test(
    'unrelated outgoing and incoming messages preserve delegate bytes and handlers',
    () async {
      final host = _RecordingMessenger();
      final messenger = GalleryClipboardMessenger(host);
      final first = codec.encodeMethodCall(
        const MethodCall('SystemNavigator.pop'),
      );
      final second = codec.encodeMethodCall(
        const MethodCall('Clipboard.setData', {
          'text': 'not-the-platform-channel',
        }),
      );
      expect(
        await messenger.send('flutter/platform', first),
        same(host.response),
      );
      expect(
        await messenger.send('synthetic/another-channel', second),
        same(host.response),
      );
      expect(host.sent, [
        ('flutter/platform', first),
        ('synthetic/another-channel', second),
      ]);
      Future<ByteData?> handler(ByteData? _) async => second;
      messenger.setMessageHandler('synthetic/incoming', handler);
      expect(host.handlers['synthetic/incoming'], same(handler));
      ByteData? reply;
      await messenger.handlePlatformMessage(
        'synthetic/incoming',
        second,
        (value) => reply = value,
      );
      expect(host.received, [('synthetic/incoming', second)]);
      expect(reply, same(host.response));
      messenger.setMessageHandler('synthetic/incoming', null);
      expect(host.handlers['synthetic/incoming'], isNull);
    },
  );
  test(
    'malformed platform messages fail closed; late binding setup is rejected',
    () async {
      final host = _RecordingMessenger();
      final messenger = GalleryClipboardMessenger(host);
      final reply = (await messenger.send('flutter/platform', ByteData(1)))!;
      expect(
        () => codec.decodeEnvelope(reply),
        throwsA(isA<PlatformException>()),
      );
      expect(host.sent, isEmpty);
      expect(initializeGalleryClipboardIsolation, throwsStateError);
    },
  );
}
