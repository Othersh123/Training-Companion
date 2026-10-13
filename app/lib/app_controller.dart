import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'dart:io';

import 'backup/drive_backup.dart';
import 'coros/coros_auth.dart';
import 'coros/coros_mcp.dart';
import 'coros/parsers.dart';
import 'data/goal.dart';
import 'data/app_database.dart';
import 'data/food_store.dart';
import 'sync/coros_sync.dart';
import 'sync/morning_runner.dart';

/// App-wide state for the UI: the database, the Coros connection and today's check.
class AppController extends ChangeNotifier {
  AppController(this.db);

  final AppDatabase db;
  late final CorosAuth auth = CorosAuth((m) => debugPrint('TC_AUTH $m'));
  late final CorosSync sync = CorosSync(db, McpToolCaller(CorosMcp(auth)));

  bool signedIn = false;
  bool onboarded = false;
  String? nickname;
  StoredCheck? today;
  List<ScheduledWorkout> todaysWorkouts = [];
  DateTime? lastChecked;
  String? busy;
  String? lastError;

  List<Goal> goals = [];
  DateTime? capSetAt;

  /// PRD, easy-run cap: prompt a threshold test every 8 weeks, or after a race.
  String? get retestReason {
    final set = capSetAt;
    if (set == null) return null;
    final now = DateTime.now();
    final race = goals.where((g) => g.type == GoalType.race && g.date != null).map((g) => g.date!).where((d) => d.isBefore(now) && d.isAfter(set)).firstOrNull;
    if (race != null && now.difference(race).inDays <= 21) return "You've raced since you last set your easy-run cap.";
    if (now.difference(set).inDays >= 56) return "It's been 8 weeks since you set your easy-run cap.";
    return null;
  }
  Goal? get primaryGoal => goals.where((g) => g.primary).firstOrNull;

  Future<void> load() async {
    signedIn = await auth.loadTokens() != null;
    onboarded = await db.setting(SettingKeys.onboarded) == 'true';
    nickname = await db.setting(SettingKeys.nickname);
    goals = await db.goals();
    // The retest reminder counts from when the cap was set; caps set before M3 count from now.
    if (await db.setting(SettingKeys.easyRunHrCap) != null && await db.setting(SettingKeys.capSetAt) == null) {
      await db.setSetting(SettingKeys.capSetAt, DateTime.now().toIso8601String());
    }
    capSetAt = DateTime.tryParse(await db.setting(SettingKeys.capSetAt) ?? '');
    mapTilesKey = await db.setting(SettingKeys.mapTilesKey);
    await refreshToday();
  }

  /// Re-reads today's stored check; the background job may have updated it.
  Future<void> refreshToday() async {
    final date = corosDateOf(DateTime.now());
    today = await db.checkOn(date);
    todaysWorkouts = await db.scheduleOn(date);
    notifyListeners();
  }

  Future<T?> _run<T>(String label, Future<T> Function() task) async {
    if (busy != null) return null;
    busy = label;
    lastError = null;
    notifyListeners();
    try {
      return await task();
    } catch (e) {
      lastError = e.toString().replaceFirst('Exception: ', '');
      await db.logError('app', '$label: $e');
      return null;
    } finally {
      busy = null;
      notifyListeners();
    }
  }

  Future<bool> signIn() async {
    final ok = await _run('Connecting to Coros', () async {
      await auth.signIn();
      signedIn = true;
      final profile = parseUserInfo(await CorosMcp(auth).callTool('queryUserInfo', {}));
      nickname = profile.nickname;
      await db.setSetting(SettingKeys.nickname, profile.nickname);
      return true;
    });
    return ok ?? false;
  }

  /// Deletes the tokens from the phone. Coros can't revoke them for a public client (L12),
  /// so the Settings screen also explains how to remove access on the Coros side.
  Future<void> disconnect() async {
    await auth.signOut();
    signedIn = false;
    notifyListeners();
  }

  Future<void> importHistory(void Function(String step, double progress) onProgress) =>
      _run('Importing 12 weeks', () => sync.importHistory(DateTime.now(), onProgress: onProgress));

  Future<void> checkNow() => _run('Checking Coros', () async {
        final now = DateTime.now();
        final wake = parseWakeTime(await db.setting(SettingKeys.wakeTime)) ?? (6, 30);
        final windowEnd = DateTime(now.year, now.month, now.day, wake.$1, wake.$2).add(MorningRunner.window);
        await MorningRunner.runNow(db, now, windowClosed: !now.isBefore(windowEnd), fromUser: true);
        lastChecked = now;
        await refreshToday();
      });

  Future<void> finishOnboarding() async {
    await db.setSetting(SettingKeys.onboarded, 'true');
    onboarded = true;
    await scheduleMorningSync();
    notifyListeners();
  }

  late final DriveBackup backup = DriveBackup(db);

  Future<bool> connectBackup() async =>
      await _run('Connecting Google Drive', () async {
        await backup.connect();
        return backup.backupNow(interactive: true);
      }) ??
      false;

  Future<void> disconnectBackup() => _run('Disconnecting Google Drive', backup.disconnect);

  Future<bool> backupNow() async => await _run('Backing up', () => backup.backupNow(interactive: true)) ?? false;

  /// Replaces this phone's data with the Drive backup, then closes the app so it reopens on it.
  /// Coros tokens aren't in the backup, so Coros asks for sign-in again if this is a new phone.
  Future<bool> restoreFromDrive() async {
    final file = await _run('Restoring', backup.download);
    if (file == null) {
      lastError ??= 'No backup found in your Google Drive';
      notifyListeners();
      return false;
    }
    await db.close();
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final f = File('${db.path}$suffix');
      if (await f.exists()) await f.delete();
    }
    await file.copy(db.path);
    await file.delete();
    await SystemNavigator.pop();
    return true;
  }

  Future<void> saveGoal(Goal g) async {
    await db.saveGoal(g);
    goals = await db.goals();
    notifyListeners();
  }

  Future<void> deleteGoal(Goal g) async {
    await db.deleteGoal(g.id!);
    goals = await db.goals();
    notifyListeners();
  }

  // ---- food and body log (M4)

  /// Bumped after anything the Log screen shows changes, so it reloads.
  int foodRevision = 0;

  void foodChanged() {
    foodRevision++;
    notifyListeners();
  }

  /// Pull to refresh on the Log screen: today's active calories so far, today's plan, and the
  /// Coros profile if the targets still need it.
  Future<void> refreshFood() => _run('Updating from Coros', () async {
        if (await db.setting(SettingKeys.heightCm) == null || await db.setting(SettingKeys.age) == null) await sync.syncProfile();
        // Installs from before M4 have no active-calorie history: fetch 5 weeks once.
        final now0 = DateTime.now();
        final known = await db.activeKcalBetween(corosDateOf(now0.subtract(const Duration(days: 35))), corosDateOf(now0));
        await sync.syncDailyHealth(known.length < 20 ? 35 : 2);
        final now = DateTime.now();
        await sync.syncSchedule(DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1)), now);
        await refreshToday();
        foodChanged();
      });

  Future<void> saveWeight(DateTime day, double kg) async {
    await db.saveWeight(corosDateOf(day), kg);
    foodChanged();
  }

  Future<void> deleteWeight(DateTime day) async {
    await db.deleteWeight(corosDateOf(day));
    foodChanged();
  }

  // ---- run map (M5)

  /// Bumped when routes or the home zone change, so the map and the Places card reload.
  int placesRevision = 0;
  bool placesBusy = false;

  /// Opening the map: the activity list once, then up to 10 routes now (the background job
  /// adds more through the day, inside the daily budget).
  Future<void> syncPlaces() async {
    if (placesBusy || !signedIn) return;
    placesBusy = true;
    notifyListeners();
    try {
      await MorningRunner.placesIfDue(db, DateTime.now(), owner: 'app', maxRoutes: 10);
    } catch (e) {
      await db.logError('app', 'Places: $e');
    } finally {
      placesBusy = false;
      placesRevision++;
      notifyListeners();
    }
  }

  /// CARTO Basemaps key for the dark map tiles (L50); without it, darkened OSM tiles.
  String? mapTilesKey;

  Future<void> setMapTilesKey(String key) async {
    await db.setSetting(SettingKeys.mapTilesKey, key.trim());
    mapTilesKey = key.trim();
    placesChanged();
  }

  void placesChanged() {
    placesRevision++;
    notifyListeners();
  }

  /// Sets the home privacy zone; a radius of 0 turns it off.
  Future<void> setHomeZone(double lat, double lon, double radiusM) async {
    await db.setSetting(SettingKeys.homeZoneLat, '$lat');
    await db.setSetting(SettingKeys.homeZoneLon, '$lon');
    await db.setSetting(SettingKeys.homeZoneRadiusM, '$radiusM');
    placesRevision++;
    notifyListeners();
  }

  /// A screen's data load that can't spin forever (10 Oct 2026: the owner saw endless loading
  /// with nothing in the logs). Fails after [limit], and every failure goes to the error log.
  static Duration? screenLoadLimit = const Duration(seconds: 20); // tests turn it off (fake clock)

  Future<T> screenLoad<T>(String screen, Future<T> Function() load) async {
    final sw = Stopwatch()..start();
    final limit = screenLoadLimit;
    try {
      final result = await (limit == null ? load() : load().timeout(limit));
      if (sw.elapsed > const Duration(seconds: 5)) await db.logError('ui', '$screen took ${sw.elapsed.inMilliseconds} ms to load');
      return result;
    } catch (e, st) {
      debugPrint('TC_UI $screen failed: $e\n$st');
      await db.logError('ui', '$screen failed after ${sw.elapsed.inMilliseconds} ms: $e ${st.toString().split('\n').take(4).join(' | ')}');
      rethrow;
    }
  }

  /// A tab another screen wants shown (read and cleared by the app shell).
  int? tabRequest;

  void openTab(int index) {
    tabRequest = index;
    notifyListeners();
  }

  Future<String?> setting(String key) => db.setting(key);

  Future<void> setSetting(String key, String value) async {
    await db.setSetting(key, value);
    if (key == SettingKeys.easyRunHrCap) {
      capSetAt = DateTime.now();
      await db.setSetting(SettingKeys.capSetAt, capSetAt!.toIso8601String());
    }
    notifyListeners();
  }
}

/// Makes the controller available to every screen.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child}) : super(notifier: controller);

  static AppController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
