import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:training_companion/app_controller.dart';
import 'package:training_companion/coros/parsers.dart';
import 'package:training_companion/data/app_database.dart';
import 'package:training_companion/data/food_store.dart';
import 'package:training_companion/food/fndds.dart';
import 'package:training_companion/food/food.dart';
import 'package:training_companion/data/goal.dart';
import 'package:training_companion/main.dart';
import 'package:training_companion/sync/coros_sync.dart';
import 'package:training_companion/sync/morning_runner.dart';
import 'package:training_companion/ui/home_cards.dart';
import 'package:training_companion/ui/manual_entry_sheet.dart';
import 'package:training_companion/ui/places_screen.dart';

String fixture(String name) => File('test/fixtures/coros/$name').readAsStringSync();

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    // No map tiles or Coros calls in tests (M5).
    DarkTiles.enabled = false;
    PlacesScreen.syncOnOpen = false;
    AppController.screenLoadLimit = null;
    // Tests draw text in a placeholder font where every letter is a full square, which makes
    // widths meaningless. Load the app's real font so the overflow checks measure real text.
    final interTight = FontLoader('InterTight');
    for (final weight in ['Regular', 'Medium', 'SemiBold']) {
      interTight.addFont(rootBundle.load('assets/fonts/InterTight-$weight.ttf'));
    }
    await interTight.load();

    // The home screen widget plugin isn't available in tests: answer its calls with nothing.
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('home_widget'), (_) async => null);
    messenger.setMockStreamHandler(const EventChannel('home_widget/updates'), MockStreamHandler.inline(onListen: (_, _) {}));
  });

  Future<AppController> controllerWith(WidgetTester tester,
      {required bool onboarded, bool withPlan = false, ScheduledWorkout? todaysWorkout, bool withFood = false}) async {
    FlutterSecureStorage.setMockInitialValues({
      'coros_tokens': '{"client_id":"c","access_token":"a","refresh_token":"r","expires_at":"2099-01-01T00:00:00.000"}',
    });
    return (await tester.runAsync(() async {
      // ownConnection: a fresh in-memory database per test (a shared one leaked data between tests).
      final db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath, ownConnection: true);
      if (onboarded) {
        await db.setSetting(SettingKeys.onboarded, 'true');
        await db.setSetting(SettingKeys.nickname, 'Adarsh');
        await db.setSetting(SettingKeys.easyRunHrCap, '150');
        // Store the owner's real 1 Oct morning under today's date, as the sync would.
        final today = corosDateOf(DateTime.now());
        String asToday(String text) => text.replaceAll('2026-10-02', '1999-01-01').replaceAll('2026-10-01', today).replaceAll('2026-09-30', corosDateOf(DateTime.now().subtract(const Duration(days: 1))));
        await db.saveHrv(parseSleepHrv(asToday(fixture('sleep_hrv_7d.txt'))));
        await db.saveRestingHr({today: 51, for (var d = 1; d <= 20; d++) corosDateOf(DateTime.now().subtract(Duration(days: d))): 55});
        await db.saveSleep(parseSleepOverview(asToday(fixture('sleep_overview_7d.txt'))));
        await db.saveLoad(parseTrainingLoad(asToday(fixture('training_load_7d.txt'))));
        await db.saveActivities(parseSportRecords(asToday(fixture('sport_records_18d.txt'))));
        await db.saveSchedule(today, today, {today: [ScheduledWorkout(name: 'S5715', distanceMeters: 9170, estimatedSeconds: 4724, trainingLoad: 112)]});
        final sync = CorosSync(db, _NoCoros());
        if (withPlan) {
          // The owner's real plan (5 Oct to 1 Nov), shifted to start today, and Malnad 53 days out.
          final details = parsePlanDetails(fixture('training_plan_details_4w.txt'));
          final shift = DateTime.now().difference(DateTime(2026, 10, 5)).inDays;
          String moved(String d) => corosDateOf(DateTime.parse(d).add(Duration(days: shift)));
          final byDate = {
            for (final e in details.days.entries)
              moved(e.key): [for (final c in e.value) ScheduledWorkout(name: c.name, sport: c.sport, courseJson: c.courseJson, planId: details.planId)],
          };
          await db.saveSchedule(moved('2026-10-05'), moved('2026-11-01'), byDate);
          await db.applyPlanDetails(details);
          await db.saveGoal(Goal(type: GoalType.race, name: 'Malnad 50K', date: DateTime.now().add(const Duration(days: 53)), distanceMeters: 50000, terrain: Terrain.trail));
        }
        if (todaysWorkout != null) await db.saveSchedule(today, today, {today: [todaysWorkout]});
        if (withFood) {
          // The owner's Coros profile, two logged weights, a weight goal and a logged lunch.
          for (final kv in {SettingKeys.heightCm: '175.0', SettingKeys.corosWeightKg: '78.6', SettingKeys.age: '31', SettingKeys.gender: 'Male'}.entries) {
            await db.setSetting(kv.key, kv.value);
          }
          await db.saveWeight(today, 78.2);
          await db.saveWeight(corosDateOf(DateTime.now().subtract(const Duration(days: 3))), 78.6);
          await db.saveGoal(Goal(type: GoalType.weight, name: 'Body weight', date: DateTime.now().add(const Duration(days: 80)), targetWeightKg: 72));
          await db.logFood(today, Meal.lunch,
              Food(source: FoodSource.manual, name: 'Rice and toor dal with a very long name that has to wrap neatly', per100g: const Nutrients(kcal: 150, protein: 6, carbs: 25, fat: 3)), 350);
          await db.addEntry(MealEntry(date: today, meal: Meal.runFuel, name: 'Energy gel', grams: 1, servingGrams: 1, nutrients: const Nutrients(kcal: 100, protein: 0, carbs: 25, fat: 0)));
        }
        await db.saveCheck(await sync.computeFromDatabase(DateTime.now()), isFinal: true);
      }
      final controller = AppController(db);
      await controller.load();
      return controller;
    }))!;
  }

  testWidgets('first run starts with connecting Coros', (tester) async {
    final controller = await controllerWith(tester, onboarded: false);
    await tester.pumpWidget(TrainingCompanionApp(controller: controller));
    await tester.pump();

    expect(find.text('Connect your Coros account'), findsOneWidget);
    expect(find.text('STEP 1 OF 6'), findsOneWidget);
    expect(find.text('Connect Coros'), findsOneWidget);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('Home: goals first, this week, then today\'s call with signals behind a tap, at ${(scale * 100).round()}% text (7 Oct 2026)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = await controllerWith(tester, onboarded: true, withPlan: true, withFood: true);
      await tester.pumpWidget(TrainingCompanionApp(controller: controller));
      for (var i = 0; i < 60 && find.text('Malnad 50K').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }

      expect(find.text('Home'), findsOneWidget); // the tab
      expect(find.textContaining('Adarsh'), findsOneWidget);
      expect(find.text('GOALS'), findsOneWidget);
      // Visual: the countdown, the block bar and the long-run dots; one short line, details on Plan.
      expect(find.text('MALNAD 50K'), findsOneWidget);
      expect(find.text('53 days to go', findRichText: true), findsOneWidget);
      expect(find.text('30 km+: 0 of 2'), findsOneWidget);
      expect(find.text('Long runs short of 50K guidance'), findsOneWidget);
      expect(find.textContaining('long runs of 30 km or 4 h+'), findsNothing); // the full reason lives on Plan
      expect(tester.takeException(), isNull);

      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('THIS WEEK SO FAR'), 300, scrollable: list);
      await tester.scrollUntilVisible(find.text('Go easy'), 300, scrollable: list);
      expect(find.text('HRV 91 ms, below your 93 to 111 ms range'), findsOneWidget); // the reason, on the verdict line
      expect(find.text('91 ms'), findsNothing); // signal tiles folded away
      await tester.tap(find.text('Go easy'));
      await tester.pump();
      expect(find.text('91 ms'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('12 over your 150 bpm cap'), 300, scrollable: list); // yesterday's run was over the cap
      expect(find.text('Check now'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Tapping the race tile opens Plan, where the full reasons are.
      tester.state<ScrollableState>(list).position.jumpTo(0); // back to the top, without a pull-to-refresh
      await tester.pump();
      await tester.tap(find.byType(GoalTile).first);
      await tester.pump();
      for (var i = 0; i < 60 && find.text('WHERE YOU STAND').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      await tester.scrollUntilVisible(find.textContaining('long runs of 30 km or 4 h+'), 300, scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
    });
  }

  // The owner saw "bottom overflowed by 1 pixels" on 3 Oct 2026. Flutter fails a test on any
  // overflow, so render both screens on a narrow phone with large text.
  testWidgets('a hard session on a Go easy morning gets swap advice (M3)', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final threshold = parsePlanDetails(fixture('training_plan_details_4w.txt')).days['2026-10-29']!.single;
    final controller = await controllerWith(tester,
        onboarded: true, todaysWorkout: ScheduledWorkout(name: threshold.name, sport: threshold.sport, courseJson: threshold.courseJson));
    await tester.pumpWidget(TrainingCompanionApp(controller: controller));
    await tester.pump();

    expect(find.text('Go easy'), findsOneWidget);
    expect(find.textContaining('Today\'s Threshold Workout is a hard session.'), findsOneWidget);
    expect(find.textContaining('Change it in the Coros app'), findsOneWidget);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('Plan fits a 360dp-wide phone at ${(scale * 100).round()}% text, with goal, plan and warnings', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = await controllerWith(tester, onboarded: true, withPlan: true);
      await tester.pumpWidget(TrainingCompanionApp(controller: controller));
      await tester.pump();

      await tester.tap(find.text('Plan'));
      for (var i = 0; i < 50 && find.text('WEEK BY WEEK').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      expect(find.text('Malnad 50K'), findsNWidgets(2)); // the goal card, and Where you stand
      expect(find.text('53'), findsOneWidget);
      expect(find.text('Marathon Plan 430'), findsOneWidget);
      expect(find.text('This plan has no trail runs before your trail race.'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('Planned km are estimates'), 300, scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in [1.0, 1.3]) {
    testWidgets('Log fits a 360dp-wide phone at ${(scale * 100).round()}% text, with targets, meals and weight (M4)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = await controllerWith(tester, onboarded: true, withFood: true);
      await tester.pumpWidget(TrainingCompanionApp(controller: controller));
      await tester.pump();

      await tester.tap(find.text('Log'));
      for (var i = 0; i < 50 && find.text('Protein').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      expect(find.text("Today's meals"), findsOneWidget);
      expect(find.text('Estimate'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Energy gel'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Run fuel'), findsOneWidget);
      expect(find.text('1 serving'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Edit weight'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('78.4'), findsWidgets); // 7-day average of 78.2 and 78.6
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('removing an item shows Undo, and the message goes away by itself (5 Oct 2026)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final controller = await controllerWith(tester, onboarded: true, withFood: true);
    await tester.pumpWidget(TrainingCompanionApp(controller: controller));
    await tester.pump();
    await tester.tap(find.text('Log'));
    for (var i = 0; i < 50 && find.text('Protein').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.scrollUntilVisible(find.text('Energy gel'), 300, scrollable: find.byType(Scrollable).first);
    // Lift the row clear of the floating bottom bar before tapping its button.
    await tester.runAsync(() => Scrollable.ensureVisible(tester.element(find.text('Energy gel')), alignment: 0.4));
    await tester.pumpAndSettle();
    final card = find.ancestor(of: find.text('Energy gel'), matching: find.byType(InkWell)).first;
    await tester.tap(find.descendant(of: card, matching: find.byIcon(Icons.remove_rounded)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.text('Removed Energy gel'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); // slides in; its 4-second timer starts then
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Removed Energy gel'), findsNothing);
  });

  testWidgets('USDA foods in the main search: "guava" logs 1 fruit, and a portion can be changed (5 Oct 2026)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final controller = await controllerWith(tester, onboarded: true, withFood: true);
    await tester.pumpWidget(TrainingCompanionApp(controller: controller));
    await tester.pump();
    Future<void> settle(Finder until) async {
      for (var i = 0; i < 60 && until.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
    }

    await tester.tap(find.text('Log'));
    await settle(find.text('Add'));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'guava');
    await tester.pump();
    await settle(find.text('Guava, raw'));
    expect(find.text('COOKED & COMMON · USDA ESTIMATES'), findsOneWidget);
    expect(find.text('37 kcal · 1 fruit (55 g)'), findsOneWidget);
    await tester.tap(find.text('Guava, raw'));
    await tester.pumpAndSettle();
    expect(find.text('1 fruit · 55 g'), findsOneWidget);
    await tester.tap(find.text('1 cup · 165 g'));
    await tester.pump();
    expect(find.text('112'), findsOneWidget); // 165 g at 68 kcal per 100 g
    await tester.tap(find.text('1 fruit · 55 g'));
    await tester.pump();
    await tester.tap(find.text('Snacks'));
    await tester.pump();
    await tester.tap(find.text('Add to snacks'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    final entries = (await tester.runAsync(() => controller.db.entriesOn(corosDateOf(DateTime.now()))))!;
    final guava = entries.firstWhere((e) => e.name == 'Guava, raw');
    expect(guava.grams, 55);
    expect(guava.servings, 1);
    expect(guava.nutrients.kcal, closeTo(37.4, 0.1));
    await tester.pump(const Duration(seconds: 15)); // the packaged search's timeout
  });

  testWidgets('search "toor", pick Red gram dal and add it to lunch (M4)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final controller = await controllerWith(tester, onboarded: true, withFood: true);
    await tester.pumpWidget(TrainingCompanionApp(controller: controller));
    await tester.pump();
    await tester.tap(find.text('Log'));
    await tester.pump();

    Future<void> settle(Finder until) async {
      for (var i = 0; i < 50 && until.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
    }

    await settle(find.text('Add'));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await settle(find.text('IFCT'));
    await tester.enterText(find.byType(TextField).first, 'toor');
    await tester.pump();
    await settle(find.text('Red gram, dal'));
    await tester.tap(find.text('Red gram, dal'));
    await tester.pumpAndSettle();
    expect(find.text('331'), findsOneWidget); // kcal in 100 g
    await tester.tap(find.text('Lunch'));
    await tester.pump();
    await tester.tap(find.text('Add to lunch'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    await settle(find.text('Red gram, dal'));
    expect(find.text('Red gram, dal'), findsOneWidget); // back on the Log screen
    final today = corosDateOf(DateTime.now());
    final entries = (await tester.runAsync(() => controller.db.entriesOn(today)))!;
    expect(entries.map((e) => e.name), contains('Red gram, dal'));
  });

  testWidgets('manual entry: "rice + chapati" estimates each part and adds them up, at 130% text', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final controller = await controllerWith(tester, onboarded: true, withFood: true);
    await tester.pumpWidget(TrainingCompanionApp(controller: controller));
    await tester.pump();
    Future<void> settle(Finder until) async {
      for (var i = 0; i < 60 && until.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
    }

    await tester.tap(find.text('Log'));
    await settle(find.text('Add'));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'rice + chapati');
    await tester.pump();
    await settle(find.text('Enter "rice + chapati" manually'));
    await tester.scrollUntilVisible(find.text('Enter "rice + chapati" manually'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Enter "rice + chapati" manually'));
    await tester.pumpAndSettle();
    Finder inSheet(String t) => find.descendant(of: find.byType(ManualEntrySheet), matching: find.text(t));
    await settle(inSheet('Bread, chappatti or roti'));

    final fndds = (await tester.runAsync(Fndds.load))!;
    final rice = fndds.search('rice').first, roti = fndds.search('chapati').first;
    await tester.tap(inSheet(rice.name));
    await tester.pump();
    await tester.ensureVisible(inSheet(roti.name));
    await tester.tap(inSheet(roti.name));
    await tester.pump();
    final expected = rice.per100g.scale(rice.defaultPortion.$2 / 100) + roti.per100g.scale(roti.defaultPortion.$2 / 100);
    expect(find.widgetWithText(TextField, expected.kcal.round().toString()), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Log it'));
    await tester.tap(find.text('Log it'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    final entries = (await tester.runAsync(() => controller.db.entriesOn(corosDateOf(DateTime.now()))))!;
    final logged = entries.firstWhere((e) => e.name == 'rice + chapati');
    expect(logged.nutrients.kcal, expected.kcal.round());
    // Typing started a packaged-food search; let its timeout run out.
    await tester.pump(const Duration(seconds: 15));
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('Today and Week fit a 360dp-wide phone at ${(scale * 100).round()}% text', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = await controllerWith(tester, onboarded: true);
      await tester.pumpWidget(TrainingCompanionApp(controller: controller));
      await tester.pump();

      await tester.tap(find.text('Week'));
      // The review loads from the database off the test clock: wait until it's on screen.
      for (var i = 0; i < 50 && find.text('Running').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }

      await tester.scrollUntilVisible(find.text('PLAN AGAINST DONE'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('PLAN AGAINST DONE'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Goal progress'), 300, scrollable: find.byType(Scrollable).first);
      await tester.scrollUntilVisible(find.text('BODY AND FOOD'), 300, scrollable: find.byType(Scrollable).first);
      await tester.scrollUntilVisible(find.text('PLACES'), 300, scrollable: find.byType(Scrollable).first);
      for (var i = 0; i < 30 && find.textContaining(' in ').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      expect(find.textContaining('runs in'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // The full map: India framed, runs only, routes still to load.
      await tester.tap(find.text('PLACES'));
      await tester.pump(const Duration(milliseconds: 500)); // page transition; a spinner never "settles"
      for (var i = 0; i < 30 && find.textContaining('Routes loading').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      expect(find.text('India'), findsOneWidget);
      expect(find.textContaining('Routes loading: 0 of'), findsOneWidget);
      expect(find.textContaining('Home zone 300 m (suggested'), findsOneWidget);
      await tester.tap(find.text('World'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}

class _NoCoros implements ToolCaller {
  @override
  Future<String> callTool(String name, Map<String, dynamic> args) => throw UnimplementedError();
}
