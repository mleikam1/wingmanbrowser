import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

Future<Database> openLocalDatabase(OpenDatabaseOptions options) async {
  // Apple adapters return the app-owned Application Support directory, outside
  // shared Documents/Downloads, with their native backup-exclusion policy.
  final String directory;
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    final nativeDirectory = await const MethodChannel(
      'wingman/browser',
    ).invokeMethod<String>('localDataDirectory');
    if (nativeDirectory == null || nativeDirectory.isEmpty) {
      throw StateError('Protected local storage is unavailable.');
    }
    directory = nativeDirectory;
  } else {
    directory = await getDatabasesPath();
  }
  return databaseFactory.openDatabase(
    path.join(directory, 'wingman.db'),
    options: options,
  );
}
