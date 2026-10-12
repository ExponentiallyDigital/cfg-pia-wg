package com.exponentiallydigital.pia_wireguard_cfga.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import com.exponentiallydigital.pia_wireguard_cfga.MainActivity
import com.exponentiallydigital.pia_wireguard_cfga.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * The 4x2 widget (ID-376): each tunnel's state, where it exits, and the guard. All the real work -
 * deciding the badge, the per-row text, who the guard is holding offline - happens in Dart
 * (lib/widget_status.dart, lib/widget_bridge.dart), which is testable without a device; this class
 * only lays out whatever it is told, through [WidgetKeys].
 */
class TunnelsWidgetProvider : HomeWidgetProvider() {

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
        RemoteViews(context.packageName, R.layout.widget_tunnels_4x2).apply {
            setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            )

            // Exactly one badge row, chosen by what Dart decided WidgetStatus.badge is.
            val badge = data.getString(WidgetKeys.BADGE, null) ?: "unchecked"
            setViewVisibility(R.id.badge_protected, visibleIf(badge == "protected"))
            setViewVisibility(R.id.badge_down, visibleIf(badge == "down"))
            setViewVisibility(R.id.badge_unchecked, visibleIf(badge == "unchecked"))
            if (badge == "down") {
                val n = data.getInt(WidgetKeys.DOWN_COUNT, 1)
                setTextViewText(R.id.tv_badge_down_text, if (n == 1) "1 tunnel down" else "$n tunnels down")
            }

            val tunnelCount = data.getInt(WidgetKeys.TUNNEL_COUNT, 0)
            populateRow(
                this, tunnelCount >= 1, R.id.row1_container, R.id.dot_row1,
                R.id.tv_row1_region, R.id.tv_row1_detail, R.id.tv_row1_guard,
                data.getString(WidgetKeys.T1_REGION, "") ?: "",
                data.getString(WidgetKeys.T1_DETAIL, "") ?: "",
                data.getString(WidgetKeys.T1_GUARD, "") ?: "",
                data.getString(WidgetKeys.T1_STATE, "unchecked") ?: "unchecked"
            )
            populateRow(
                this, tunnelCount >= 2, R.id.row2_container, R.id.dot_row2,
                R.id.tv_row2_region, R.id.tv_row2_detail, R.id.tv_row2_guard,
                data.getString(WidgetKeys.T2_REGION, "") ?: "",
                data.getString(WidgetKeys.T2_DETAIL, "") ?: "",
                data.getString(WidgetKeys.T2_GUARD, "") ?: "",
                data.getString(WidgetKeys.T2_STATE, "unchecked") ?: "unchecked"
            )

            val overflow = data.getString(WidgetKeys.OVERFLOW_TEXT, "") ?: ""
            setViewVisibility(R.id.tv_overflow, visibleIf(overflow.isNotEmpty()))
            if (overflow.isNotEmpty()) setTextViewText(R.id.tv_overflow, overflow)

            setTextViewText(
                R.id.tv_last_checked,
                data.getString(WidgetKeys.LAST_CHECKED_TEXT, "") ?: ""
            )

            // With a key installed, the refresh button reads the router (WidgetRefreshReceiver).
            // Without one there is nothing it could read with, so it opens the app instead of
            // doing nothing - the plain icon already says it cannot refresh by itself.
            val canRefresh = data.getBoolean(WidgetKeys.CAN_REFRESH, false)
            setInt(
                R.id.btn_refresh, "setBackgroundResource",
                if (canRefresh) R.drawable.widget_badge_refresh_bg else R.drawable.widget_badge_refresh_bg_none
            )
            setImageViewResource(
                R.id.btn_refresh,
                if (canRefresh) R.drawable.ic_widget_refresh_active else R.drawable.ic_widget_refresh_plain
            )
            setOnClickPendingIntent(
                R.id.btn_refresh,
                if (canRefresh) WidgetRefreshReceiver.pendingIntent(context)
                else HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            )
        }

    companion object {
        /** `RemoteViews.setViewVisibility` takes the `View` constant, not a bare boolean. */
        fun visibleIf(shown: Boolean) = if (shown) android.view.View.VISIBLE else android.view.View.GONE

        /** One tunnel row, shared between row 1 and row 2 so the two cannot drift apart. */
        fun populateRow(
            views: RemoteViews,
            show: Boolean,
            containerId: Int,
            dotId: Int,
            regionId: Int,
            detailId: Int,
            guardId: Int,
            region: String,
            detail: String,
            guard: String,
            state: String
        ) {
            views.setViewVisibility(containerId, visibleIf(show))
            if (!show) return
            views.setTextViewText(regionId, region)
            views.setTextViewText(detailId, detail)
            views.setViewVisibility(guardId, visibleIf(guard.isNotEmpty()))
            if (guard.isNotEmpty()) views.setTextViewText(guardId, guard)
            views.setImageViewResource(
                dotId,
                when (state) {
                    "answering" -> R.drawable.widget_dot_answering
                    "down" -> R.drawable.widget_dot_down
                    else -> R.drawable.widget_dot_unchecked
                }
            )
        }
    }
}
