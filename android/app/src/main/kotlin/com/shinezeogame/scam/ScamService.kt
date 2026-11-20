package com.shinezeogame.scam

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Service au premier plan, avec sa notification permanente.
 *
 * - Mode « camera » : la caméra et le micro restent ouverts écran éteint (types camera et
 *   microphone ; Android 14 exige que ce service démarre pendant que sCam est à l'écran,
 *   ce qui est le cas : il démarre quand l'utilisateur lance la caméra).
 * - Mode « screen » : l'écran reste relié aux caméras (alertes) et le son continue en
 *   arrière-plan (types connectedDevice et mediaPlayback).
 *
 * Dans les deux cas, un verrou de veille et un verrou Wi-Fi empêchent le téléphone de
 * couper le processeur ou le Wi-Fi pour économiser la batterie.
 */
class ScamService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val mode = intent?.getStringExtra(EXTRA_MODE) ?: "screen"
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "sCam"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: ""
        try {
            val notification = buildNotification(this, title, text)
            if (Build.VERSION.SDK_INT >= 29) {
                val type = if (mode == "camera") {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                } else {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                }
                startForeground(NOTIFICATION_ID, notification, type)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // Autorisation manquante ou démarrage refusé par le système : sCam continue tant
            // qu'il est à l'écran.
            stopSelf()
            return START_NOT_STICKY
        }
        acquireLocks()
        return START_NOT_STICKY
    }

    private fun acquireLocks() {
        if (wakeLock == null) {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "sCam:veille").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
        if (wifiLock == null) {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            val mode = if (Build.VERSION.SDK_INT >= 29) {
                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
            } else {
                WifiManager.WIFI_MODE_FULL_HIGH_PERF
            }
            wifiLock = wifi.createWifiLock(mode, "sCam:wifi").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wifiLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        wifiLock = null
        super.onDestroy()
    }

    companion object {
        const val EXTRA_MODE = "mode"
        const val EXTRA_TITLE = "titre"
        const val EXTRA_TEXT = "texte"
        private const val NOTIFICATION_ID = 1
        const val CHANNEL_WATCH = "veille"
        const val CHANNEL_ALERTS = "alertes"

        /** Crée les deux canaux de notification (Android 8 et plus). */
        fun createChannels(context: Context) {
            if (Build.VERSION.SDK_INT < 26) return
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_WATCH, "Veille", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Notification permanente pendant que sCam filme ou veille."
                    setShowBadge(false)
                }
            )
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ALERTS, "Alertes", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Bruit ou mouvement repéré par une caméra."
                    enableVibration(true)
                }
            )
        }

        fun openAppIntent(context: Context): PendingIntent {
            val open = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(
                context, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        @Suppress("DEPRECATION")
        fun builder(context: Context, channel: String): Notification.Builder =
            if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channel) else Notification.Builder(context)

        fun buildNotification(context: Context, title: String, text: String): Notification {
            createChannels(context)
            return builder(context, CHANNEL_WATCH)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title)
                .setContentText(text)
                .setOngoing(true)
                .setContentIntent(openAppIntent(context))
                .build()
        }
    }
}
