package com.exponentiallydigital.pia_wireguard_cfga.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import com.exponentiallydigital.pia_wireguard_cfga.MainActivity
import com.exponentiallydigital.pia_wireguard_cfga.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** The 2x1 widget (ID-376): the badge and one line. See TunnelsWidgetProvider for the 4x2 size. */
class CompactWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { id ->
            appWidgetManager.updateAppWidget(id, buildViews(context, widgetData))
        }
    }

    private fun buildViews(context: Context, data: SharedPreferences): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_compact_2x1).apply {
            setOnClickPendingIntent(
                R.id.compact_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            )
            setImageViewResource(
                R.id.compact_icon,
                when (data.getString(WidgetKeys.BADGE, "unchecked")) {
                    "protected" -> R.drawable.ic_widget_shield
                    "down" -> R.drawable.ic_widget_warning
                    else -> R.drawable.ic_widget_clock
                }
            )
            setTextViewText(R.id.tv_compact_badge, data.getString(WidgetKeys.COMPACT_BADGE_TEXT, "") ?: "")
            setTextViewText(R.id.tv_compact_detail, data.getString(WidgetKeys.COMPACT_DETAIL_TEXT, "") ?: "")
        }
}
