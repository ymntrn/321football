import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Opens the shipped SQLite database.
///
/// The asset is ~62 MB and sqflite can only open a real file, so on first
/// launch it is copied out of the bundle into the app's documents directory.
/// That copy is the slow part of a cold start — everything after it is
/// instant, and the copy never repeats unless [assetVersion] changes.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _assetPath = 'assets/db/321_football.db';
  static const _fileName = '321_football.db';

  /// Bump this whenever a new database is dropped into assets/, otherwise the
  /// stale copy on disk wins and the new data never appears.
  static const assetVersion = 1;

  Database? _db;

  Database get db {
    final database = _db;
    if (database == null) {
      throw StateError('AppDatabase.open() must complete before use.');
    }
    return database;
  }

  bool get isOpen => _db != null;

  Future<Database> open() async {
    if (_db != null) return _db!;

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _fileName);
    final stamp = File(p.join(dir.path, '.db_version'));

    final needsCopy = !await File(path).exists() ||
        !await stamp.exists() ||
        (await stamp.readAsString()).trim() != '$assetVersion';

    if (needsCopy) {
      final data = await rootBundle.load(_assetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await File(path).writeAsBytes(bytes, flush: true);
      await stamp.writeAsString('$assetVersion');
    }

    _db = await openDatabase(path, readOnly: true);
    return _db!;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
