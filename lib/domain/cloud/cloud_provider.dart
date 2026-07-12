import 'dart:typed_data';
import '../abstractions/document_source.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CLOUD DOCUMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// A document stored in a cloud provider.
class CloudDocument {
  /// Provider-specific unique identifier.
  final String id;

  /// Display name (usually the file name with extension).
  final String name;

  /// Path or folder within the cloud storage (may be null).
  final String? remotePath;

  /// When the file was last modified in the cloud.
  final DateTime? modifiedAt;

  /// File size in bytes (may be null for unresolved entries).
  final int? sizeBytes;

  /// Whether the document is shared with other users.
  final bool isShared;

  /// Thumbnail image bytes for document preview cards.
  final Uint8List? thumbnail;

  const CloudDocument({
    required this.id,
    required this.name,
    this.remotePath,
    this.modifiedAt,
    this.sizeBytes,
    this.isShared = false,
    this.thumbnail,
  });

  @override
  String toString() => 'CloudDocument(id: $id, name: $name)';
}

// ═══════════════════════════════════════════════════════════════════════════════
// SYNC STATUS
// ═══════════════════════════════════════════════════════════════════════════════

enum SyncStatus {
  /// Up-to-date with the cloud version.
  synced,

  /// Local changes not yet pushed.
  localAhead,

  /// Cloud version is newer — need to pull.
  remoteAhead,

  /// Both local and remote changed — manual merge required.
  conflict,

  /// Sync has never been performed.
  unknown,
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLOUD PROVIDER INTERFACE
// ═══════════════════════════════════════════════════════════════════════════════

/// Abstract interface every cloud storage backend must implement.
///
/// Planned implementations (Phase 6+):
///   [GoogleDriveProvider]  — Google Drive API v3
///   [OneDriveProvider]     — Microsoft Graph API
///   [DropboxProvider]      — Dropbox API v2
///   [WebDavProvider]       — WebDAV (Nextcloud, ownCloud, …)
///
/// Usage:
/// ```dart
/// final provider = GoogleDriveProvider();
/// await provider.connect();
/// final docs = await provider.listDocuments();
/// final source = await provider.download(docs.first);
/// // Open source in FormulaDoc viewer
/// ```
abstract class CloudProvider {
  // ── Identity ──────────────────────────────────────────────────────────────

  /// Short identifier used internally (e.g. "google_drive").
  String get id;

  /// Human-readable display name (e.g. "Google Drive").
  String get displayName;

  /// Whether the user has authenticated with this provider.
  bool get isConnected;

  // ── Auth lifecycle ────────────────────────────────────────────────────────

  /// Opens the OAuth2 / sign-in flow and establishes a session.
  Future<void> connect();

  /// Signs out and clears locally cached credentials.
  Future<void> disconnect();

  // ── Document listing ──────────────────────────────────────────────────────

  /// Returns DOCX (and other supported) documents in [folder].
  ///
  /// [folder] is provider-specific (e.g. a folder ID for Google Drive,
  /// a path string for WebDAV).  Pass `null` for the root.
  Future<List<CloudDocument>> listDocuments({String? folder});

  /// Searches for documents matching [query] in the cloud.
  Future<List<CloudDocument>> search(String query);

  // ── Transfer ──────────────────────────────────────────────────────────────

  /// Downloads [doc] and returns a [DocumentSource] the parser can consume.
  Future<DocumentSource> download(CloudDocument doc);

  /// Uploads the file at [localPath] to [cloudFolder].
  ///
  /// Returns the [CloudDocument] representation of the uploaded file.
  Future<CloudDocument> upload(String localPath, {String? cloudFolder});

  /// Pushes local bytes for [localPath] to an existing [remote] document.
  Future<void> sync(String localPath, CloudDocument remote);

  // ── Status ────────────────────────────────────────────────────────────────

  /// Computes the sync status of a local file relative to its cloud version.
  Future<SyncStatus> syncStatus(String localPath, CloudDocument remote);

  /// Resolves a conflict, taking either [keepLocal] or the remote version.
  Future<void> resolveConflict(
    String localPath,
    CloudDocument remote, {
    required bool keepLocal,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// BYTES CLOUD SOURCE  (used by download implementations)
// ═══════════════════════════════════════════════════════════════════════════════

/// [DocumentSource] that wraps bytes fetched from a cloud provider.
///
/// Used internally by [CloudProvider.download] implementations.
class CloudDocumentSource extends DocumentSource {
  final CloudDocument _doc;
  final Future<Uint8List> Function() _fetchBytes;

  CloudDocumentSource({
    required CloudDocument doc,
    required Future<Uint8List> Function() fetchBytes,
  })  : _doc = doc,
        _fetchBytes = fetchBytes;

  @override
  String get name => _doc.name;

  @override
  String? get path => null; // cloud document has no local path yet

  @override
  dynamic get format => null; // detected from name

  @override
  Future<Uint8List> readBytes() => _fetchBytes();

  @override
  String toString() => 'CloudDocumentSource(${_doc.name})';
}
