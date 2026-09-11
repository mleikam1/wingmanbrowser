// DEVELOPMENT ENTRYPOINT ONLY. No production file may import this helper.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Call before runApp or any ordinary binding initialization in the debug gallery.
/// Fails rather than silently leaving a normal messenger in the synthetic tool.
void initializeGalleryClipboardIsolation() {
  if (!kDebugMode) return;
  final existing = BindingBase.debugBindingType();
  if (existing == GalleryClipboardBinding) return;
  if (existing != null) {
    throw StateError(
      'Initialize the synthetic gallery binding before any other binding.',
    );
  }
  GalleryClipboardBinding();
}

class GalleryClipboardBinding extends WidgetsFlutterBinding {
  @override
  BinaryMessenger createBinaryMessenger() =>
      GalleryClipboardMessenger(super.createBinaryMessenger());
}

/// Intercepts only Flutter Clipboard.* calls on flutter/platform. No supplied
/// text is retained, logged, forwarded or written to the system clipboard.
/// Incoming events and other outgoing messages retain the delegate's ordering.
/// This does not claim control of OS/browser actions outside Flutter's API.
class GalleryClipboardMessenger implements BinaryMessenger {
  GalleryClipboardMessenger(this.delegate);
  final BinaryMessenger delegate;
  static const _codec = JSONMethodCodec();

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (channel != 'flutter/platform') return delegate.send(channel, message);
    MethodCall call;
    try {
      if (message == null) throw const FormatException();
      call = _codec.decodeMethodCall(message);
    } catch (_) {
      return Future.value(
        _codec.encodeErrorEnvelope(
          code: 'gallery-platform-message',
          message: 'Malformed synthetic platform request.',
        ),
      );
    }
    if (!call.method.startsWith('Clipboard.')) {
      return delegate.send(channel, message);
    }
    return Future.value(switch (call.method) {
      'Clipboard.hasStrings' => _codec.encodeSuccessEnvelope({'value': false}),
      'Clipboard.getData' ||
      'Clipboard.setData' => _codec.encodeSuccessEnvelope(null),
      _ => _codec.encodeErrorEnvelope(
        code: 'gallery-clipboard-disabled',
        message: 'System clipboard is unavailable in this synthetic gallery.',
      ),
    });
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      delegate.setMessageHandler(channel, handler);

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) =>
      // Required interface forwarding for Flutter's deprecated compatibility API.
      // ignore: deprecated_member_use
      delegate.handlePlatformMessage(channel, data, callback);
}
