import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../coros/parsers.dart';
import '../rules/morning_check.dart';
import '../sync/home_data.dart';
import 'home_cards.dart';
import '../rules/planned_workout.dart';
import 'settings_screen.dart';
import 'theme.dart';

/// Home (owner, 7 Oct 2026): where you stand against your goals first, then this week, then
/// anything worth knowing, then today's call and session. Replaces the verdict-only Today.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<HomeData>? _future;
  String? _loadedFor;
  bool _signalsOpen = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final stored = app.today;
    final check = stored?.check;
    // Reload when the check, the log, the plan or the goals change.
    final key = '${stored?.computedAt}|${app.foodRevision}|${app.placesRevision}|${app.goals.map((g) => '${g.id}${g.primary}').join()}';
    if (_future == null || _loadedFor != key) {
      _loadedFor = key;
      _future = app.screenLoad('Home', () => app.sync.homeData(DateTime.now()));
    }

    return RefreshIndicator(
      color: Tc.go,
      backgroundColor: Tc.surface,
      onRefresh: app.checkNow,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
        children: [
          _Header(nickname: app.nickname),
          const SizedBox(height: 20),
          if (check != null && check.hasErrors) ...[
            _ErrorBanner(check: check),
            const SizedBox(height: 12),
          ],
          FutureBuilder<HomeData>(
            future: _future,
            builder: (context, snap) {
              final h = snap.data;
              if (snap.hasError) return EmptyCard(icon: Icons.error_outline, title: 'Couldn\'t load your goals', subtitle: '${snap.error}');
              if (h == null) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: Tc.go)));
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('GOALS', style: Tc.caps),
                const SizedBox(height: 10),
                if (h.goals.isEmpty)
                  const EmptyCard(icon: Icons.flag_outlined, title: 'No goals yet', subtitle: 'Set one on the Plan tab: a race, a weight, consistency or aerobic fitness.')
                else
                  for (final (i, g) in h.goals.indexed) Padding(padding: const EdgeInsets.only(bottom: 10), child: GoalTile(status: g, primary: i == 0, onOpen: () => app.openTab(1))),
                const SizedBox(height: 14),
                Text('THIS WEEK SO FAR', style: Tc.caps),
                const SizedBox(height: 10),
                WeekStripCard(w: h.week),
                if (h.insights.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('WORTH KNOWING', style: Tc.caps),
                  const SizedBox(height: 10),
                  InsightChips(insights: h.insights),
                ],
              ]);
            },
          ),
          const SizedBox(height: 24),
          Text('TODAY', style: Tc.caps),
          const SizedBox(height: 10),
          if (check == null)
            const EmptyCard(
              icon: Icons.bedtime_outlined,
              title: 'No check yet today',
              subtitle: 'It runs at your wake time once Coros has last night\'s sleep. Or tap Check now.',
            )
          else ...[
            VerdictLine(check: check, isFinal: stored!.isFinal, open: _signalsOpen, onTap: () => setState(() => _signalsOpen = !_signalsOpen)),
            if (_signalsOpen) ...[
              const SizedBox(height: 10),
              _SignalTiles(signals: check.signals),
            ],
          ],
          const SizedBox(height: 12),
          _CheckNowRow(app: app),
          if (app.retestReason != null) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
              child: TcCard(
                child: Row(children: [
                  const Icon(Icons.monitor_heart_outlined, color: Tc.sky),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${app.retestReason} Do a threshold test in the Coros app, then update your Zone 2 cap in Settings.',
                      style: Tc.body.copyWith(fontSize: 14),
                    ),
                  ),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _WorkoutCard(workouts: app.todaysWorkouts, verdict: check?.verdict),
          // Yesterday's easy run only when it needs attention (owner: Home shows what's useful).
          if (check != null && (check.easyRun.state == EasyRunState.overCap || check.easyRun.state == EasyRunState.capNotSet)) ...[
            const SizedBox(height: 24),
            Text('YESTERDAY\'S EASY RUN', style: Tc.caps),
            const SizedBox(height: 10),
            _EasyRunCard(run: check.easyRun),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.nickname});
  final String? nickname;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const days = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];
    const months = ['JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'];
    final greeting = now.hour < 12 ? 'Morning' : (now.hour < 17 ? 'Afternoon' : 'Evening');
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}', style: Tc.caps),
          const SizedBox(height: 6),
          Text(nickname == null ? greeting : '$greeting, $nickname', style: Tc.title(32)),
        ]),
      ),
      GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: Tc.surfaceRaised, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tc.hairline)),
          alignment: Alignment.center,
          child: Text((nickname ?? '?').substring(0, 1).toUpperCase(), style: Tc.title(18)),
        ),
      ),
    ]);
  }
}

/// Value against normal range for each signal (ref_4 macro tiles).
class _SignalTiles extends StatelessWidget {
  const _SignalTiles({required this.signals});
  final List<SignalResult> signals;

  @override
  Widget build(BuildContext context) {
    Widget tile(SignalResult s) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Tc.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: Tc.hairline)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: Tc.forState(s.state), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Flexible(child: Text(signalLabel(s.signal), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tc.label.copyWith(fontSize: 13))),
              ]),
              const SizedBox(height: 10),
              Text(s.value ?? (s.state == SignalState.error ? 'Couldn\'t read' : 'No data'),
                  style: Tc.title(20).copyWith(color: s.hasData ? Tc.text : Tc.textSecondary)),
              const SizedBox(height: 4),
              Text(s.state == SignalState.flagged || !s.hasData ? (s.note ?? '') : (s.normal ?? ''),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: Tc.label.copyWith(fontSize: 12)),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(height: 5, color: Tc.forState(s.state).withValues(alpha: s.hasData ? 1 : 0.5)),
              ),
            ]),
          ),
        );

    return Column(children: [
      Row(children: [tile(signals[0]), const SizedBox(width: 10), tile(signals[1])]),
      const SizedBox(height: 10),
      Row(children: [tile(signals[2]), const SizedBox(width: 10), tile(signals[3])]),
    ]);
  }
}

class _CheckNowRow extends StatelessWidget {
  const _CheckNowRow({required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final stored = app.today;
    final synced = stored == null
        ? 'Not checked yet today'
        : 'Checked ${TimeOfDay.fromDateTime(stored.computedAt).format(context)}${stored.isFinal ? '' : ' · will check again'}';
    return Row(children: [
      PillButton(label: 'Check now', icon: Icons.refresh_rounded, busy: app.busy == 'Checking Coros', onPressed: app.signedIn ? app.checkNow : null),
      const SizedBox(width: 14),
      Expanded(child: Text(app.lastError ?? synced, style: Tc.label.copyWith(fontSize: 13, color: app.lastError == null ? Tc.textSecondary : Tc.coral))),
    ]);
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.check});
  final MorningCheck check;

  @override
  Widget build(BuildContext context) {
    final broken = check.signals.where((s) => s.state == SignalState.error).map((s) => signalLabel(s.signal)).join(', ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Tc.coral.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(22), border: Border.all(color: Tc.coral.withValues(alpha: 0.4))),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded, color: Tc.coral),
        const SizedBox(width: 12),
        Expanded(
          child: Text('Coros changed how it reports $broken, so the app couldn\'t read it. The verdict uses the other signals. Details are in Settings, Error log.',
              style: Tc.body.copyWith(fontSize: 14)),
        ),
      ]),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.workouts, required this.verdict});
  final List<ScheduledWorkout> workouts;
  final Verdict? verdict;

  @override
  Widget build(BuildContext context) {
    if (workouts.isEmpty) {
      return const EmptyCard(icon: Icons.event_available_outlined, title: 'Nothing scheduled', subtitle: 'No workout on your Coros calendar today.');
    }
    final strengthOnly = workouts.every((w) => w.sport == WorkoutSport.strength);
    final today = corosDate(DateTime.now());
    // Swap advice (PRD F1): a hard or long session on a Go easy or Rest morning. The owner's plan
    // was made in the Coros app, which the app can't change, so this is advice (F2 decisions).
    final heavy = workouts.map((w) => classifyWorkout(today, w)).where((p) => p.hard || p.long).firstOrNull;
    const inCoros = ' Change it in the Coros app; the app can\'t edit your plan.';
    final swap = heavy == null
        ? null
        : switch (verdict) {
            Verdict.goEasy when heavy.hard =>
              'Today\'s ${heavy.name} is a hard session. Run it as an easy ${heavy.km.toStringAsFixed(0)} km in Zone 2 instead, and keep the hard work for a day the check is clear.$inCoros',
            Verdict.goEasy =>
              '${heavy.name} is a long run. Cut it to about ${(heavy.km * 0.6).toStringAsFixed(0)} km, all in Zone 2.$inCoros',
            Verdict.rest => 'Skip ${heavy.name} today: rest, or 20 to 30 minutes very easy.$inCoros',
            _ => null,
          };
    final advice = swap ?? switch ((verdict, strengthOnly)) {
      (Verdict.goAsPlanned, _) => 'Go as planned.',
      (Verdict.goEasy, true) => 'Keep the session, but go lighter: fewer sets or less weight.',
      (Verdict.goEasy, false) => 'Keep the session, but cap your heart rate at Zone 2 and cut the intensity.',
      (Verdict.rest, true) => 'Rest today, or swap it for 20 minutes of mobility.',
      (Verdict.rest, false) => 'Rest today, or 20 to 30 minutes very easy.',
      _ => 'No verdict yet; go by how you feel.',
    };
    return TcCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final w in workouts) ...[
          Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: Tc.surfaceRaised, borderRadius: BorderRadius.circular(12)),
              child: Icon(
                switch (w.sport) {
                  WorkoutSport.run || WorkoutSport.trailRun => Icons.directions_run_rounded,
                  WorkoutSport.strength => Icons.fitness_center_rounded,
                  WorkoutSport.cycle => Icons.directions_bike_rounded,
                  WorkoutSport.rest => Icons.hotel_rounded,
                  WorkoutSport.unknown => Icons.event_note_rounded,
                },
                color: Tc.go,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(w.name, style: Tc.title(18)),
                const SizedBox(height: 3),
                Text(
                  [
                    if (w.estimatedSeconds != null) formatMinutes((w.estimatedSeconds! / 60).round()),
                    if (w.distanceMeters != null) '${(w.distanceMeters! / 1000).toStringAsFixed(1)} km',
                    if (w.trainingLoad != null) '${w.trainingLoad} TL',
                  ].join(' · '),
                  style: Tc.label.copyWith(fontSize: 13),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
        ],
        Text(advice, style: Tc.body.copyWith(color: Tc.forVerdict(verdict))),
      ]),
    );
  }
}

class _EasyRunCard extends StatelessWidget {
  const _EasyRunCard({required this.run});
  final EasyRunCheck run;

  @override
  Widget build(BuildContext context) {
    final (color, text) = switch (run.state) {
      EasyRunState.underCap => (Tc.go, 'Averaged ${run.avgHr} bpm, at or under your ${run.cap} bpm cap.'),
      EasyRunState.overCap => (Tc.coral, 'Averaged ${run.avgHr} bpm, ${run.avgHr! - run.cap!} over your ${run.cap} bpm cap. Easy runs build the base only when they stay easy.'),
      EasyRunState.capNotSet => (Tc.amber, 'Averaged ${run.avgHr} bpm. Set your easy-run HR cap in Settings to check it.'),
      EasyRunState.noEasyRun => (Tc.textSecondary, ''),
    };
    return TcCard(
      child: Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 14),
        Expanded(child: Text('${run.runName ?? 'Run'}: $text', style: Tc.body.copyWith(fontSize: 14))),
      ]),
    );
  }
}
