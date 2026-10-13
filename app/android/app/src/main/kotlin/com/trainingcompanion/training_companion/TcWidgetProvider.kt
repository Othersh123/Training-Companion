package com.trainingcompanion.training_companion

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Home screen widget: verdict ring, verdict, main reason, today's workout, Check now. */
class TcWidgetProvider : HomeWidgetProvider() {
  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    for (id in appWidgetIds) {
      val ring = when (widgetData.getString("tc_state", null)) {
        "goAsPlanned" -> R.drawable.tc_ring_go
        "goEasy" -> R.drawable.tc_ring_easy
        "rest" -> R.drawable.tc_ring_rest
        else -> R.drawable.tc_ring_none
      }
      val views = RemoteViews(context.packageName, R.layout.tc_widget).apply {
        setImageViewResource(R.id.tc_ring, ring)
        setTextViewText(R.id.tc_verdict, widgetData.getString("tc_verdict", "Open to set up"))
        setTextViewText(R.id.tc_reason, widgetData.getString("tc_reason", "Connect Coros in Training Companion"))
        setTextViewText(R.id.tc_workout, widgetData.getString("tc_workout", ""))
        setOnClickPendingIntent(R.id.tc_root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
        setOnClickPendingIntent(
            R.id.tc_check_now,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("trainingcompanion://check-now")))
      }
      appWidgetManager.updateAppWidget(id, views)
    }
  }
}
