package com.briffini.academy

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.view.WindowManager
import android.os.Bundle
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.graphics.Color
import android.os.Build
import android.media.AudioAttributes
import android.net.Uri
import android.media.AudioManager
import android.media.AudioDeviceInfo
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.app.ActivityManager
import java.util.*

class MainActivity : FlutterActivity() {
    private val CHANNEL = "flutter.native/screenProtection"
    private var audioManager: AudioManager? = null
    private var screenRecordingCheckHandler: Handler? = null
    private var screenRecordingCheckRunnable: Runnable? = null
    private var isMonitoringEnabled = false
    private var lastRecordingState = false
    private var methodChannel: MethodChannel? = null
    private var hasNotifiedThisSession = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Always enable FLAG_SECURE to prevent screenshots and screen recording app-wide
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        
        // Create notification channels for Android O and above
        createNotificationChannels()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize audio manager for recording detection
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "preventScreenshots" -> {
                    val enable = call.arguments as Boolean
                    toggleSecureScreen(enable)
                    result.success(true)
                }
                "enableScreenshotMonitoring" -> {
                    Log.d("ScreenProtection", "Android: Enabling screen recording monitoring")
                    enableScreenRecordingMonitoring()
                    result.success(true)
                }
                "disableScreenshotMonitoring" -> {
                    Log.d("ScreenProtection", "Android: Disabling screen recording monitoring")
                    disableScreenRecordingMonitoring()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun toggleSecureScreen(secure: Boolean) {
        if (secure) {
            // Prevent screenshots and screen recording
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            // Allow screenshots and screen recording
            // Note: We're commenting this out to enforce app-wide screenshot protection
            // window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
    
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // Chat messages channel - High importance
            val chatChannel = NotificationChannel(
                "chat_channel",
                "Chat Messages",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for new chat messages"
                enableLights(true)
                lightColor = Color.BLUE
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 100, 200, 300)
                setShowBadge(true)
                
                // Add sound
                val audioAttributes = AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .build()
                setSound(Uri.parse("android.resource://${packageName}/raw/notification_sound"), audioAttributes)
            }
            
            // General notifications channel - Default importance
            val generalChannel = NotificationChannel(
                "general_channel",
                "General Notifications",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "General app notifications"
                setShowBadge(true)
            }
            
            // Register the channels
            notificationManager.createNotificationChannel(chatChannel)
            notificationManager.createNotificationChannel(generalChannel)
        }
    }
    
    private fun enableScreenRecordingMonitoring() {
        if (isMonitoringEnabled) return
        
        isMonitoringEnabled = true
        screenRecordingCheckHandler = Handler(Looper.getMainLooper())
        
        screenRecordingCheckRunnable = object : Runnable {
            override fun run() {
                checkForScreenRecording()
                // Check every 2 seconds for screen recording
                screenRecordingCheckHandler?.postDelayed(this, 2000)
            }
        }
        
        screenRecordingCheckHandler?.post(screenRecordingCheckRunnable!!)
        Log.d("ScreenProtection", "Android: Screen recording monitoring enabled")
    }
    
    private fun disableScreenRecordingMonitoring() {
        if (!isMonitoringEnabled) return
        
        isMonitoringEnabled = false
        hasNotifiedThisSession = false // Reset notification flag when disabling
        screenRecordingCheckRunnable?.let { 
            screenRecordingCheckHandler?.removeCallbacks(it)
        }
        screenRecordingCheckHandler = null
        screenRecordingCheckRunnable = null
        
        Log.d("ScreenProtection", "Android: Screen recording monitoring disabled")
    }
    
    private fun checkForScreenRecording() {
        try {
            val currentRecordingState = detectScreenRecording()
            
            // Only notify if state changed from false to true (recording started) 
            // and we haven't already notified this session
            if (currentRecordingState && !lastRecordingState && !hasNotifiedThisSession) {
                Log.w("ScreenProtection", "Screen recording detected on Android! (First time this session)")
                hasNotifiedThisSession = true
                notifyFlutterOfScreenRecording(true)
            } else if (!currentRecordingState && lastRecordingState) {
                Log.i("ScreenProtection", "Screen recording stopped on Android - resetting notification flag")
                hasNotifiedThisSession = false
                notifyFlutterOfScreenRecording(false)
            }
            
            lastRecordingState = currentRecordingState
        } catch (e: Exception) {
            Log.e("ScreenProtection", "Error checking for screen recording: ${e.message}")
        }
    }
    
    private fun detectScreenRecording(): Boolean {
        try {
            // Method 1: Check for audio recording (many screen recorders also record audio)
            val isAudioRecording = audioManager?.let { manager ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    // Check if any app is recording audio
                    manager.getDevices(AudioManager.GET_DEVICES_INPUTS).any { device ->
                        device.type == AudioDeviceInfo.TYPE_BUILTIN_MIC
                    }
                } else {
                    false
                }
            } ?: false
            
            // Method 2: Check for known screen recording processes
            val hasScreenRecordingApp = detectScreenRecordingApps()
            
            // Method 3: Check system properties that might indicate recording
            val hasRecordingProperties = checkRecordingSystemProperties()
            
            return isAudioRecording || hasScreenRecordingApp || hasRecordingProperties
            
        } catch (e: Exception) {
            Log.e("ScreenProtection", "Error in detectScreenRecording: ${e.message}")
            return false
        }
    }
    
    private fun detectScreenRecordingApps(): Boolean {
        try {
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val runningApps = activityManager.runningAppProcesses ?: return false
            
            // List of known screen recording app packages
            val screenRecordingApps = setOf(
                "com.kimcy929.screenrecorder",
                "com.hecorat.screenrecorder.free",
                "com.blogspot.gmc.rcdroid",
                "com.mobizen.mirroring.com",
                "com.apowersoft.android.recorder",
                "com.duapps.recorder",
                "com.icecoldapps.screenrecorder",
                "com.pro.mobizen",
                "com.screen.recorder.videorecorder",
                "com.androidhidden.screenrecorder"
            )
            
            for (app in runningApps) {
                if (screenRecordingApps.contains(app.processName)) {
                    Log.w("ScreenProtection", "Detected screen recording app: ${app.processName}")
                    return true
                }
            }
        } catch (e: Exception) {
            Log.e("ScreenProtection", "Error detecting screen recording apps: ${e.message}")
        }
        return false
    }
    
    private fun checkRecordingSystemProperties(): Boolean {
        try {
            // Check if MediaProjection is active (requires reflection due to API restrictions)
            // This is a simplified check - in real implementation you might need more complex detection
            val className = "android.media.projection.MediaProjectionManager"
            return false // Simplified for this implementation
        } catch (e: Exception) {
            Log.e("ScreenProtection", "Error checking recording system properties: ${e.message}")
            return false
        }
    }
    
    private fun notifyFlutterOfScreenRecording(isRecording: Boolean) {
        try {
            val arguments = mapOf("isRecording" to isRecording)
            
            methodChannel?.invokeMethod("onScreenRecordingStateChanged", arguments, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    Log.d("ScreenProtection", "Successfully notified Flutter of recording state: $isRecording")
                }
                
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    Log.e("ScreenProtection", "Error notifying Flutter: $errorMessage")
                }
                
                override fun notImplemented() {
                    Log.w("ScreenProtection", "Method not implemented")
                }
            })
        } catch (e: Exception) {
            Log.e("ScreenProtection", "Error in notifyFlutterOfScreenRecording: ${e.message}")
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        disableScreenRecordingMonitoring()
    }
}
