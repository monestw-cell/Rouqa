package com.ruqa.chessanalyzer

import android.app.*
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel

/**
 * AnalysisForegroundService — خدمة التحليل في الخلفية
 *
 * تحل مشكلة Android 13+ التي تقتل isolates و services في الخلفية.
 *
 * الميزات:
 * - Foreground Service مع notification
 * - WakeLock لمنع النوم أثناء التحليل
 * - إشعار يتحدث بالتقدم
 * - إيقاف نظيف عند إغلاق التطبيق
 * - MethodChannel للتواصل مع Flutter
 * - دعم أذونات الإشعارات (Android 13+)
 */
class AnalysisForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "ruqa_analysis_channel"
        const val CHANNEL_NAME = "تحليل المباريات"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "com.ruqa.chessanalyzer.START_ANALYSIS"
        const val ACTION_STOP = "com.ruqa.chessanalyzer.STOP_ANALYSIS"
        const val ACTION_UPDATE_PROGRESS = "com.ruqa.chessanalyzer.UPDATE_PROGRESS"

        // Extra keys
        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_CURRENT_MOVE = "current_move"
        const val EXTRA_TOTAL_MOVES = "total_moves"

        // MethodChannel name — Must match background_analysis_service.dart
        const val METHOD_CHANNEL = "com.ruqa.chessanalyzer/background_analysis"

        private const val TAG = "AnalysisService"
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var isRunning = false

    // ─── MethodChannel Handler ──────────────────────────────────────────

    /**
     * تسجيل MethodChannel — Register method channel handler
     *
     * يُستدعى من MainActivity لتسجيل قناة التواصل مع Flutter.
     * يجب أن يُستدعى مرة واحدة فقط.
     */
    fun registerMethodChannel(messenger: io.flutter.plugin.common.BinaryMessenger) {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAnalysis" -> {
                    val intent = Intent(this, AnalysisForegroundService::class.java).apply {
                        action = ACTION_START
                    }
                    startService(intent)
                    result.success(null)
                }
                "stopAnalysis" -> {
                    val intent = Intent(this, AnalysisForegroundService::class.java).apply {
                        action = ACTION_STOP
                    }
                    startService(intent)
                    result.success(null)
                }
                "updateProgress" -> {
                    val progress = call.argument<Int>("progress") ?: 0
                    val currentMove = call.argument<String>("currentMove") ?: ""
                    val totalMoves = call.argument<Int>("totalMoves") ?: 0
                    val intent = Intent(this, AnalysisForegroundService::class.java).apply {
                        action = ACTION_UPDATE_PROGRESS
                        putExtra(EXTRA_PROGRESS, progress)
                        putExtra(EXTRA_CURRENT_MOVE, currentMove)
                        putExtra(EXTRA_TOTAL_MOVES, totalMoves)
                    }
                    startService(intent)
                    result.success(null)
                }
                "checkNotificationPermission" -> {
                    val hasPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        ContextCompat.checkSelfPermission(
                            this, android.Manifest.permission.POST_NOTIFICATIONS
                        ) == PackageManager.PERMISSION_GRANTED
                    } else {
                        true // لا حاجة لإذن قبل Android 13
                    }
                    result.success(hasPermission)
                }
                "requestNotificationPermission" -> {
                    // لا يمكن طلب الأذونات من Service — يجب طلبها من Activity
                    // نُرجع false ويجب على Flutter طلبها من MainActivity
                    result.success(false)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ─── Service Lifecycle ──────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startAnalysis()
            }
            ACTION_STOP -> {
                stopAnalysis()
            }
            ACTION_UPDATE_PROGRESS -> {
                val progress = intent.getIntExtra(EXTRA_PROGRESS, 0)
                val currentMove = intent.getStringExtra(EXTRA_CURRENT_MOVE) ?: ""
                val totalMoves = intent.getIntExtra(EXTRA_TOTAL_MOVES, 0)
                updateNotification(progress, currentMove, totalMoves)
            }
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /**
     * بدء التحليل — Start analysis with foreground service
     */
    private fun startAnalysis() {
        if (isRunning) return
        isRunning = true

        // Acquire WakeLock
        acquireWakeLock()

        // التحقق من إذن الإشعارات (Android 13+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val hasPermission = ContextCompat.checkSelfPermission(
                this, android.Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED

            if (!hasPermission) {
                Log.w(TAG, "إذن الإشعارات غير ممنوح — الإشعار قد لا يظهر")
            }
        }

        // Start as foreground service with notification
        val notification = createNotification(0, "", 0)
        startForeground(NOTIFICATION_ID, notification)

        Log.d(TAG, "بدء خدمة التحليل في الخلفية")
    }

    /**
     * إيقاف التحليل — Stop analysis
     */
    private fun stopAnalysis() {
        isRunning = false
        releaseWakeLock()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()

        Log.d(TAG, "إيقاف خدمة التحليل")
    }

    /**
     * إنشاء قناة الإشعارات — Create notification channel (Android 8+)
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "إشعار تقدم تحليل المباريات"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    /**
     * إنشاء الإشعار — Create notification
     */
    private fun createNotification(progress: Int, currentMove: String, totalMoves: Int): Notification {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, AnalysisForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val progressText = if (totalMoves > 0) {
            "جاري التحليل: $progress/$totalMoves — $currentMove"
        } else {
            "جاري التحليل..."
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("رُقعة — تحليل المباراة")
            .setContentText(progressText)
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setOngoing(true)
            .setProgress(totalMoves, progress, progress == 0 && totalMoves == 0)
            .setContentIntent(pendingIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "إيقاف",
                stopPendingIntent
            )
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setSilent(true) // لا صوت عند التحديث
            .build()
    }

    /**
     * تحديث الإشعار — Update notification with progress
     */
    private fun updateNotification(progress: Int, currentMove: String, totalMoves: Int) {
        if (!isRunning) return

        val notification = createNotification(progress, currentMove, totalMoves)
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, notification)
    }

    /**
     * Acquire WakeLock — لمنع النوم أثناء التحليل
     */
    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "ruqa::AnalysisWakeLock"
            ).apply {
                acquire(30 * 60 * 1000L) // 30 minutes max
            }
        } catch (e: Exception) {
            Log.e(TAG, "فشل الحصول على WakeLock: ${e.message}")
        }
    }

    /**
     * Release WakeLock
     */
    private fun releaseWakeLock() {
        try {
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                }
            }
            wakeLock = null
        } catch (e: Exception) {
            Log.e(TAG, "فشل تحرير WakeLock: ${e.message}")
        }
    }

    override fun onDestroy() {
        releaseWakeLock()
        isRunning = false
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // تنظيف عند إزالة التطبيق من المهام
        stopAnalysis()
        super.onTaskRemoved(rootIntent)
    }
}
