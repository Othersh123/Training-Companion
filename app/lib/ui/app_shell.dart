import 'package:flutter/material.dart';

import '../app_controller.dart';

import 'food_search_screen.dart';
import 'log_screen.dart';
import 'theme.dart';
import 'plan_screen.dart';
import 'home_screen.dart';
import 'week_screen.dart';

/// Four tabs and a raised centre button for logging a meal or weight (PRD: Screens and key flows).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  static const _tabs = [
    (Icons.home_outlined, 'Home'),
    (Icons.calendar_month_outlined, 'Plan'),
    (Icons.bar_chart_rounded, 'Week'),
    (Icons.restaurant_outlined, 'Log'),
  ];

  @override
  Widget build(BuildContext context) {
    // Another screen asked for a tab (Home's goal tiles open Plan).
    final app = AppScope.of(context);
    if (app.tabRequest != null) {
      _tab = app.tabRequest!;
      app.tabRequest = null;
    }
    final body = switch (_tab) {
      0 => const HomeScreen(),
      1 => const PlanScreen(),
      2 => const WeekScreen(),
      _ => const LogScreen(),
    };
    return Scaffold(
      extendBody: true,
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: Tc.surface.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: Tc.hairline),
            ),
            child: Row(children: [
              _item(0),
              _item(1),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: () => _showLogSheet(context),
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Tc.goButton,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Tc.go.withValues(alpha: 0.35), blurRadius: 18)],
                      ),
                      child: const Icon(Icons.add_rounded, color: Colors.black, size: 30),
                    ),
                  ),
                ),
              ),
              _item(2),
              _item(3),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _item(int i) {
    final selected = _tab == i;
    final color = selected ? Tc.go : Tc.textSecondary;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: () => setState(() => _tab = i),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(_tabs[i].$1, color: color, size: 22),
          const SizedBox(height: 4),
          Text(_tabs[i].$2, style: TextStyle(fontFamily: Tc.font, fontSize: 11, color: color, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
  }

  void _showLogSheet(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Tc.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (sheet) {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          Widget tile(IconData icon, String title, String subtitle, VoidCallback onTap) => Expanded(
                child: Material(
                  color: Tc.surfaceRaised,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: Tc.surface, borderRadius: BorderRadius.circular(12)),
                          child: Icon(icon, color: Tc.go, size: 20),
                        ),
                        const SizedBox(height: 22),
                        Text(title, style: Tc.title(16)),
                        const SizedBox(height: 2),
                        Text(subtitle, style: Tc.label.copyWith(fontSize: 12)),
                      ]),
                    ),
                  ),
                ),
              );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
              child: Row(children: [
                tile(Icons.restaurant_outlined, 'Log a meal', 'Search, recipes, saved', () {
                  Navigator.pop(sheet);
                  openFoodSearch(context, today, guessMeal(now));
                }),
                const SizedBox(width: 10),
                tile(Icons.monitor_weight_outlined, 'Log weight', 'Morning weight', () {
                  Navigator.pop(sheet);
                  showWeightSheet(context, today, null);
                }),
              ]),
            ),
          );
        },
      );
}
