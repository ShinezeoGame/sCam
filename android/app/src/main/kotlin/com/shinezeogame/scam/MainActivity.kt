package com.shinezeogame.scam

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Environment
import android.os.Build
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Fonctions propres à Android, appelées depuis `lib/data/system_bridge.dart` (canal
 * `scam/systeme`) : nom du téléphone, multidiffusion, autorisations, service au premier
 * plan, batterie, mesures de la caméra, notifications d'alerte, économie de batterie.
 */
class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private val analyzer = CameraAnalyzer()
    private var pendingPermissions: MethodChannel.Result? = null
    private var pendingCamera = false
    private var alertId = 100

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ScamService.createChannels(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "scam/systeme").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "nomAppareil" -> result.success(deviceName())
                    "verrouMultidiffusion" -> {
                        setMulticastLock(call.arguments as? Boolean ?: false)
                        result.success(null)
                    }
                    "autorisations" -> requestPermissions(call.argument<Boolean>("camera") ?: false, result)
                    "serviceDemarrer" -> {
                        startScamService(
                            call.argument<String>("mode") ?: "screen",
                            call.argument<String>("titre") ?: "sCam",
                            call.argument<String>("texte") ?: "",
                        )
                        result.success(null)
                    }
                    "serviceArreter" -> {
                        stopService(Intent(this, ScamService::class.java))
                        result.success(null)
                    }
                    "batterie" -> result.success(battery())
                    "analyseDemarrer" -> {
                        analyzer.start(call.argument<String>("video"), call.argument<String>("audio"))
                        result.success(null)
                    }
                    "analyseArreter" -> {
                        analyzer.stop()
                        result.success(null)
                    }
                    "analyseMesure" -> result.success(analyzer.read())
                    "analyseJpeg" -> result.success(analyzer.jpeg())
                    "alerte" -> {
                        notifyAlert(call.argument<String>("titre") ?: "sCam", call.argument<String>("texte") ?: "")
                        result.success(null)
                    }
                    "sansRestrictionBatterie" -> result.success(batteryUnrestricted())
                    "demanderSansRestrictionBatterie" -> {
                        requestBatteryUnrestricted()
                        result.success(null)
                    }
                    "rangerVideo" -> {
                        val path = call.argument<String>("chemin") ?: ""
                        val name = call.argument<String>("nom") ?: "extrait.mp4"
                        // La copie peut prendre un moment : hors du fil de l'interface.
                        Thread {
                            val saved = try {
                                saveVideo(File(path), name)
                            } catch (e: Exception) {
                                null
                            }
                            runOnUiThread { result.success(saved) }
                        }.start()
                    }
                    "ouvrirVideo" -> {
                        openVideo(call.arguments as String)
                        result.success(null)
                    }
                    "ecranAllume" -> {
                        if (call.arguments as? Boolean == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("erreur", e.message, null)
            }
        }
    }

    override fun onDestroy() {
        analyzer.stop()
        setMulticastLock(false)
        super.onDestroy()
    }

    /** Nom donné au téléphone par son propriétaire, à défaut son modèle. */
    private fun deviceName(): String {
        val chosen = try {
            Settings.Global.getString(contentResolver, "device_name")
        } catch (e: Exception) {
            null
        }
        return if (chosen.isNullOrBlank()) Build.MODEL else chosen
    }

    private fun setMulticastLock(enabled: Boolean) {
        try {
            if (enabled) {
                if (multicastLock == null) {
                    val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    multicastLock = wifi.createMulticastLock("scam").apply {
                        setReferenceCounted(false)
                        acquire()
                    }
                }
            } else {
                multicastLock?.release()
                multicastLock = null
            }
        } catch (e: Exception) {
            // Sans verrou, la diffusion classique reste disponible.
        }
    }

    // ── Autorisations ──

    private fun granted(permission: String) = checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun requestPermissions(camera: Boolean, result: MethodChannel.Result) {
        val wanted = mutableListOf<String>()
        if (camera) {
            wanted += Manifest.permission.CAMERA
            wanted += Manifest.permission.RECORD_AUDIO
        }
        if (Build.VERSION.SDK_INT >= 33) wanted += Manifest.permission.POST_NOTIFICATIONS
        val missing = wanted.filter { !granted(it) }
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        pendingPermissions?.success(false)
        pendingPermissions = result
        pendingCamera = camera
        requestPermissions(missing.toTypedArray(), PERMISSIONS_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSIONS_REQUEST) return
        val result = pendingPermissions ?: return
        pendingPermissions = null
        // Les notifications sont facultatives ; la caméra et le micro ne le sont pas.
        val ok = !pendingCamera || (granted(Manifest.permission.CAMERA) && granted(Manifest.permission.RECORD_AUDIO))
        result.success(ok)
    }

    // ── Service, batterie, alertes ──

    private fun startScamService(mode: String, title: String, text: String) {
        val intent = Intent(this, ScamService::class.java).apply {
            putExtra(ScamService.EXTRA_MODE, mode)
            putExtra(ScamService.EXTRA_TITLE, title)
            putExtra(ScamService.EXTRA_TEXT, text)
        }
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
    }

    private fun battery(): Map<String, Any?> {
        val status = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = status?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = status?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val plugged = status?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
        val tenths = status?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE) ?: Int.MIN_VALUE
        var hot = false
        if (Build.VERSION.SDK_INT >= 29) {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            hot = power.currentThermalStatus >= PowerManager.THERMAL_STATUS_SEVERE
        }
        return mapOf(
            "niveau" to if (level >= 0 && scale > 0) level * 100 / scale else null,
            "enCharge" to (plugged != 0),
            "temperature" to if (tenths != Int.MIN_VALUE) tenths / 10.0 else null,
            "chaud" to hot,
        )
    }

    @SuppressLint("MissingPermission")
    private fun notifyAlert(title: String, text: String) {
        if (Build.VERSION.SDK_INT >= 33 && !granted(Manifest.permission.POST_NOTIFICATIONS)) return
        val notification = ScamService.builder(this, ScamService.CHANNEL_ALERTS)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setCategory(android.app.Notification.CATEGORY_ALARM)
            .setContentIntent(ScamService.openAppIntent(this))
            .apply {
                @Suppress("DEPRECATION")
                if (Build.VERSION.SDK_INT < 26) {
                    setPriority(android.app.Notification.PRIORITY_HIGH)
                    setDefaults(android.app.Notification.DEFAULT_ALL)
                }
            }
            .build()
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // Une notification par alerte, pour garder l'historique dans le volet.
        alertId = if (alertId > 150) 100 else alertId + 1
        manager.notify(alertId, notification)
    }

    private fun batteryUnrestricted(): Boolean {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(packageName)
    }

    @SuppressLint("BatteryLife")
    private fun requestBatteryUnrestricted() {
        try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
            )
        } catch (e: Exception) {
            // Certains téléphones n'ont pas cette demande : on ouvre la liste générale.
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }

    // ── Extraits téléchargés ──

    /** Range une vidéo dans la galerie (Films/sCam) ; renvoie son adresse content://. */
    private fun saveVideo(source: File, name: String): String? {
        if (Build.VERSION.SDK_INT >= 29) {
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, name)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/sCam")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values) ?: return null
            contentResolver.openOutputStream(uri)?.use { out -> source.inputStream().use { it.copyTo(out) } }
            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            return uri.toString()
        }
        // Android 7 à 9 : dossier Films de sCam, puis indexation pour obtenir une adresse
        // que le lecteur vidéo peut ouvrir.
        val folder = File(getExternalFilesDir(Environment.DIRECTORY_MOVIES), "sCam").apply { mkdirs() }
        val target = File(folder, name)
        source.copyTo(target, overwrite = true)
        val latch = java.util.concurrent.CountDownLatch(1)
        var scanned: Uri? = null
        MediaScannerConnection.scanFile(this, arrayOf(target.path), arrayOf("video/mp4")) { _, uri ->
            scanned = uri
            latch.countDown()
        }
        latch.await(10, java.util.concurrent.TimeUnit.SECONDS)
        return scanned?.toString()
    }

    private fun openVideo(uri: String) {
        try {
            startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(Uri.parse(uri), "video/mp4")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            )
        } catch (e: Exception) {
            // Aucun lecteur vidéo : l'extrait reste dans la galerie.
        }
    }

    companion object {
        private const val PERMISSIONS_REQUEST = 4780
    }
}
