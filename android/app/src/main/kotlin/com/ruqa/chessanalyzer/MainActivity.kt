package com.ruqa.chessanalyzer

import android.annotation.SuppressLint
import android.app.ActivityManager
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity — نقطة دخول Flutter
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val THERMAL_CHANNEL = "com.ruqa.chessanalyzer/thermal"
        private const val BACKGROUND_ANALYSIS_CHANNEL = "com.ruqa.chessanalyzer/background_analysis"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // قناة الحرارة والبطارية
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, THERMAL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getThermalData" -> {
                        val data = getThermalData()
                        result.success(data)
                    }
                    "requestBatteryOptimizationExemption" -> {
                        requestBatteryOptimizationExemption()
                        result.success(true)
                    }
                    "isBatteryOptimizationExempted" -> {
                        result.success(isBatteryOptimizationExempted())
                    }
                    else -> result.notImplemented()
                }
            }

        // قناة خدمة التحليل في الخلفية
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKGROUND_ANALYSIS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startAnalysis" -> {
                        startService(Intent(this, AnalysisForegroundService::class.java).apply {
                            action = AnalysisForegroundService.ACTION_START
                        })
                        result.success(null)
                    }
                    "stopAnalysis" -> {
                        startService(Intent(this, AnalysisForegroundService::class.java).apply {
                            action = AnalysisForegroundService.ACTION_STOP
                        })
                        result.success(null)
                    }
                    "updateProgress" -> {
                        val progress = call.argument<Int>("progress") ?: 0
                        val currentMove = call.argument<String>("currentMove") ?: ""
                        val totalMoves = call.argument<Int>("totalMoves") ?: 0
                        startService(Intent(this, AnalysisForegroundService::class.java).apply {
                            action = AnalysisForegroundService.ACTION_UPDATE_PROGRESS
                            putExtra(AnalysisForegroundService.EXTRA_PROGRESS, progress)
                            putExtra(AnalysisForegroundService.EXTRA_CURRENT_MOVE, currentMove)
                            putExtra(AnalysisForegroundService.EXTRA_TOTAL_MOVES, totalMoves)
                        })
                        result.success(null)
                    }
                    "checkNotificationPermission" -> {
                        val hasPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            ContextCompat.checkSelfPermission(
                                this, android.Manifest.permission.POST_NOTIFICATIONS
                            ) == PackageManager.PERMISSION_GRANTED
                        } else { true }
                        result.success(hasPermission)
                    }
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                                1001
                            )
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @SuppressLint("NewApi")
    private fun getThermalData(): Map<String, Any?> {
        val data = mutableMapOf<String, Any?>("isSupported" to true)
        try {
            val batteryManager = getSystemService(BATTERY_SERVICE) as? BatteryManager
            data["batteryLevel"] = batteryManager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 100
            data["isCharging"] = batteryManager?.isCharging ?: false

            try {
                val batteryIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                if (batteryIntent != null) {
                    val temp = batteryIntent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1)
                    if (temp != -1) data["batteryTemperature"] = temp / 10.0
                    val status = batteryIntent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                    data["isCharging"] = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                            status == BatteryManager.BATTERY_STATUS_FULL
                }
            } catch (_: Exception) {}

            val powerManager = getSystemService(POWER_SERVICE) as? PowerManager
            data["isPowerSave"] = powerManager?.isPowerSaveMode ?: false

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try {
                    data["thermalStatus"] = powerManager?.currentThermalStatus ?: 0
                } catch (_: Exception) {}
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                try {
                    val am = getSystemService(ACTIVITY_SERVICE) as? ActivityManager
                    if (am != null) data["performanceClass"] = am.performanceClass
                } catch (_: Exception) {}
            }

            try {
                val am = getSystemService(ACTIVITY_SERVICE) as? ActivityManager
                if (am != null) {
                    val memInfo = ActivityManager.MemoryInfo()
                    am.getMemoryInfo(memInfo)
                    data["availableMemoryMb"] = (memInfo.availMem / (1024 * 1024)).toInt()
                }
            } catch (_: Exception) {}

        } catch (e: Exception) {
            data["isSupported"] = false
            data["error"] = e.message
        }
        return data
    }

    private fun requestBatteryOptimizationExemption() {
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = android.net.Uri.parse("package:${packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                })
            } catch (_: Exception) {}
        }
    }

    private fun isBatteryOptimizationExempted(): Boolean {
        return try {
            val powerManager = getSystemService(POWER_SERVICE) as? PowerManager
            powerManager?.isIgnoringBatteryOptimizations(packageName) ?: false
        } catch (_: Exception) { false }
    }
}
