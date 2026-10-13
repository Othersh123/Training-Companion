import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../coros/parsers.dart';
import '../data/goal.dart';
import '../rules/load_guard.dart';
import '../rules/planned_workout.dart';
import 'goal_form.dart';
import '../rules/goal_status.dart';
import '../sync/home_data.dart';
import 'home_cards.dart';
import 'theme.dart';
import 'week_screen.dart' show weekLabel;

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _date(DateTime d) => '${_dayNames[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// PRD F2 as scoped on 5 Oct 2026: goals, the plan the owner follows, and the load guard over it.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  GuardResult? _guard;
  (String, CorosDate?, CorosDate?)? _plan;
  List<GoalStatus> _statuses = [];
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  String? _loadError;

  Future<void> _load() async {
    final app = AppScope.of(context);
    try {
      await app.screenLoad('Plan', () => _loadData(app));
      _loadError = null;
    } catch (e) {
      if (mounted) setState(() => _loadError = 'Couldn\'t load your plan ($e). Pull down to try again.');
    }
  }

  Future<void> _loadData(AppController app) async {
    final guard = await app.sync.guardFromDatabase(DateTime.now());
    final planId = guard.weeks.expand((w) => w.workouts).isEmpty
        ? null
        : (await app.db.scheduleBetween(corosDate(guard.weeks.first.monday), corosDate(guard.weeks.last.monday.add(const Duration(days: 6)))))
            .values
            .expand((d) => d)
            .map((w) => w.planId)
            .nonNulls
            .firstOrNull;
    final plan = planId == null ? null : await app.db.planInfo(planId);
    // The full reasons behind Home's goal tiles (owner, 7 Oct 2026: details live on Plan).
    final statuses = (await app.sync.homeData(DateTime.now())).goals;
    if (mounted) {
      setState(() {
        _guard = guard;
        _plan = plan;
        _statuses = statuses;
      });
    }
  }

  Future<void> _refresh() async {
    try {
      await AppScope.of(context).sync.syncBlock(DateTime.now());
      _error = null;
    } catch (_) {
      _error = 'Couldn\'t reach Coros; showing what\'s stored.';
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final guard = _guard;
    final primary = app.primaryGoal;
    final others = app.goals.where((g) => !g.primary).toList();
    final warnings = guard?.warnings.length ?? 0;
    final trailRace = primary?.type == GoalType.race && primary?.terrain == Terrain.trail;
    final hasTrailRuns = guard?.weeks.expand((w) => w.workouts).any((w) => w.sport == WorkoutSport.trailRun) ?? false;

    return RefreshIndicator(
      color: Tc.go,
      backgroundColor: Tc.surface,
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
        children: [
          Row(children: [
            Expanded(child: Text('Plan', style: Tc.title(34))),
            TextButton.icon(
              onPressed: () => _openGoal(null),
              icon: const Icon(Icons.add_rounded, color: Tc.go, size: 18),
              label: const Text('Goal', style: TextStyle(color: Tc.go, fontFamily: Tc.font)),
            ),
          ]),
          const SizedBox(height: 16),
          if (primary == null)
            GestureDetector(
              onTap: () => _openGoal(null),
              child: const EmptyCard(icon: Icons.flag_outlined, title: 'Set your goal', subtitle: 'A race, a weight, consistency or aerobic fitness.'),
            )
          else
            _GoalCard(goal: primary, onTap: () => _openGoal(primary)),
          for (final g in others) ...[
            const SizedBox(height: 8),
            TcCard(
              padding: EdgeInsets.zero,
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  onTap: () => _openGoal(g),
                  title: Text(g.name, style: Tc.body),
                  subtitle: Text(g.summary, style: Tc.label.copyWith(fontSize: 13)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Tc.textSecondary),
                ),
              ),
            ),
          ],
          if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: Tc.label.copyWith(color: Tc.coral, fontSize: 13))],
          if (_statuses.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('WHERE YOU STAND', style: Tc.caps),
            const SizedBox(height: 8),
            for (final st in _statuses) Padding(padding: const EdgeInsets.only(bottom: 8), child: GoalCard(status: st)),
          ],
          const SizedBox(height: 16),
          if (guard == null && _loadError != null)
            EmptyCard(icon: Icons.error_outline, title: 'Plan didn\'t load', subtitle: _loadError!)
          else if (guard == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: Tc.go)))
          else ...[
            _BlockCard(plan: _plan, warnings: warnings, noTrailRuns: trailRace && !hasTrailRuns && _plan != null),
            const SizedBox(height: 16),
            Text('WEEK BY WEEK', style: Tc.caps),
            const SizedBox(height: 8),
            for (final (i, w) in guard.weeks.indexed) ...[
              _WeekTile(week: w, initiallyExpanded: i == 0, raceDate: primary?.type == GoalType.race ? primary?.date : null),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            Text('Planned km are estimates: time-based parts of a workout are counted at your recent easy pace. '
                'Past days show what you actually ran.', style: Tc.label.copyWith(fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Future<void> _openGoal(Goal? g) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GoalForm(goal: g)));
    await _load();
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.onTap});
  final Goal goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final days = goal.daysTo(DateTime.now());
    return GestureDetector(
      onTap: onTap,
      child: TcCard(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x3897EB78), Tc.surface],
          stops: [0, 0.6],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PRIMARY GOAL', style: Tc.caps),
              const SizedBox(height: 8),
              Text(goal.name, style: Tc.title(24)),
              const SizedBox(height: 4),
              Text(goal.summary, style: Tc.label.copyWith(fontSize: 14)),
              if (goal.date != null) ...[
                const SizedBox(height: 4),
                Text(_date(goal.date!), style: Tc.label.copyWith(fontSize: 14)),
              ],
            ]),
          ),
          if (days != null && days >= 0)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$days', style: Tc.title(40)),
              Text(days == 1 ? 'day to go' : 'days to go', style: Tc.label.copyWith(fontSize: 13)),
            ]),
        ]),
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.plan, required this.warnings, required this.noTrailRuns});
  final (String, CorosDate?, CorosDate?)? plan;
  final int warnings;
  final bool noTrailRuns;

  @override
  Widget build(BuildContext context) {
    final p = plan;
    return TcCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('FOLLOWING', style: Tc.caps),
        const SizedBox(height: 8),
        Text(p == null ? 'No Coros plan on your calendar' : p.$1, style: Tc.title(20)),
        if (p?.$3 != null) ...[
          const SizedBox(height: 4),
          Text('From your Coros app · ends ${_date(DateTime.parse(p!.$3!))}', style: Tc.label.copyWith(fontSize: 13)),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Icon(warnings == 0 ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded, color: warnings == 0 ? Tc.go : Tc.amber, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              warnings == 0 ? 'The load guard found nothing to change.' : 'The load guard found $warnings thing${warnings == 1 ? '' : 's'} to check, below.',
              style: Tc.body.copyWith(fontSize: 14),
            ),
          ),
        ]),
        if (noTrailRuns) ...[
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.terrain_rounded, color: Tc.textSecondary, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('This plan has no trail runs before your trail race.', style: Tc.body.copyWith(fontSize: 14))),
          ]),
        ],
        if (p != null) ...[
          const SizedBox(height: 10),
          Text('The app can\'t change a plan made in the Coros app; make any change there, then pull down here to refresh.',
              style: Tc.label.copyWith(fontSize: 12)),
        ],
      ]),
    );
  }
}

class _WeekTile extends StatelessWidget {
  const _WeekTile({required this.week, required this.initiallyExpanded, this.raceDate});
  final GuardWeek week;
  final bool initiallyExpanded;
  final DateTime? raceDate;

  @override
  Widget build(BuildContext context) {
    final runs = week.workouts.where((w) => w.isRun).length;
    final strength = week.workouts.where((w) => w.sport == WorkoutSport.strength).length;
    final isRaceWeek = raceDate != null && !raceDate!.isBefore(week.monday) && raceDate!.isBefore(week.monday.add(const Duration(days: 7)));
    final byDay = <String, List<PlannedWorkout>>{};
    for (final w in week.workouts) {
      byDay.putIfAbsent(w.date, () => []).add(w);
    }
    final days = byDay.keys.toList()..sort();

    // A Material, not a coloured Container, so the expansion tile's ripple shows.
    return Material(
      color: Tc.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: Tc.hairline)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
          title: Row(children: [
            Expanded(child: Text(isRaceWeek ? '${weekLabel(week.monday)} · race week' : weekLabel(week.monday), style: Tc.body.copyWith(fontWeight: FontWeight.w500))),
            if (week.warnings.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Tc.amber.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(999)),
                child: Text('${week.warnings.length} to check', style: Tc.label.copyWith(fontSize: 12, color: Tc.amber)),
              ),
          ]),
          subtitle: Text(
            '${week.km.toStringAsFixed(0)} km · long ${week.longKm.toStringAsFixed(0)} km · $runs run${runs == 1 ? '' : 's'}${strength == 0 ? '' : ' · $strength strength'}',
            style: Tc.label.copyWith(fontSize: 13),
          ),
          iconColor: Tc.textSecondary,
          collapsedIconColor: Tc.textSecondary,
          children: [
            for (final warning in week.warnings)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Tc.amber.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
                child: Text(warning.text, style: Tc.body.copyWith(fontSize: 13.5)),
              ),
            if (days.isEmpty) Align(alignment: Alignment.centerLeft, child: Text('Nothing planned', style: Tc.label.copyWith(fontSize: 13))),
            for (final d in days)
              for (final w in byDay[d]!)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    SizedBox(width: 56, child: Text(_date(DateTime.parse(d)).substring(0, 6).trim(), style: Tc.label.copyWith(fontSize: 13))),
                    Icon(
                      switch (w.sport) {
                        WorkoutSport.strength => Icons.fitness_center_rounded,
                        WorkoutSport.cycle => Icons.directions_bike_rounded,
                        WorkoutSport.rest => Icons.hotel_rounded,
                        _ => Icons.directions_run_rounded,
                      },
                      size: 16,
                      color: w.hard ? Tc.amber : Tc.go,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(w.name, style: Tc.body.copyWith(fontSize: 14))),
                    Text(
                      [w.kindLabel, if (w.estimatedMeters != null) '${w.km.toStringAsFixed(0)} km'].join(' · '),
                      style: Tc.label.copyWith(fontSize: 12),
                    ),
                  ]),
                ),
          ],
        ),
      ),
    );
  }
}
