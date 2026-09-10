import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

Future<Database> openLocalDatabase(OpenDatabaseOptions options) async {
  // iOS exposes user downloads in Files. Keep browser data in Application
  // Support, outside shared Documents, and excluded from OS cloud backups.
  final String directory;
  if (defaultTargetPlatform == TargetPlatform.iOS) {
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
