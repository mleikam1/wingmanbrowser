import 'dart:convert';

/// Versioned feature documents share Wingman's existing local database. This
/// contract is not a sync transport and accepts no arbitrary namespace.
abstract interface class SignatureDocumentStore {
  static const keys = {
    'workspace',
    'privacy',
    'compatibility',
    'ui',
    'launchpad',
    'browserSession',
    'liveContentPreferences',
    'liveContentCache',
    'liveContentSaved',
    'liveContentRefreshState',
  };
  static const maximumBytes = 512 * 1024;
  Future<Map<String, Object?>?> readDocument(String key);
  Future<void> writeDocument(String key, Map<String, Object?> value);
}

Map<String, Object?> checkedDocument(String key, Map<String, Object?> value) {
  if (!SignatureDocumentStore.keys.contains(key)) {
    throw const FormatException('Unknown local feature document.');
  }
  final text = jsonEncode(value);
  if (utf8.encode(text).length > SignatureDocumentStore.maximumBytes) {
    throw const FormatException('Local feature storage limit reached.');
  }
  return Map<String, Object?>.from(jsonDecode(text) as Map);
}

class MemorySignatureDocumentStore implements SignatureDocumentStore {
  final Map<String, Map<String, Object?>> _documents = {};
  @override
  Future<Map<String, Object?>?> readDocument(String key) async {
    final value = _documents[key];
    return value == null ? null : checkedDocument(key, value);
  }

  @override
  Future<void> writeDocument(String key, Map<String, Object?> value) async {
    _documents[key] = checkedDocument(key, value);
  }
}

/// A private/unknown/student scope never reads or writes the owner's backing
/// document store, even if a feature mistakenly asks to save its state.
class SessionSignatureDocumentStore implements SignatureDocumentStore {
  SessionSignatureDocumentStore(
    SignatureDocumentStore backing, {
    required bool ephemeral,
  }) : _backing = ephemeral ? MemorySignatureDocumentStore() : backing;
  final SignatureDocumentStore _backing;
  @override
  Future<Map<String, Object?>?> readDocument(String key) =>
      _backing.readDocument(key);
  @override
  Future<void> writeDocument(String key, Map<String, Object?> value) =>
      _backing.writeDocument(key, value);
}
