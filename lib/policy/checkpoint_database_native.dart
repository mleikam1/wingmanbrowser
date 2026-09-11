import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

Future<Database> openPolicyCheckpointDatabase(
  OpenDatabaseOptions options,
) async {
  final String directory;
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    final value = await const MethodChannel(
      'wingman/browser',
    ).invokeMethod<String>('localDataDirectory');
    if (value == null || value.isEmpty) {
      throw StateError('Policy checkpoint unavailable');
    }
    directory = value;
  } else {
    directory = await getDatabasesPath();
  }
  return databaseFactory.openDatabase(
    path.join(directory, 'policy-trust.db'),
    options: options,
  );
}
