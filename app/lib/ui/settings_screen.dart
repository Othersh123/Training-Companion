import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../food/targets.dart';
import '../backup/drive_backup.dart';
import '../rules/morning_check.dart';
import '../sync/coros_sync.dart';
import '../sync/morning_runner.dart';
import 'theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _values = <String, String?>{};

  static const _keys = [
    SettingKeys.wakeTime,
    SettingKeys.easyRunHrCap,
    SettingKeys.notificationsOn,
    SettingKeys.restingHrRise,
    SettingKeys.sleepMinMinutes,
    SettingKeys.restingHrHistoryDays,
    SettingKeys.historyImportedAt,
    SettingKeys.weeklyReviewTime,
    DriveBackup.enabledKey,
    DriveBackup.lastBackupKey,
    SettingKeys.carbsRest,
    SettingKeys.carbsEasy,
    SettingKeys.carbsHard,
    SettingKeys.proteinGkg,
    SettingKeys.deficitCap,
    SettingKeys.heightCm,
    SettingKeys.age,
    SettingKeys.gender,
    SettingKeys.corosWeightKg,
    SettingKeys.homeZoneRadiusM,
    SettingKeys.homeZoneLat,
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  Future<void> _reload() async {
    final app = AppScope.of(context);
    for (final k in _keys) {
      _values[k] = await app.setting(k);
    }
    if (mounted) setState(() {});
  }

  Future<void> _save(String key, String value) async {
    await AppScope.of(context).setSetting(key, value);
    await _reload();
  }

  Future<void> _editNumber({required String key, required String title, required String help, required int current, int min = 1, int max = 999}) async {
    final controller = TextEditingController(text: '$current');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Tc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(title, style: Tc.title(20)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(help, style: Tc.label.copyWith(fontSize: 14)),
          const SizedBox(height: 14),
          TextField(controller: controller, keyboardType: TextInputType.number, autofocus: true, style: Tc.title(22)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Tc.textSecondary))),
          TextButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v != null && v >= min && v <= max) Navigator.pop(ctx, v);
            },
            child: const Text('Save', style: TextStyle(color: Tc.go)),
          ),
        ],
      ),
    );
    if (result != null) await _save(key, '$result');
  }

  Future<void> _editDecimal({required String key, required String title, required String help, required double current, required double min, required double max}) async {
    final controller = TextEditingController(text: current.toString());
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Tc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(title, style: Tc.title(20)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(help, style: Tc.label.copyWith(fontSize: 14)),
          const SizedBox(height: 14),
          TextField(controller: controller, keyboardType: const TextInputType.numberWithOptions(decimal: true), autofocus: true, style: Tc.title(22)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Tc.textSecondary))),
          TextButton(
            onPressed: () {
              final v = double.tryParse(controller.text.trim().replaceAll(',', '.'));
              if (v != null && v >= min && v <= max) Navigator.pop(ctx, v);
            },
            child: const Text('Save', style: TextStyle(color: Tc.go)),
          ),
        ],
      ),
    );
    if (result != null) {
      await _save(key, '$result');
      if (mounted) AppScope.of(context).foodChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    const d = Thresholds();
    const f = FoodSettings();
    double dOf(String key, double fallback) => double.tryParse(_values[key] ?? '') ?? fallback;
    String gkg(double v) => '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)} g/kg';
    int intOf(String key, int fallback) => int.tryParse(_values[key] ?? '') ?? fallback;
    final cap = int.tryParse(_values[SettingKeys.easyRunHrCap] ?? '');
    final sleepMin = intOf(SettingKeys.sleepMinMinutes, d.sleepMinMinutes);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            Row(children: [
              _BackButton(onTap: () => Navigator.pop(context)),
              const SizedBox(width: 14),
              Text('Settings', style: Tc.title(26)),
            ]),
            const SizedBox(height: 24),
            _section('COROS'),
            _Group(children: [
              _Row(
                title: app.signedIn ? 'Connected${app.nickname == null ? '' : ' as ${app.nickname}'}' : 'Not connected',
                subtitle: app.signedIn ? 'Tokens are stored only in this phone\'s secure storage' : 'Sign in to sync your watch data',
                trailing: TextButton(
                  onPressed: app.busy != null ? null : (app.signedIn ? () => _confirmDisconnect(app) : app.signIn),
                  child: Text(app.signedIn ? 'Disconnect' : 'Sign in', style: TextStyle(color: app.signedIn ? Tc.coral : Tc.go)),
                ),
              ),
              _Row(
                title: 'Re-import 12 weeks',
                subtitle: _values[SettingKeys.historyImportedAt] == null ? 'Not imported yet' : 'Last import ${_values[SettingKeys.historyImportedAt]!.substring(0, 10)}',
                onTap: app.signedIn ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportScreen())) : null,
              ),
            ]),
            _section('MORNING CHECK'),
            _Group(children: [
              _Row(
                title: 'Wake time',
                subtitle: 'Checks Coros every 15 minutes from here, for up to 2 hours',
                value: _values[SettingKeys.wakeTime] ?? 'Not set',
                onTap: () async {
                  final current = (_values[SettingKeys.wakeTime] ?? '06:30').split(':');
                  final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(current[0]), minute: int.parse(current[1])));
                  if (t != null) await _save(SettingKeys.wakeTime, '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                },
              ),
              _Row(
                title: 'Morning notification',
                subtitle: 'Once last night\'s data is in, or if it doesn\'t arrive',
                trailing: Switch(
                  value: _values[SettingKeys.notificationsOn] != 'false',
                  onChanged: (v) => _save(SettingKeys.notificationsOn, '$v'),
                ),
              ),
              _Row(
                title: 'Easy-run HR cap',
                subtitle: 'The top of your Coros Zone 2, in bpm. Coros doesn\'t share zone values, so copy it from the Coros app.',
                value: cap == null ? 'Not set' : '$cap bpm',
                onTap: () => _editNumber(key: SettingKeys.easyRunHrCap, title: 'Easy-run HR cap', help: 'Top of your Coros Zone 2, in bpm. In the Coros app: Profile, Zones, Heart rate.', current: cap ?? 150, min: 90, max: 200),
              ),
            ]),
            _section('WEEKLY REVIEW'),
            _Group(children: [
              _Row(
                title: 'Sunday summary',
                subtitle: 'Your week and one thing to change, every Sunday',
                value: _values[SettingKeys.weeklyReviewTime] ?? '19:00',
                onTap: () async {
                  final current = (_values[SettingKeys.weeklyReviewTime] ?? '19:00').split(':');
                  final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(current[0]), minute: int.parse(current[1])));
                  if (t != null) await _save(SettingKeys.weeklyReviewTime, '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                },
              ),
            ]),
            _section('RULES'),
            _Group(children: [
              _Row(
                title: 'Resting HR flag',
                subtitle: 'Flagged when today is this many bpm above your average',
                value: '+${intOf(SettingKeys.restingHrRise, d.restingHrRiseBpm)} bpm',
                onTap: () => _editNumber(key: SettingKeys.restingHrRise, title: 'Resting HR flag', help: 'Flag resting HR when it is at least this many bpm above your average.', current: intOf(SettingKeys.restingHrRise, d.restingHrRiseBpm), max: 20),
              ),
              _Row(
                title: 'Resting HR average',
                subtitle: 'Days of history the average uses',
                value: '${intOf(SettingKeys.restingHrHistoryDays, d.restingHrHistoryDays)} days',
                onTap: () => _editNumber(key: SettingKeys.restingHrHistoryDays, title: 'Resting HR average', help: 'Number of days of resting HR history to average.', current: intOf(SettingKeys.restingHrHistoryDays, d.restingHrHistoryDays), min: 7, max: 90),
              ),
              _Row(
                title: 'Sleep flag',
                subtitle: 'Flagged when last night\'s main sleep, naps excluded, is shorter than this',
                value: formatMinutes(sleepMin),
                onTap: () => _editNumber(key: SettingKeys.sleepMinMinutes, title: 'Sleep flag, in minutes', help: 'Flag sleep when time asleep in last night\'s main sleep is under this many minutes. 360 is 6 hours.', current: sleepMin, min: 120, max: 720),
              ),
            ]),
            const SizedBox(height: 12),
            TcCard(
              child: Text(
                'How the verdict works\n\n'
                'HRV is flagged when Coros rates last night below your normal range. '
                'Load is flagged when Coros labels it ${d.excessiveLoadLabel}; the app uses the Coros label as given.\n\n'
                'No flags: Go as planned. One flag: Go easy, keep the session but cap heart rate and cut intensity. '
                'Two or more: Rest, or 20 to 30 minutes very easy. With fewer than two signals available, there is no verdict.\n\n'
                'A signal Coros has no data for is left out. A reply the app can\'t read is shown as an error, never as missing data.\n\n'
                'A run counts as easy when your plan says so: no section longer than a minute at Zone 3 or above, and not a long run. '
                'On days without a plan, any run under ${d.easyRunMaxMinutes} minutes counts as easy.',
                style: Tc.label.copyWith(fontSize: 14, height: 1.45),
              ),
            ),
            _section('FOOD TARGETS'),
            _Group(children: [
              _Row(
                title: 'Your profile',
                subtitle: _values[SettingKeys.heightCm] == null
                    ? 'Not fetched yet. Tap to fetch height, weight, age and sex from Coros'
                    : 'From Coros: ${double.parse(_values[SettingKeys.heightCm]!).round()} cm, ${_values[SettingKeys.age]}, ${_values[SettingKeys.gender]?.toLowerCase()}. Tap to refresh',
                onTap: app.signedIn
                    ? () async {
                        await app.sync.syncProfile();
                        await _reload();
                        app.foodChanged();
                      }
                    : null,
              ),
              for (final (key, title, value, fallback) in [
                (SettingKeys.carbsRest, 'Carbs, rest day', dOf(SettingKeys.carbsRest, f.carbsRest), f.carbsRest),
                (SettingKeys.carbsEasy, 'Carbs, easy day', dOf(SettingKeys.carbsEasy, f.carbsEasy), f.carbsEasy),
                (SettingKeys.carbsHard, 'Carbs, hard or long day', dOf(SettingKeys.carbsHard, f.carbsHard), f.carbsHard),
                (SettingKeys.proteinGkg, 'Protein, every day', dOf(SettingKeys.proteinGkg, f.protein), f.protein),
              ])
                _Row(
                  title: title,
                  subtitle: 'Grams per kg of body weight. Default ${gkg(fallback)}',
                  value: gkg(value),
                  onTap: () => _editDecimal(
                      key: key, title: title, help: 'Grams per kg of body weight a day. Sports nutrition ranges: carbs 3 to 10, protein 1.2 to 2.0.', current: value, min: 0.5, max: 12),
                ),
              _Row(
                title: 'Weight goal deficit',
                subtitle: 'The most a weight goal takes off a rest or easy day. Never on hard days or around a race',
                value: '${dOf(SettingKeys.deficitCap, f.deficitCap).round()} kcal',
                onTap: () => _editDecimal(
                    key: SettingKeys.deficitCap, title: 'Weight goal deficit', help: 'Most calories a day the weight goal can take off.', current: dOf(SettingKeys.deficitCap, f.deficitCap), min: 0, max: 1000),
              ),
            ]),
            const SizedBox(height: 12),
            TcCard(
              child: Text(
                'How food targets work\n\n'
                'Calories: resting energy (Mifflin-St Jeor, from your Coros profile and logged weight) plus Coros active calories, minus any weight goal deficit. '
                'Protein is the same every day; carbs follow the day type from your plan, or from Coros if you trained without one. Fat is the rest, never under 20% of calories.\n\n'
                'With a weight goal, rest and easy days take up to the deficit above, and carbs shrink to fit it, never below 3 g/kg. '
                'Hard and long days are never cut, and nothing is cut from 2 weeks before a race to 1 week after.\n\n'
                'These are estimates and general guidance, not medical or dietetic advice.',
                style: Tc.label.copyWith(fontSize: 14, height: 1.45),
              ),
            ),
            _section('RUN MAP'),
            _Group(children: [
              _Row(
                title: 'Home privacy zone',
                subtitle: _values[SettingKeys.homeZoneLat] == null
                    ? 'Around your most common start point. Long-press the map to move it. 0 turns it off'
                    : 'Around the point you set on the map. Long-press the map to move it. 0 turns it off',
                value: (double.tryParse(_values[SettingKeys.homeZoneRadiusM] ?? '') ?? 300) == 0
                    ? 'Off'
                    : '${(double.tryParse(_values[SettingKeys.homeZoneRadiusM] ?? '') ?? 300).round()} m',
                onTap: () async {
                  final app = AppScope.of(context);
                  await _editNumber(
                    key: SettingKeys.homeZoneRadiusM,
                    title: 'Home zone radius, in metres',
                    help: 'Route parts within this distance of home are hidden on the map, and pins inside it aren\'t shown at their real spot. Stored data doesn\'t change.',
                    current: (double.tryParse(_values[SettingKeys.homeZoneRadiusM] ?? '') ?? 300).round(),
                    min: 0,
                    max: 2000,
                  );
                  app.placesChanged();
                },
              ),
              _Row(
                title: 'Dark map key',
                subtitle: (app.mapTilesKey ?? '').isEmpty
                    ? 'Free CARTO key for the dark map style (carto.com/basemaps/apikey). Without it the map uses darkened OpenStreetMap tiles'
                    : 'CARTO dark map in use. Tap to change the key',
                value: (app.mapTilesKey ?? '').isEmpty ? 'Add' : 'Set',
                onTap: () async {
                  final controller = TextEditingController(text: app.mapTilesKey ?? '');
                  final key = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: Tc.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      title: Text('Dark map key', style: Tc.title(20)),
                      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Paste the key CARTO emailed you. Leave it empty to use darkened OpenStreetMap tiles.', style: Tc.label.copyWith(fontSize: 14)),
                        const SizedBox(height: 14),
                        TextField(controller: controller, autofocus: true, style: Tc.body),
                      ]),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Tc.textSecondary))),
                        TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save', style: TextStyle(color: Tc.go))),
                      ],
                    ),
                  );
                  if (key != null) await app.setMapTilesKey(key);
                },
              ),
            ]),
            _section('BACKUP'),
            if (!DriveBackup.configured)
              const EmptyCard(icon: Icons.cloud_outlined, title: 'Google Drive backup', subtitle: 'Waiting for the Google Cloud setup.')
            else
              _Group(children: [
                _Row(
                  title: 'Google Drive backup',
                  subtitle: _values[DriveBackup.enabledKey] == 'true'
                      ? 'Daily after the morning check, to a hidden app folder only this app can see. Your Coros sign-in is never backed up.'
                      : 'Back up your history and settings to your own Google Drive',
                  trailing: Switch(
                    value: _values[DriveBackup.enabledKey] == 'true',
                    onChanged: app.busy != null
                        ? null
                        : (on) async {
                            if (on) {
                              await app.connectBackup();
                            } else {
                              await app.disconnectBackup();
                            }
                            await _reload();
                          },
                  ),
                ),
                if (_values[DriveBackup.enabledKey] == 'true') ...[
                  _Row(
                    title: 'Back up now',
                    subtitle: _values[DriveBackup.lastBackupKey] == null
                        ? 'No backup yet'
                        : 'Last backup ${_values[DriveBackup.lastBackupKey]!.substring(0, 16).replaceFirst('T', ' ')}',
                    trailing: app.busy == 'Backing up' ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Tc.go)) : null,
                    onTap: app.busy != null
                        ? null
                        : () async {
                            final ok = await app.backupNow();
                            await _reload();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Backed up to Google Drive' : (app.lastError ?? 'Backup needs you to reconnect Google'))));
                            }
                          },
                  ),
                  _Row(title: 'Restore from Drive', subtitle: 'Replace this phone\'s data with the backup', onTap: app.busy != null ? null : () => _confirmRestore(app)),
                ],
              ]),
            if (app.lastError != null && app.busy == null) ...[
              const SizedBox(height: 8),
              Text(app.lastError!, style: Tc.label.copyWith(color: Tc.coral, fontSize: 13)),
            ],
            _section('DIAGNOSTICS'),
            _Group(children: [
              _Row(title: 'Error log', subtitle: 'Sync and format errors, kept on this phone', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ErrorLogScreen()))),
              _Row(
                title: 'Run background check now',
                subtitle: 'Runs the morning job once in the background, as Android would',
                onTap: () async {
                  await runBackgroundJobOnce();
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Background check queued')));
                },
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDisconnect(AppController app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Tc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text('Disconnect Coros?', style: Tc.title(20)),
        content: Text(
          'This deletes the Coros sign-in from this phone, so the app can no longer read your data. '
          'Coros doesn\'t let the app revoke its own access, so to remove it completely, also remove Training Companion from the authorised apps in the Coros app.',
          style: Tc.label.copyWith(fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Tc.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Disconnect', style: TextStyle(color: Tc.coral))),
        ],
      ),
    );
    if (ok == true) await app.disconnect();
  }

  Future<void> _confirmRestore(AppController app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Tc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text('Restore from Drive?', style: Tc.title(20)),
        content: Text(
          'This replaces everything on this phone with your last Drive backup, then closes the app. Open it again to continue. '
          'If this is a new phone, you\'ll be asked to sign in to Coros again.',
          style: Tc.label.copyWith(fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Tc.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore', style: TextStyle(color: Tc.coral))),
        ],
      ),
    );
    if (ok == true) await app.restoreFromDrive();
  }

  Widget _section(String title) => Padding(padding: const EdgeInsets.fromLTRB(4, 28, 4, 10), child: Text(title, style: Tc.caps));
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => TcCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (final (i, c) in children.indexed) ...[if (i > 0) const Divider(height: 1, color: Tc.hairline, indent: 18, endIndent: 18), c],
        ]),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.title, this.subtitle, this.value, this.trailing, this.onTap});
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Tc.body.copyWith(fontWeight: FontWeight.w500)),
                if (subtitle != null) ...[const SizedBox(height: 3), Text(subtitle!, style: Tc.label.copyWith(fontSize: 13))],
              ]),
            ),
            if (value != null) ...[const SizedBox(width: 12), Text(value!, style: Tc.body.copyWith(color: Tc.go))],
            ?trailing,
          ]),
        ),
      );
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: Tc.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Tc.hairline)),
          child: const Icon(Icons.arrow_back_rounded, color: Tc.text, size: 20),
        ),
      );
}

class ErrorLogScreen extends StatefulWidget {
  const ErrorLogScreen({super.key});

  @override
  State<ErrorLogScreen> createState() => _ErrorLogScreenState();
}

class _ErrorLogScreenState extends State<ErrorLogScreen> {
  List<Map<String, Object?>>? _rows;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppScope.of(context).db.errors().then((r) => setState(() => _rows = r));
  }

  String _asText() => (_rows ?? []).map((r) => '${r['at']}  [${r['source']}]  ${r['message']}').join('\n');

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            Row(children: [
              _BackButton(onTap: () => Navigator.pop(context)),
              const SizedBox(width: 14),
              Expanded(child: Text('Error log', style: Tc.title(26))),
              if (rows != null && rows.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _asText()));
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error log copied')));
                  },
                  child: const Text('Copy all', style: TextStyle(color: Tc.go)),
                ),
            ]),
            const SizedBox(height: 20),
            if (rows == null)
              const Center(child: CircularProgressIndicator(color: Tc.go))
            else if (rows.isEmpty)
              const EmptyCard(icon: Icons.check_rounded, title: 'No errors', subtitle: 'Sync and format problems will show up here.')
            else
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TcCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${(r['at'] as String).substring(0, 16).replaceFirst('T', ' ')} · ${r['source']}', style: Tc.caps.copyWith(fontSize: 11)),
                      const SizedBox(height: 6),
                      Text(r['message'] as String, style: Tc.body.copyWith(fontSize: 13)),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Shows the 12-week import with progress; used in onboarding and from Settings.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, this.onDone});
  final VoidCallback? onDone;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String _step = 'Starting';
  double _progress = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final app = AppScope.of(context);
    await app.importHistory((step, p) => setState(() {
          _step = step;
          _progress = p;
        }));
    await app.refreshToday();
    setState(() => _done = app.lastError == null);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Spacer(),
            Text('IMPORTING FROM COROS', style: Tc.caps),
            const SizedBox(height: 8),
            Text(_done ? '12 weeks imported' : 'Bringing in your last 12 weeks', style: Tc.title(30)),
            const SizedBox(height: 10),
            Text(app.lastError ?? 'HRV, resting HR, sleep, load and activities, a few days at a time. $_step.', style: Tc.label.copyWith(color: app.lastError == null ? Tc.textSecondary : Tc.coral)),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: _progress, minHeight: 8, color: Tc.go, backgroundColor: Tc.surfaceRaised),
            ),
            const Spacer(),
            if (_done || app.lastError != null)
              SizedBox(
                width: double.infinity,
                child: PillButton(
                  label: app.lastError != null ? 'Try again' : 'Continue',
                  onPressed: app.lastError != null ? _start : (widget.onDone ?? () => Navigator.pop(context)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
