import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/policy/strict_search_policy.dart';

void main() {
  const policy = StrictSearchPolicy();
  final fixture =
      jsonDecode(
            File('test/fixtures/strict_search_cases.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

  for (final entry in cases) {
    final operation = entry['operation'] as String;
    final input = entry['input'] as String;
    test('$operation: ${entry['name']}', () {
      Object? invoke() => switch (operation) {
        'buildQuery' => policy.buildQuery(input).toString(),
        'rewriteProviderInput' =>
          policy.rewriteProviderInput(input)?.toString(),
        'acceptsCanonical' => policy.acceptsCanonical(Uri.parse(input)),
        'unwrapResultLink' =>
          policy.unwrapResultLink(Uri.parse(input))?.toString(),
        _ => throw StateError('Unknown shared fixture operation $operation'),
      };
      if (entry['throwsFormatException'] == true) {
        expect(invoke, throwsFormatException);
      } else {
        expect(invoke(), entry['expected']);
      }
    });
  }

  test(
    'every successfully built or rewritten URL passes the native contract',
    () {
      for (final entry in cases) {
        if (!{
              'buildQuery',
              'rewriteProviderInput',
            }.contains(entry['operation']) ||
            entry['expected'] is! String) {
          continue;
        }
        final uri = Uri.parse(entry['expected'] as String);
        expect(
          policy.acceptsCanonical(uri),
          isTrue,
          reason: entry['name'] as String,
        );
        expect(policy.rewriteProviderInput(uri.toString()), uri);
        expect(uri.queryParametersAll.keys, orderedEquals(['q', 'kp']));
        expect(uri.queryParametersAll['kp'], ['1']);
        expect(uri.hasFragment, isFalse);
      }
    },
  );

  test('unpaired UTF16 surrogates are rejected before UTF8 replacement', () {
    for (final codeUnit in [0xd800, 0xdbff, 0xdc00, 0xdfff]) {
      expect(
        () => policy.buildQuery(String.fromCharCode(codeUnit)),
        throwsFormatException,
      );
    }
  });

  test('publisher limits match the shared language-independent fixture', () {
    expect(fixture['schemaVersion'], 1);
    expect(fixture['providerId'], StrictSearchPolicy.providerId);
    expect(fixture['maxUnicodeScalars'], StrictSearchPolicy.maxQueryCharacters);
    expect(fixture['maxUtf8Bytes'], StrictSearchPolicy.maxQueryUtf8Bytes);
  });
}
