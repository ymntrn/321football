import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException, rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Opens the shipped SQLite database.
///
/// The asset is ~62 MB and sqflite can only open a real file, so on first
/// launch it is copied out of the bundle into the app's documents directory.
/// That copy is the slow part of a cold start — everything after it is
/// instant, and the copy never repeats unless [assetVersion] changes.
///
/// On Android the copy is STREAMED by MainActivity.kt in 1 MB chunks, with
/// [progress] updated as it goes, rather than loaded whole with
/// `rootBundle.load()` — which held all 62 MB in memory before writing a
/// byte. Anywhere the native side is unavailable (another platform, tests),
/// it falls back to the old whole-file load.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _assetPath = 'assets/db/321_football.db';
  static const _fileName = '321_football.db';

  static const _copyChannel = MethodChannel('football321/asset_copy');

  /// Bump this whenever a new database is dropped into assets/, otherwise the
  /// stale copy on disk wins and the new data never appears.
  static const assetVersion = 1;

  Database? _db;

  /// First-launch copy progress, 0 to 1. Null while the size is unknown or
  /// when no copy is needed — the splash shows an indeterminate bar then.
  final ValueNotifier<double?> progress = ValueNotifier(null);

  /// True while the asset is being copied, so the splash can say why it is
  /// waiting.
  final ValueNotifier<bool> copying = ValueNotifier(false);

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

    final needsCopy =
        !await File(path).exists() ||
        !await stamp.exists() ||
        (await stamp.readAsString()).trim() != '$assetVersion';

    if (needsCopy) {
      copying.value = true;
      try {
        await _copyAsset(path);
      } finally {
        copying.value = false;
      }
      // Only after the copy has fully landed: a copy killed half way leaves
      // the stamp stale, so the next launch copies again.
      await stamp.writeAsString('$assetVersion');
    }

    _db = await openDatabase(path, readOnly: true);
    return _db!;
  }

  Future<void> _copyAsset(String path) async {
    if (!kIsWeb && Platform.isAndroid) {
      _copyChannel.setMethodCallHandler((call) async {
        if (call.method != 'progress') return;
        final args = Map<String, Object?>.from(call.arguments as Map);
        final done = (args['done'] as num).toDouble();
        final total = (args['total'] as num).toDouble();
        progress.value = total > 0 ? (done / total).clamp(0.0, 1.0) : null;
      });
      try {
        await _copyChannel.invokeMethod<int>('copy', {
          'asset': _assetPath,
          'dest': path,
        });
        progress.value = 1;
        return;
      } on MissingPluginException {
        // No native side (an engine without MainActivity's channel) —
        // fall through to the whole-file load.
      } on PlatformException catch (e) {
        debugPrint('streamed asset copy failed, falling back: ${e.message}');
      } finally {
        _copyChannel.setMethodCallHandler(null);
      }
    }

    final data = await rootBundle.load(_assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    await File(path).writeAsBytes(bytes, flush: true);
    progress.value = 1;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
