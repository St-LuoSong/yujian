import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Cached payload plus the moment it was written.
class CachedEntry {
  const CachedEntry(this.payload, this.updatedAt);

  final Object? payload;
  final DateTime updatedAt;
}

/// Minimal JSON file cache used for offline reading.
///
/// Only the discovered catalog and the most recent trip plan are cached today.
/// Everything lives in one directory, so clearing the cache is a single delete
/// and no business data leaks into the app documents folder.
class LocalCache {
  LocalCache(this.directory);

  static const String catalogKey = 'catalog';
  static const String latestPlanKey = 'latest_plan';

  final Directory directory;

  static Future<LocalCache> open() async {
    final base = await getApplicationSupportDirectory();
    final directory =
        Directory('${base.path}${Platform.pathSeparator}offline_cache');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return LocalCache(directory);
  }

  Future<bool> write(String key, Object? value, {DateTime? updatedAt}) async {
    try {
      final envelope = <String, Object?>{
        'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
        'payload': value,
      };
      await _fileFor(key).writeAsString(jsonEncode(envelope), flush: true);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<CachedEntry?> read(String key) async {
    final file = _fileFor(key);
    try {
      if (!await file.exists()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        await clear(key);
        return null;
      }
      final updatedAt =
          DateTime.tryParse(decoded['updatedAt']?.toString() ?? '');
      if (updatedAt == null) {
        await clear(key);
        return null;
      }
      return CachedEntry(decoded['payload'], updatedAt);
    } on FormatException {
      await clear(key);
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> clear(String key) async {
    try {
      final file = _fileFor(key);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Nothing to do: the entry is unreadable anyway.
    }
  }

  /// Total bytes currently held by the offline payload cache.
  Future<int> sizeBytes() async {
    try {
      if (!await directory.exists()) {
        return 0;
      }
      int total = 0;
      await for (final entity in directory.list()) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } on FileSystemException {
      return 0;
    }
  }

  /// Removes every cached payload. Business data on the server is untouched.
  Future<void> clearAll() async {
    try {
      if (!await directory.exists()) {
        return;
      }
      await for (final entity in directory.list()) {
        if (entity is File) {
          await entity.delete();
        }
      }
    } on FileSystemException {
      // Nothing else to do; the next read will rebuild what it can.
    }
  }

  File _fileFor(String key) =>
      File('${directory.path}${Platform.pathSeparator}$key.json');
}
