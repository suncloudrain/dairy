import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/database/app_database.dart';
import '../data/repositories/diary_repository.dart';
import '../data/repositories/task_repository.dart';

/// One composition root. Platform details do not leak into features.
final class AppDependencies {
  AppDependencies(this.database)
    : diaries = DiaryRepository(database),
      tasks = TaskRepository(database);

  final AppDatabase database;
  final DiaryRepository diaries;
  final TaskRepository tasks;

  static Future<AppDependencies> initialize() async {
    final DatabaseFactory factory;
    if (Platform.isWindows) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    } else if (Platform.isAndroid || Platform.isIOS) {
      // iOS can reuse this boundary, but is not yet a generated/tested target.
      factory = mobile.databaseFactory;
    } else {
      throw UnsupportedError('This platform is not configured.');
    }
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final database = await AppDatabase.open(
      factory: factory,
      path: path.join(directory.path, 'dairy.sqlite'),
    );
    return AppDependencies(database);
  }

  Future<void> close() => database.close();
}
