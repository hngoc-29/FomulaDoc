import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// One saved snapshot of a document, taken right before an editor Save
/// overwrote the original file.
class DocVersion {
  final String   path;       // path to the backup file on disk
  final DateTime savedAt;
  final int      sizeBytes;

  const DocVersion({
    required this.path,
    required this.savedAt,
    required this.sizeBytes,
  });
}

/// Keeps a small rolling history of previous versions of a document,
/// so an in-app edit that goes wrong isn't unrecoverable.
///
/// Versions are stored in the app's own support directory (not next to the
/// original file), named `<safeOriginalName>__<timestamp>.bak`, so this
/// never clutters the user's file manager view and never risks colliding
/// with or overwriting unrelated files.
class VersionHistoryService {
  static const _maxVersionsPerFile = 5;

  Future<Directory> _versionsDir() async {
    final base = await getApplicationSupportDirectory();
    final dir  = Directory('${base.path}/doc_versions');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _safeName(String originalPath) {
    final name = originalPath.split(Platform.pathSeparator).last;
    return name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  /// Snapshot [originalPath]'s CURRENT on-disk content before it gets
  /// overwritten. Call this immediately before writing new bytes to the
  /// original file. Silently trims older versions beyond
  /// [_maxVersionsPerFile] for the same source file.
  Future<void> snapshotBeforeSave(String originalPath) async {
    final file = File(originalPath);
    if (!await file.exists()) return;

    final dir = await _versionsDir();
    final safe = _safeName(originalPath);
    final ts   = DateTime.now().millisecondsSinceEpoch;
    final backupPath = '${dir.path}/${safe}__$ts.bak';

    try {
      await file.copy(backupPath);
    } catch (_) {
      // Non-fatal: if backup fails (e.g. low storage), proceed with save
      // anyway rather than blocking the user's work.
      return;
    }

    await _trimOldVersions(dir, safe);
  }

  Future<void> _trimOldVersions(Directory dir, String safeName) async {
    final versions = await listVersions(safeName);
    if (versions.length <= _maxVersionsPerFile) return;
    final toDelete = versions.sublist(_maxVersionsPerFile);
    for (final v in toDelete) {
      try { await File(v.path).delete(); } catch (_) {}
    }
  }

  /// List saved versions for a given original file path, newest first.
  Future<List<DocVersion>> listVersionsForPath(String originalPath) =>
      listVersions(_safeName(originalPath));

  Future<List<DocVersion>> listVersions(String safeName) async {
    final dir = await _versionsDir();
    if (!await dir.exists()) return const [];

    final prefix = '${safeName}__';
    final matches = <DocVersion>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final base = entity.path.split(Platform.pathSeparator).last;
      if (!base.startsWith(prefix) || !base.endsWith('.bak')) continue;
      final tsStr = base.substring(prefix.length, base.length - 4);
      final ts = int.tryParse(tsStr);
      if (ts == null) continue;
      final stat = await entity.stat();
      matches.add(DocVersion(
        path:      entity.path,
        savedAt:   DateTime.fromMillisecondsSinceEpoch(ts),
        sizeBytes: stat.size,
      ));
    }
    matches.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return matches;
  }

  /// Read the raw bytes of a saved version (for restore or preview).
  Future<Uint8List> readVersion(DocVersion v) => File(v.path).readAsBytes();

  /// Restore [version] by copying it back over [originalPath].
  /// The CURRENT content is itself snapshotted first, so restoring is safe
  /// to undo as well.
  Future<void> restore(String originalPath, DocVersion version) async {
    await snapshotBeforeSave(originalPath);
    final bytes = await readVersion(version);
    await File(originalPath).writeAsBytes(bytes);
  }
}
