import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future<Database> openGuardDatabase(OpenDatabaseOptions options) =>
    databaseFactoryFfiWeb.openDatabase('guard.db', options: options);
