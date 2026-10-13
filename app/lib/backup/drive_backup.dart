import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;

import '../data/app_database.dart';
import 'google_config.dart';

/// Backs the database up to the hidden app-data folder of the user's own Google Drive
/// (PRD: Privacy). Coros tokens live in secure storage, not the database, so they're never in it.
class DriveBackup {
  DriveBackup(this.db);

  final AppDatabase db;

  static const _scopes = [drive.DriveApi.driveAppdataScope];
  static const _fileName = 'training_companion_backup.db';
  static const lastBackupKey = 'backup_last_at';
  static const enabledKey = 'backup_enabled';

  static bool _initialised = false;

  static Future<void> _init() async {
    if (_initialised) return;
    await GoogleSignIn.instance.initialize(serverClientId: googleWebClientId);
    _initialised = true;
  }

  static bool get configured => !googleWebClientId.startsWith('PASTE_');

  /// Interactive: picks the Google account and grants Drive app-data access. Foreground only.
  Future<void> connect() async {
    await _init();
    await GoogleSignIn.instance.authenticate(scopeHint: _scopes);
    await GoogleSignIn.instance.authorizationClient.authorizeScopes(_scopes);
    await db.setSetting(enabledKey, 'true');
  }

  Future<void> disconnect() async {
    await _init();
    await GoogleSignIn.instance.disconnect();
    await db.setSetting(enabledKey, 'false');
  }

  /// Without prompting; null if the user needs to connect (again).
  Future<drive.DriveApi?> _api({required bool interactive}) async {
    await _init();
    final client = GoogleSignIn.instance.authorizationClient;
    final authz = interactive ? await client.authorizeScopes(_scopes) : await client.authorizationForScopes(_scopes);
    return authz == null ? null : drive.DriveApi(authz.authClient(scopes: _scopes));
  }

  Future<drive.File?> _existing(drive.DriveApi api) async {
    final list = await api.files.list(spaces: 'appDataFolder', q: "name = '$_fileName'", $fields: 'files(id, modifiedTime, size)');
    return list.files?.firstOrNull;
  }

  /// Uploads a snapshot, replacing the previous backup. Returns false if Google needs the user.
  Future<bool> backupNow({bool interactive = false}) async {
    final api = await _api(interactive: interactive);
    if (api == null) return false;
    final snapshot = File(p.join(Directory.systemTemp.path, 'tc_backup_${DateTime.now().millisecondsSinceEpoch}.db'));
    try {
      await db.snapshotTo(snapshot.path);
      final media = drive.Media(snapshot.openRead(), await snapshot.length());
      final existing = await _existing(api);
      if (existing == null) {
        await api.files.create(drive.File(name: _fileName, parents: ['appDataFolder']), uploadMedia: media);
      } else {
        await api.files.update(drive.File(), existing.id!, uploadMedia: media);
      }
      await db.setSetting(lastBackupKey, DateTime.now().toIso8601String());
      return true;
    } finally {
      if (await snapshot.exists()) await snapshot.delete();
    }
  }

  /// When the backup in Drive was made, or null if there is none.
  Future<DateTime?> latestBackupTime() async {
    final api = await _api(interactive: true);
    return (await _existing(api!))?.modifiedTime;
  }

  /// Downloads the backup to a temporary file; the caller swaps it in with the database closed.
  Future<File?> download() async {
    final api = await _api(interactive: true);
    final existing = await _existing(api!);
    if (existing == null) return null;
    final media = await api.files.get(existing.id!, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final target = File(p.join(Directory.systemTemp.path, 'tc_restore.db'));
    final sink = target.openWrite();
    await media.stream.pipe(sink);
    return target;
  }

  /// Daily automatic backup after the morning check; silent if Google needs the user.
  static Future<void> dailyIfDue(AppDatabase db) async {
    if (!configured || await db.setting(enabledKey) != 'true') return;
    final last = DateTime.tryParse(await db.setting(lastBackupKey) ?? '');
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 20)) return;
    try {
      if (!await DriveBackup(db).backupNow()) await db.logError('backup', 'Google needs you to reconnect Drive backup in Settings');
    } catch (e) {
      await db.logError('backup', e.toString());
    }
  }
}
