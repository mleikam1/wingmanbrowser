import 'dart:async';

import 'package:flutter/services.dart';

import 'consumer_update_manifest.dart';

final class PreparedConsumerPolicy {
  const PreparedConsumerPolicy(this.token, this.sequence, this.sha256);
  final String token, sha256;
  final int sequence;
}

/// Preparation must independently authenticate and compile the native policy.
/// Activation keeps a previous generation until durable Dart commit succeeds.
abstract interface class ConsumerPolicyInstaller {
  Future<PreparedConsumerPolicy?> prepare(
    VerifiedConsumerUpdate update, {
    bool restore = false,
  });
  Future<bool> activate(PreparedConsumerPolicy prepared);
  Future<void> discard(PreparedConsumerPolicy prepared);
  Future<bool> revert(PreparedConsumerPolicy prepared);
}

class NativeConsumerPolicyInstaller implements ConsumerPolicyInstaller {
  const NativeConsumerPolicyInstaller();
  static const _channel = MethodChannel('wingman/protected-browser');
  static const preparationTimeout = Duration(seconds: 45);
  static const commandTimeout = Duration(seconds: 10);
  @override
  Future<PreparedConsumerPolicy?> prepare(
    VerifiedConsumerUpdate update, {
    bool restore = false,
  }) async {
    try {
      final result = await _channel
          .invokeMapMethod<String, Object?>('prepareConsumerPolicy', {
            'envelope': update.manifest.envelope,
            'data': update.data,
            'restore': restore,
          })
          .timeout(preparationTimeout);
      if (result?['ready'] != true ||
          result?['sequence'] != update.manifest.sequence ||
          result?['sha256'] != update.manifest.sha256 ||
          result?['token'] is! String ||
          (result!['token'] as String).isEmpty) {
        return null;
      }
      return PreparedConsumerPolicy(
        result['token'] as String,
        update.manifest.sequence,
        update.manifest.sha256,
      );
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> activate(PreparedConsumerPolicy prepared) async {
    final result = await _channel
        .invokeMapMethod<String, Object?>('activateConsumerPolicy', {
          'token': prepared.token,
        })
        .timeout(commandTimeout);
    return result?['activated'] == true &&
        result?['sequence'] == prepared.sequence &&
        result?['sha256'] == prepared.sha256;
  }

  @override
  Future<void> discard(PreparedConsumerPolicy prepared) async {
    await _channel
        .invokeMethod<void>('discardConsumerPolicy', {'token': prepared.token})
        .timeout(commandTimeout);
  }

  @override
  Future<bool> revert(PreparedConsumerPolicy prepared) async {
    final result = await _channel
        .invokeMapMethod<String, Object?>('revertConsumerPolicy', {
          'token': prepared.token,
        })
        .timeout(commandTimeout);
    return result?['reverted'] == true;
  }
}
