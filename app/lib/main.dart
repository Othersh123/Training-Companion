import 'dart:async';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import 'app_controller.dart';
import 'coros/coros_auth.dart';
import 'data/app_database.dart';
import 'ui/app_shell.dart';
import 'ui/onboarding_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(await AppDatabase.open());
  await controller.load();
  runApp(TrainingCompanionApp(controller: controller));
}

class TrainingCompanionApp extends StatefulWidget {
  const TrainingCompanionApp({super.key, required this.controller});
  final AppController controller;

  @override
  State<TrainingCompanionApp> createState() => _TrainingCompanionAppState();
}

class _TrainingCompanionAppState extends State<TrainingCompanionApp> with WidgetsBindingObserver {
  StreamSubscription<Uri?>? _widgetClicks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CorosAuth.appState = 'in front';
    // The widget's Check now opens the app with this link; the app is then in front,
    // so it has network access (Android blocks it in the background, L20).
    // Ignore failures: the widget link is a convenience, never a reason to crash.
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_onWidgetClick, onError: (_) {});
    _widgetClicks = HomeWidget.widgetClicked.listen(_onWidgetClick, onError: (_) {});
  }

  void _onWidgetClick(Uri? uri) {
    if (uri?.host == 'check-now' && widget.controller.onboarded) widget.controller.checkNow();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    CorosAuth.appState = switch (state) {
      AppLifecycleState.resumed => 'in front',
      AppLifecycleState.inactive => 'inactive',
      AppLifecycleState.hidden || AppLifecycleState.paused => 'in the background',
      AppLifecycleState.detached => 'detached',
    };
    if (state == AppLifecycleState.resumed) widget.controller.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetClicks?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
        controller: widget.controller,
        child: MaterialApp(
          title: 'Training Companion',
          debugShowCheckedModeBanner: false,
          theme: Tc.theme(),
          home: Builder(builder: (context) => AppScope.of(context).onboarded ? const AppShell() : const OnboardingScreen()),
        ),
      );
}
