import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter/foundation.dart';

abstract interface class PinDerivation {
  Future<List<int>> derive(String pin, List<int> salt);
}

class Pbkdf2PinDerivation implements PinDerivation {
  const Pbkdf2PinDerivation();
  static const iterations = 600000;

  @override
  Future<List<int>> derive(String pin, List<int> salt) =>
      compute(_derive, <Object>[pin, salt]);
}

Future<List<int>> _derive(List<Object> input) async {
  final algorithm = DartPbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: Pbkdf2PinDerivation.iterations,
    bits: 256,
    // Runs in an isolate on supported mobile targets; do not delay its loop.
    pausePeriod: Duration.zero,
  );
  final key = await algorithm.deriveKey(
    secretKey: SecretKey(utf8.encode(input[0] as String)),
    nonce: input[1] as List<int>,
  );
  return key.extractBytes();
}
