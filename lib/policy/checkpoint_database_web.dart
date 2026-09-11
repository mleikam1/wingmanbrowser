import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future<Database> openPolicyCheckpointDatabase(OpenDatabaseOptions options) =>
    databaseFactoryFfiWeb.openDatabase('policy-trust.db', options: options);
