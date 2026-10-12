package com.exponentiallydigital.pia_wireguard_cfga.widget

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import dev.fluttercommunity.workmanager.BackgroundWorker

/**
 * The widget's refresh button (ID-376). A tap queues one run of the same Dart entry point the
 * fifteen-minute refresh uses (lib/widget_refresh.dart, callbackDispatcher), through the
 * workmanager plugin's own worker.
 *
 * Why not home_widget's background channel, which is what the button first used: home_widget
 * queues every tap with `ExistingWorkPolicy.APPEND` under one fixed name, so each tap waits for
 * the one before it - and once any tap fails, every tap queued after it fails too, without ever
 * running. One bad tap left the button dead for good: on the emulator, 2026-10-12, sixteen taps
 * were recorded, one had run and failed, and fifteen had failed without being attempted.
 *
 * `KEEP` here instead: a tap while a refresh is already queued or running is dropped (it would
 * read the same router a second later), and a refresh that failed is finished, so it never blocks
 * the next tap.
 */
class WidgetRefreshReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val request = OneTimeWorkRequestBuilder<BackgroundWorker>()
            .setInputData(workDataOf(BackgroundWorker.DART_TASK_KEY to TAP_TASK))
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(TAP_TASK, ExistingWorkPolicy.KEEP, request)
    }

    companion object {
        /** The unique work name, and the task name the Dart side is handed. */
        const val TAP_TASK = "cfg-pia-wg-widget-tap"

        /** An explicit broadcast to this receiver, so nothing outside the app can send it one. */
        fun pendingIntent(context: Context): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                0,
                Intent(context, WidgetRefreshReceiver::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
    }
}
