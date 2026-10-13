import 'package:home_widget/home_widget.dart';

import '../rules/morning_check.dart';

/// Feeds the native home screen widget (TcWidgetProvider) through home_widget's shared storage.
class HomeWidgetUpdater {
  static const _provider = 'com.trainingcompanion.training_companion.TcWidgetProvider';

  static Future<void> show(MorningCheck check, {String? workoutName}) async {
    await HomeWidget.saveWidgetData<String>('tc_verdict', verdictLabel(check.verdict));
    await HomeWidget.saveWidgetData<String>('tc_state', check.verdict.name);
    await HomeWidget.saveWidgetData<String>('tc_reason', check.reason);
    await HomeWidget.saveWidgetData<String>('tc_workout', workoutName == null ? 'No workout scheduled' : 'Today: $workoutName');
    await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
  }
}
