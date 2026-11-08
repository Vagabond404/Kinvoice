package com.kinvoice.kinvoice

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.StatFs
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.kinvoice.kinvoice/ambient_service"
    private var methodChannel: MethodChannel? = null
    private var pendingQuickRecord: Boolean = false
    private var pendingNotificationAction: String? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIncomingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent == null) return
        if (intent.getBooleanExtra("quick_record", false)) {
            intent.removeExtra("quick_record")
            pendingQuickRecord = true
            methodChannel?.invokeMethod("onQuickRecordLaunch", true)
        }
        val notifAction = intent.getStringExtra("notification_action")
        if (!notifAction.isNullOrEmpty()) {
            intent.removeExtra("notification_action")
            pendingNotificationAction = notifAction
            methodChannel?.invokeMethod("onNotificationAction", notifAction)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel

        AmbientAudioService.onActionCallback = { action ->
            runOnUiThread {
                channel.invokeMethod("onNotificationAction", action)
            }
        }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startAmbientService" -> {
                    val title = call.argument<String>("notificationTitle") ?: "Kinvoice Studio Recorder"
                    val text = call.argument<String>("notificationText") ?: "Recording audio..."
                    val elapsed = call.argument<String>("elapsed") ?: "00:00:00"
                    val isPaused = call.argument<Boolean>("isPaused") ?: false
                    AmbientAudioService.startService(this, title, elapsed, isPaused, text)
                    result.success(true)
                }
                "updateRecordingNotification" -> {
                    val title = call.argument<String>("notificationTitle") ?: "Kinvoice Studio Recorder"
                    val text = call.argument<String>("notificationText") ?: "Recording audio..."
                    val elapsed = call.argument<String>("elapsed") ?: "00:00:00"
                    val isPaused = call.argument<Boolean>("isPaused") ?: false
                    AmbientAudioService.updateNotification(this, title, elapsed, isPaused, text)
                    result.success(true)
                }
                "stopAmbientService" -> {
                    AmbientAudioService.stopService(this)
                    result.success(true)
                }
                "isServiceRunning" -> {
                    result.success(AmbientAudioService.isRunning)
                }
                "consumeQuickRecordIntent" -> {
                    val flag = pendingQuickRecord
                    pendingQuickRecord = false
                    result.success(flag)
                }
                "consumeNotificationAction" -> {
                    val act = pendingNotificationAction
                    pendingNotificationAction = null
                    result.success(act)
                }
                "requestAllPermissions" -> {
                    val permissionsToRequest = mutableListOf(Manifest.permission.RECORD_AUDIO)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        permissionsToRequest.add(Manifest.permission.POST_NOTIFICATIONS)
                    }
                    val missing = permissionsToRequest.filter {
                        ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
                    }
                    if (missing.isEmpty()) {
                        result.success(true)
                    } else {
                        pendingPermissionResult = result
                        ActivityCompat.requestPermissions(this, missing.toTypedArray(), 9010)
                    }
                }
                "openAppSettings" -> {
                    try {
                        val settingsIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.fromParts("package", packageName, null)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(settingsIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "getFreeDiskBytes" -> {
                    try {
                        val stat = StatFs(filesDir.absolutePath)
                        result.success(stat.availableBytes)
                    } catch (e: Exception) {
                        result.success(1024L * 1024L * 1024L)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 9010) {
            val granted = grantResults.isNotEmpty() && grantResults.any { it == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }
}
