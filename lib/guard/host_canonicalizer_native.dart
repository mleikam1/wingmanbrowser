import 'package:flutter/services.dart';

Future<String?> canonicalizeHost(String host) async {
  try {
    return await const MethodChannel(
      'wingman/browser',
    ).invokeMethod<String>('normalizeHost', {'host': host});
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
