package com.kinvoice.kinvoice

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class AmbientAudioService : Service() {

    companion object {
        const val CHANNEL_ID = "kinvoice_ambient_ear"
        const val CHANNEL_NAME = "Kinvoice Recording Service"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START = "ACTION_START_AMBIENT_SERVICE"
        const val ACTION_UPDATE = "ACTION_UPDATE_RECORDING_NOTIFICATION"
        const val ACTION_STOP = "ACTION_STOP_AMBIENT_SERVICE"
        const val ACTION_TOGGLE_PAUSE = "com.kinvoice.kinvoice.ACTION_TOGGLE_PAUSE"
        const val ACTION_STOP_AND_SAVE = "com.kinvoice.kinvoice.ACTION_STOP_AND_SAVE"

        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_ELAPSED = "extra_elapsed"
        const val EXTRA_IS_PAUSED = "extra_is_paused"
        const val EXTRA_STATUS_TEXT = "extra_status_text"

        var isRunning = false
            private set

        var isPaused = false
            private set

        var onActionCallback: ((String) -> Unit)? = null

        fun startService(
            context: Context,
            title: String = "Kinvoice Studio Recorder",
            elapsed: String = "00:00:00",
            paused: Boolean = false,
            statusText: String = "Recording audio..."
        ) {
            val intent = Intent(context, AmbientAudioService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_ELAPSED, elapsed)
                putExtra(EXTRA_IS_PAUSED, paused)
                putExtra(EXTRA_STATUS_TEXT, statusText)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun updateNotification(
            context: Context,
            title: String = "Kinvoice Studio Recorder",
            elapsed: String = "00:00:00",
            paused: Boolean = false,
            statusText: String = "Recording audio..."
        ) {
            if (!isRunning) {
                startService(context, title, elapsed, paused, statusText)
                return
            }
            val intent = Intent(context, AmbientAudioService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_ELAPSED, elapsed)
                putExtra(EXTRA_IS_PAUSED, paused)
                putExtra(EXTRA_STATUS_TEXT, statusText)
            }
            context.startService(intent)
        }

        fun stopService(context: Context) {
            val intent = Intent(context, AmbientAudioService::class.java).apply {
                action = ACTION_STOP
            }
            context.stopService(intent)
        }
    }

    private var currentTitle: String = "Kinvoice Studio Recorder"
    private var currentElapsed: String = "00:00:00"
    private var currentStatusText: String = "Recording audio..."

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(true)
                stopSelf()
                isRunning = false
                isPaused = false
                return START_NOT_STICKY
            }
            ACTION_TOGGLE_PAUSE -> {
                isPaused = !isPaused
                currentStatusText = if (isPaused) "Recording paused" else "Recording audio..."
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.notify(NOTIFICATION_ID, buildNotification())
                onActionCallback?.invoke("pause_resume")
                return START_STICKY
            }
            ACTION_STOP_AND_SAVE -> {
                onActionCallback?.invoke("stop_and_save")
                val launchIntent = Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    putExtra("notification_action", "stop_and_save")
                }
                startActivity(launchIntent)
                return START_STICKY
            }
            ACTION_UPDATE -> {
                currentTitle = intent.getStringExtra(EXTRA_TITLE) ?: currentTitle
                currentElapsed = intent.getStringExtra(EXTRA_ELAPSED) ?: currentElapsed
                isPaused = intent.getBooleanExtra(EXTRA_IS_PAUSED, isPaused)
                currentStatusText = intent.getStringExtra(EXTRA_STATUS_TEXT) ?: currentStatusText
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.notify(NOTIFICATION_ID, buildNotification())
                return START_STICKY
            }
            else -> {
                currentTitle = intent?.getStringExtra(EXTRA_TITLE) ?: "Kinvoice Studio Recorder"
                currentElapsed = intent?.getStringExtra(EXTRA_ELAPSED) ?: "00:00:00"
                isPaused = intent?.getBooleanExtra(EXTRA_IS_PAUSED, false) ?: false
                currentStatusText = intent?.getStringExtra(EXTRA_STATUS_TEXT) ?: "Recording audio..."
                val notification = buildNotification()
                startForeground(NOTIFICATION_ID, notification)
                isRunning = true
                return START_STICKY
            }
        }
    }

    override fun onDestroy() {
        isRunning = false
        isPaused = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Ongoing audio capture and real-time recording controls"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val immutableFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val contentPendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag
        )

        val pauseResumeIntent = Intent(this, AmbientAudioService::class.java).apply {
            action = ACTION_TOGGLE_PAUSE
        }
        val pauseResumePendingIntent = PendingIntent.getService(
            this,
            1,
            pauseResumeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag
        )

        val stopSaveIntent = Intent(this, AmbientAudioService::class.java).apply {
            action = ACTION_STOP_AND_SAVE
        }
        val stopSavePendingIntent = PendingIntent.getService(
            this,
            2,
            stopSaveIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag
        )

        val iconRes = applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_btn_speak_now
        val pauseLabel = if (isPaused) "Resume" else "Pause"
        val pauseIcon = if (isPaused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause
        val waveStatus = if (isPaused) "⏸ $currentStatusText • $currentElapsed" else "🎙️ $currentStatusText • $currentElapsed"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(currentTitle)
            .setContentText(waveStatus)
            .setSubText(currentElapsed)
            .setSmallIcon(iconRes)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentPendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(pauseIcon, pauseLabel, pauseResumePendingIntent)
            .addAction(android.R.drawable.ic_menu_save, "Stop & Save", stopSavePendingIntent)
            .build()
    }
}
