import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../backup/drive_backup.dart';
import '../notify/notifier.dart';
import '../sync/coros_sync.dart';
import 'settings_screen.dart';
import 'theme.dart';

/// First run (PRD key flow 1): connect Coros, import 12 weeks, HR cap, wake time, Drive backup, notifications.
/// Goals arrive with M3.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Step { connect, import, cap, wake, backup, notifications }

class _OnboardingScreenState extends State<OnboardingScreen> {
  _Step _step = _Step.connect;
  final _cap = TextEditingController();
  TimeOfDay _wake = const TimeOfDay(hour: 6, minute: 30);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (_step == _Step.import) return ImportScreen(onDone: () => setState(() => _step = _Step.cap));

    final (caps, title, body, content, action, onAction) = switch (_step) {
      _Step.connect => (
          'STEP 1 OF 6',
          'Connect your Coros account',
          'Training Companion reads your sleep, HRV, resting HR, load and runs from Coros, and works out each morning whether to train as planned, go easy or rest. '
              'Everything stays on this phone.',
          app.lastError == null ? null : Text(app.lastError!, style: Tc.label.copyWith(color: Tc.coral)),
          'Connect Coros',
          () async {
            if (await app.signIn()) setState(() => _step = _Step.import);
          },
        ),
      _Step.cap => (
          'STEP 3 OF 6',
          'Your easy-run heart rate cap',
          'Enter the top of your Coros Zone 2, in bpm. Coros doesn\'t share zone values with apps, so copy it from the Coros app: Profile, Zones, Heart rate. '
              'Zones based on lactate threshold are more accurate than ones from max HR.',
          TextField(
            controller: _cap,
            keyboardType: TextInputType.number,
            style: Tc.title(28),
            decoration: const InputDecoration(hintText: 'e.g. 148', suffixText: 'bpm'),
          ),
          'Continue',
          () async {
            final v = int.tryParse(_cap.text.trim());
            if (v == null || v < 90 || v > 200) return;
            await app.setSetting(SettingKeys.easyRunHrCap, '$v');
            setState(() => _step = _Step.wake);
          },
        ),
      _Step.wake => (
          'STEP 4 OF 6',
          'When do you wake up?',
          'From this time, the app checks Coros every 15 minutes for up to 2 hours, until last night\'s sleep and HRV arrive.',
          GestureDetector(
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: _wake);
              if (t != null) setState(() => _wake = t);
            },
            child: TcCard(child: Text(_wake.format(context), style: Tc.title(40))),
          ),
          'Continue',
          () async {
            await app.setSetting(SettingKeys.wakeTime, '${_wake.hour.toString().padLeft(2, '0')}:${_wake.minute.toString().padLeft(2, '0')}');
            setState(() => _step = DriveBackup.configured ? _Step.backup : _Step.notifications);
          },
        ),
      _Step.backup => (
          'STEP 5 OF 6',
          'Back up to Google Drive',
          'Once a day, your history and settings are copied to a hidden folder in your own Google Drive that only this app can see. '
              'Your Coros sign-in is never backed up. You can turn this on later in Settings.',
          TextButton(
            onPressed: () => setState(() => _step = _Step.notifications),
            child: const Text('Skip for now', style: TextStyle(color: Tc.textSecondary, fontFamily: Tc.font, fontSize: 15)),
          ),
          'Connect Google Drive',
          () async {
            if (await app.connectBackup()) setState(() => _step = _Step.notifications);
          },
        ),
      _Step.notifications => (
          'STEP 6 OF 6',
          'Morning notification',
          'Get the verdict as soon as Coros has last night\'s data, or a note saying what\'s missing if it doesn\'t arrive.',
          null,
          'Allow notifications',
          () async {
            final allowed = await Notifier.requestPermission();
            await app.setSetting(SettingKeys.notificationsOn, '$allowed');
            await app.finishOnboarding();
            await app.checkNow();
          },
        ),
      _Step.import => throw StateError('handled above'),
    };

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Spacer(),
            Text(caps, style: Tc.caps),
            const SizedBox(height: 10),
            Text(title, style: Tc.title(32)),
            const SizedBox(height: 12),
            Text(body, style: Tc.label.copyWith(height: 1.45)),
            if (content != null) ...[const SizedBox(height: 24), content],
            const Spacer(flex: 2),
            SizedBox(width: double.infinity, child: PillButton(label: action, busy: app.busy != null, onPressed: onAction)),
          ]),
        ),
      ),
    );
  }
}
