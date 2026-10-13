import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/goal.dart';
import 'theme.dart';

/// Set or edit a goal (PRD F2: race, weight, consistency, aerobic fitness).
class GoalForm extends StatefulWidget {
  const GoalForm({super.key, this.goal});
  final Goal? goal;

  @override
  State<GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<GoalForm> {
  late GoalType _type = widget.goal?.type ?? GoalType.race;
  late final _name = TextEditingController(text: widget.goal?.name ?? '');
  late DateTime? _date = widget.goal?.date;
  late final _distance = TextEditingController(text: widget.goal?.distanceMeters == null ? '' : _km(widget.goal!.distanceMeters!));
  late Terrain _terrain = widget.goal?.terrain ?? Terrain.road;
  late final _target = TextEditingController(text: widget.goal?.targetSeconds == null ? '' : formatDuration(widget.goal!.targetSeconds!));
  late final _weight = TextEditingController(text: widget.goal?.targetWeightKg?.toStringAsFixed(1) ?? '');
  late final _runs = TextEditingController(text: '${widget.goal?.runsPerWeek ?? 4}');
  late final _strength = TextEditingController(text: '${widget.goal?.strengthPerWeek ?? 2}');
  late bool _primary = widget.goal?.primary ?? true;
  String? _error;

  static String _km(int m) => (m / 1000).toStringAsFixed(m % 1000 == 0 ? 0 : 1);

  /// "4:30" or "4:30:00" -> seconds; empty -> null (run to finish).
  static int? _parseTarget(String raw) {
    final parts = raw.trim().split(':');
    if (raw.trim().isEmpty) return null;
    if (parts.length < 2 || parts.length > 3 || parts.any((p) => int.tryParse(p) == null)) return -1;
    final n = parts.map(int.parse).toList();
    return parts.length == 2 ? n[0] * 3600 + n[1] * 60 : n[0] * 3600 + n[1] * 60 + n[2];
  }

  Future<void> _save() async {
    final app = AppScope.of(context);
    String? error;
    final name = _name.text.trim();
    final distanceKm = double.tryParse(_distance.text.trim());
    final target = _parseTarget(_target.text);
    final weight = double.tryParse(_weight.text.trim());
    switch (_type) {
      case GoalType.race:
        if (name.isEmpty) error = 'Give the race a name.';
        if (_date == null) error ??= 'Pick the race date.';
        if (distanceKm == null || distanceKm <= 0) error ??= 'Enter the race distance in km.';
        if (target == -1) error ??= 'Write the target as hours:minutes, e.g. 4:30, or leave it empty to finish.';
      case GoalType.weight:
        if (weight == null) error = 'Enter your target weight in kg.';
        if (_date == null) error ??= 'Pick a date to reach it by.';
      case GoalType.consistency:
        if (int.tryParse(_runs.text) == null || int.tryParse(_strength.text) == null) error = 'Enter runs and strength sessions a week.';
      case GoalType.aerobic:
        break;
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    await app.saveGoal(Goal(
      id: widget.goal?.id,
      type: _type,
      name: name.isEmpty ? _defaultName(_type) : name,
      date: _type == GoalType.race || _type == GoalType.weight ? _date : null,
      distanceMeters: _type == GoalType.race ? (distanceKm! * 1000).round() : null,
      terrain: _terrain,
      targetSeconds: _type == GoalType.race ? target : null,
      targetWeightKg: _type == GoalType.weight ? weight : null,
      runsPerWeek: _type == GoalType.consistency ? int.parse(_runs.text) : null,
      strengthPerWeek: _type == GoalType.consistency ? int.parse(_strength.text) : null,
      primary: _primary,
    ));
    // A new race date changes which weeks the guard looks at; fetch them.
    if (_type == GoalType.race) app.sync.syncBlock(DateTime.now()).catchError((_) {});
    if (mounted) Navigator.pop(context);
  }

  static String _defaultName(GoalType t) => switch (t) {
        GoalType.race => 'Race',
        GoalType.weight => 'Body weight',
        GoalType.consistency => 'Consistency',
        GoalType.aerobic => 'Aerobic fitness',
      };

  @override
  Widget build(BuildContext context) {
    Widget field(String label, TextEditingController c, {String? hint, TextInputType? keyboard, String? suffix}) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextField(
            controller: c,
            keyboardType: keyboard,
            style: Tc.body,
            decoration: InputDecoration(labelText: label, hintText: hint, suffixText: suffix, labelStyle: Tc.label),
          ),
        );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: Tc.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Tc.hairline)),
                  child: const Icon(Icons.arrow_back_rounded, color: Tc.text, size: 20),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(widget.goal == null ? 'New goal' : 'Edit goal', style: Tc.title(26))),
              if (widget.goal != null)
                TextButton(
                  onPressed: () async {
                    await AppScope.of(context).deleteGoal(widget.goal!);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Delete', style: TextStyle(color: Tc.coral)),
                ),
            ]),
            const SizedBox(height: 20),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in GoalType.values)
                ChoiceChip(
                  label: Text(_defaultName(t) == 'Race' ? 'Race' : _defaultName(t)),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                  selectedColor: Tc.goButton,
                  backgroundColor: Tc.surfaceRaised,
                  labelStyle: TextStyle(fontFamily: Tc.font, color: _type == t ? Colors.black : Tc.text),
                  showCheckmark: false,
                  side: const BorderSide(color: Tc.hairline),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
            ]),
            const SizedBox(height: 20),
            if (_type == GoalType.race) ...[
              field('Race name', _name, hint: 'e.g. Malnad 50K'),
              field('Distance', _distance, keyboard: const TextInputType.numberWithOptions(decimal: true), suffix: 'km'),
              SegmentedButton<Terrain>(
                segments: const [ButtonSegment(value: Terrain.road, label: Text('Road')), ButtonSegment(value: Terrain.trail, label: Text('Trail'))],
                selected: {_terrain},
                onSelectionChanged: (s) => setState(() => _terrain = s.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 14),
              field('Target time (optional)', _target, hint: 'h:mm, or leave empty to finish'),
            ],
            if (_type == GoalType.weight) field('Target weight', _weight, keyboard: const TextInputType.numberWithOptions(decimal: true), suffix: 'kg'),
            if (_type == GoalType.consistency) ...[
              field('Runs a week', _runs, keyboard: TextInputType.number),
              field('Strength sessions a week', _strength, keyboard: TextInputType.number),
            ],
            if (_type == GoalType.aerobic)
              Text('Tracks your pace at your easy heart rate (the fitness trend on the Week screen). Faster means fitter.',
                  style: Tc.label.copyWith(fontSize: 14)),
            if (_type == GoalType.race || _type == GoalType.weight)
              TcCard(
                padding: EdgeInsets.zero,
                child: Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                  title: Text(_type == GoalType.race ? 'Race date' : 'Reach it by', style: Tc.body),
                  trailing: Text(
                      _date == null ? 'Pick a date' : '${_date!.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][_date!.month - 1]} ${_date!.year}',
                      style: Tc.body.copyWith(color: Tc.go)),
                  onTap: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 730)), initialDate: _date ?? now.add(const Duration(days: 60)));
                    if (d != null) setState(() => _date = d);
                  },
                  ),
                ),
              ),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Primary goal', style: Tc.body),
              subtitle: Text('The plan and weekly review work toward this one', style: Tc.label.copyWith(fontSize: 13)),
              value: _primary,
              onChanged: (v) => setState(() => _primary = v),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: Tc.label.copyWith(color: Tc.coral))),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: PillButton(label: 'Save goal', onPressed: _save)),
          ],
        ),
      ),
    );
  }
}
