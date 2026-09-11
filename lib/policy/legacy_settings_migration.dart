import 'dart:convert';

/// Compatibility input is never authoritative. Retain only additional blocks.
String retireLegacyGuardSettings(String input) {
  Map<dynamic, dynamic> old = const {};
  try {
    if (input.length <= 65536) {
      final value = jsonDecode(input);
      if (value is Map) old = value;
    }
  } catch (_) {
    /* An unreadable preference cannot disable the baseline. */
  }
  final blocks =
      (old['customBlock'] is List ? old['customBlock'] as List : const [])
          .whereType<String>()
          .where((s) => s.length <= 253 && RegExp(r'^[a-z0-9.-]+$').hasMatch(s))
          .take(200)
          .toSet()
          .toList()
        ..sort();
  return jsonEncode({
    'schema': 2,
    'mandatoryPolicyVersion': 1,
    'guardEnabled': true,
    'enabledCategories': [
      'adult',
      'alcohol',
      'recreational-drugs',
      'gambling',
      'tobacco-vaping',
    ],
    'customBlock': blocks,
    'customAllow': <String>[],
    'overridesAllowed': false,
    'trackingProtection': true,
    'dangerousDownloadProtection': true,
  });
}
