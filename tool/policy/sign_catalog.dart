import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as path;

Future<String> digest(List<int> bytes) async => (await Sha256().hash(
  bytes,
)).bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Pass an external development-key file path.');
  }
  final root = Directory.current.resolveSymbolicLinksSync();
  final keyPath = path.normalize(path.absolute(args.single));
  final parent = Directory(path.dirname(keyPath));
  await parent.create(recursive: true);
  final keyFile = File(
    path.join(await parent.resolveSymbolicLinks(), path.basename(keyPath)),
  );
  if (keyFile.path == root || keyFile.path.startsWith('$root/')) {
    throw ArgumentError('Signing seeds must remain outside the repository.');
  }
  SimpleKeyPair key;
  if (await keyFile.exists()) {
    key = await Ed25519().newKeyPairFromSeed(
      base64Decode((await keyFile.readAsString()).trim()),
    );
  } else {
    key = await Ed25519().newKeyPair();
    await keyFile.parent.create(recursive: true);
    await keyFile.writeAsString(
      '${base64Encode(await key.extractPrivateKeyBytes())}\n',
      flush: true,
    );
    if (!Platform.isWindows) await Process.run('chmod', ['600', keyFile.path]);
  }
  final catalog =
      jsonDecode(await File('assets/policy/catalog.source.json').readAsString())
          as Map<String, dynamic>;
  final records = catalog['resources'] as List;
  for (final raw in records) {
    final row = raw as Map<String, dynamic>;
    final id = row['id'] as String;
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,79}$').hasMatch(id) ||
        row['assetPath'] != 'assets/policy/articles/$id.txt') {
      throw FormatException('Invalid resource asset scope');
    }
    final bytes = await File(row['assetPath'] as String).readAsBytes();
    row['sha256'] = await digest(bytes);
    row['byteLength'] = bytes.length;
    row['capability'] = 'bundledPlainText';
  }
  catalog['revokedIds'] ??= <String>[];
  final bytes = utf8.encode(
    '${const JsonEncoder.withIndent('  ').convert(catalog)}\n',
  );
  final payload = utf8.encode(
    jsonEncode({
      'schema': 1,
      'policyVersion': 1,
      'capability': 'bundledPlainText',
      'version': catalog['version'],
      'sequence': catalog['sequence'],
      'catalogSha256': await digest(bytes),
      'catalogBytes': bytes.length,
      'resourceCount': records.length,
    }),
  );
  final signature = await Ed25519().sign(payload, keyPair: key);
  const keyId = 'wingman-development-policy-1';
  await File('assets/policy/catalog.json').writeAsBytes(bytes, flush: true);
  await File('assets/policy/manifest.json').writeAsString(
    '${jsonEncode({'keyId': keyId, 'payload': base64Encode(payload), 'signature': base64Encode(signature.bytes)})}\n',
    flush: true,
  );
  await File('assets/policy/public_keys.json').writeAsString(
    '${jsonEncode({keyId: base64Encode((await key.extractPublicKey()).bytes)})}\n',
    flush: true,
  );
  stdout.writeln(
    'Signed ${records.length} bundled records (${bytes.length} catalog bytes). Development seed remains outside the repository.',
  );
}
