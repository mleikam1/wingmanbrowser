import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Uses a bundled SQLite WASM worker and this origin's IndexedDB. No network
/// persistence or Wingman backend is involved.
Future<Database> openLocalDatabase(OpenDatabaseOptions options) =>
    databaseFactoryFfiWeb.openDatabase('wingman.db', options: options);
