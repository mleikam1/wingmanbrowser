import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as path;

/// Development-only release authoring. The key is written outside the Git
/// repository. Production distribution must provision its own protected key.
Future<void> main(List<String> args) async {
  if (args.length != 2 ||
      !const [
        '--development-key-output',
        '--development-key-input',
      ].contains(args[0])) {
    stderr.writeln(
      'Usage: dart run tool/guard/build_starter_pack.dart '
      '--development-key-output /absolute/path/outside/repository/key.json',
    );
    exitCode = 64;
    return;
  }
  final requestedKey = File(args[1]);
  final root = Directory.current.resolveSymbolicLinksSync();
  final keyDirectory = requestedKey.parent.resolveSymbolicLinksSync();
  final keyFile = File(path.join(keyDirectory, path.basename(args[1])));
  final actualKeyPath = keyFile.existsSync()
      ? keyFile.resolveSymbolicLinksSync()
      : keyFile.path;
  if (!path.isAbsolute(args[1]) ||
      path.isWithin(root, actualKeyPath) ||
      actualKeyPath == root ||
      (args[0] == '--development-key-output' && keyFile.existsSync())) {
    stderr.writeln('Use a new absolute key path outside the repository.');
    exitCode = 64;
    return;
  }
  final records = <Map<String, Object>>[];
  void add(
    String host,
    String category, {
    String kind = 'category',
    String? source,
  }) {
    records.add({
      'id': 'starter-${records.length + 1}',
      'host': host,
      'kind': kind,
      'category': category,
      'includeSubdomains': true,
      'source': ?source,
    });
  }

  for (final category in [
    'adult',
    'alcohol',
    'recreational-drugs',
    'gambling',
    'tobacco-vaping',
    'social-media',
    'shopping',
    'gaming',
    'news',
  ]) {
    add('$category.guard.test', category);
  }
  add('malware.guard.test', 'malware', kind: 'malware');
  add('phishing.guard.test', 'phishing', kind: 'phishing');
  add('download.guard.test', 'harmful-downloads', kind: 'harmful-download');
  for (final entry in <String, List<String>>{
    'adult': ['pornhub.com', 'xvideos.com'],
    'alcohol': ['heineken.com', 'budweiser.com', 'jackdaniels.com'],
    'recreational-drugs': ['eaze.com'],
    'gambling': ['bet365.com', 'draftkings.com', 'fanduel.com'],
    'tobacco-vaping': ['juul.com', 'vuse.com'],
    'social-media': [
      'facebook.com',
      'instagram.com',
      'tiktok.com',
      'reddit.com',
      'x.com',
    ],
    'shopping': ['amazon.com', 'ebay.com'],
    'gaming': ['roblox.com', 'steampowered.com'],
    'news': ['bbc.com', 'cnn.com', 'nytimes.com'],
  }.entries) {
    for (final host in entry.value) {
      add(host, entry.key, source: 'https://$host/');
    }
  }
  for (final host in [
    'support.guard.test',
    'aa.org',
    'na.org',
    'smartrecovery.org',
    'samhsa.gov',
    'findtreatment.gov',
    'poison.org',
    'cdc.gov',
    'who.int',
    'medlineplus.gov',
    'plannedparenthood.org',
    'rainn.org',
    '988lifeline.org',
    'nih.gov',
  ]) {
    add(host, '', kind: 'support', source: 'https://$host/');
  }
  final pack = utf8.encode('${records.map(jsonEncode).join('\n')}\n');
  final hash = (await Sha256().hash(
    pack,
  )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final canonical =
      records
          .map(
            (r) => [
              r['host'],
              r['kind'],
              r['category'],
              r['includeSubdomains'] == true ? 1 : 0,
              r['id'],
            ],
          )
          .toList()
        ..sort((a, b) {
          for (var i = 0; i < 3; i++) {
            final order = (a[i] as String).compareTo(b[i] as String);
            if (order != 0) return order;
          }
          return 0;
        });
  final rulesHash = (await Sha256().hash(
    utf8.encode('${canonical.map(jsonEncode).join('\n')}\n'),
  )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final payload = utf8.encode(
    jsonEncode({
      'schema': 1,
      'version': '1.0.0',
      'sequence': 1,
      'createdAt': '2026-09-10T00:00:00Z',
      'minimumAppVersion': '0.2.0',
      'coverage':
          'Limited authored starter data; not comprehensive threat or category coverage.',
      'packs': [
        {
          'filename': 'starter.ndjson',
          'sha256': hash,
          'rulesSha256': rulesHash,
          'bytes': pack.length,
          'rules': records.length,
          'license': 'CC0-1.0',
          'categories': [
            'adult',
            'alcohol',
            'recreational-drugs',
            'gambling',
            'tobacco-vaping',
            'malware',
            'phishing',
            'harmful-downloads',
            'social-media',
            'shopping',
            'gaming',
            'news',
          ],
        },
      ],
    }),
  );
  final algorithm = Ed25519();
  final key = args[0] == '--development-key-input'
      ? await algorithm.newKeyPairFromSeed(
          base64Decode(
            (jsonDecode(await keyFile.readAsString())
                    as Map<String, dynamic>)['seed']
                as String,
          ),
        )
      : await algorithm.newKeyPair();
  final public = (await key.extractPublicKey()).bytes;
  final private = await key.extractPrivateKeyBytes();
  final signature = await algorithm.sign(payload, keyPair: key);
  const keyId = 'wingman-development-2026-09';
  if (args[0] == '--development-key-output') {
    await keyFile.create(exclusive: true);
    final permissions = await Process.run('chmod', ['600', keyFile.path]);
    if (permissions.exitCode != 0) {
      throw StateError('Could not protect key permissions.');
    }
    await keyFile.writeAsString(
      jsonEncode({
        'purpose': 'DEVELOPMENT ONLY - NEVER SHIP',
        'keyId': keyId,
        'seed': base64Encode(private),
        'publicKey': base64Encode(public),
      }),
    );
  }
  final output = Directory('assets/guard');
  await output.create(recursive: true);
  await File('${output.path}/starter.ndjson').writeAsBytes(pack);
  await File('${output.path}/manifest.json').writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({'keyId': keyId, 'payload': base64Encode(payload), 'signature': base64Encode(signature.bytes)})}\n',
  );
  await File(
    '${output.path}/public_keys.json',
  ).writeAsString('${jsonEncode({keyId: base64Encode(public)})}\n');
  stdout.writeln(
    'Signed ${records.length} starter rules (${pack.length} bytes). '
    'Only the public verification key and artifacts are in the app.',
  );
}
