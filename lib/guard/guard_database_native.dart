import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

Future<Database> openGuardDatabase(OpenDatabaseOptions options) async {
  final String directory;
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    final result = await const MethodChannel(
      'wingman/browser',
    ).invokeMethod<String>('localDataDirectory');
    if (result == null || result.isEmpty) {
      throw StateError('Local Guard storage unavailable.');
    }
    directory = result;
  } else {
    directory = await getDatabasesPath();
  }
  return databaseFactory.openDatabase(
    path.join(directory, 'guard.db'),
    options: options,
  );
}
