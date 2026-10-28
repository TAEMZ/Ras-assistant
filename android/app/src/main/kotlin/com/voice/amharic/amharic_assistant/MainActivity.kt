package com.voice.amharic.amharic_assistant

import android.accessibilityservice.AccessibilityService
import android.app.ActivityManager
import android.app.SearchManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.Uri
import android.os.BatteryManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.os.Build
import android.provider.AlarmClock
import android.provider.MediaStore
import android.provider.Settings
import android.view.KeyEvent
import androidx.annotation.NonNull
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.voice.amharic.assistant/native_actions"
    private var ttsAudioTrack: AudioTrack? = null
    private var pendingWakeTrigger = false
    private var isFlashlightOn = false

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "makeDirectCall" -> {
                    val number = call.argument<String>("phoneNumber")
                    if (!number.isNullOrEmpty()) {
                        try {
                            val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$number"))
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            val dialIntent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number"))
                            dialIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(dialIntent)
                            result.success(true)
                        }
                    } else {
                        result.error("INVALID_NUMBER", "Phone number is empty", null)
                    }
                }
                "openCamera" -> {
                    try {
                        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CAMERA_ERROR", e.message, null)
                    }
                }
                "openWifiSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WIFI_ERROR", e.message, null)
                    }
                }
                "openBluetoothSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BLUETOOTH_ERROR", e.message, null)
                    }
                }
                "openSoundSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_SOUND_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SOUND_ERROR", e.message, null)
                    }
                }
                "getBatteryLevel" -> {
                    val batteryIntent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                    val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                    val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                    if (level >= 0 && scale > 0) {
                        val pct = (level * 100) / scale
                        result.success(pct)
                    } else {
                        result.success(-1)
                    }
                }
                "getInstalledApps" -> {
                    try {
                        val pm = context.packageManager
                        val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
                            addCategory(Intent.CATEGORY_LAUNCHER)
                        }
                        val apps = pm.queryIntentActivities(mainIntent, 0)
                        val appList = mutableListOf<Map<String, String>>()
                        for (resolveInfo in apps) {
                            val label = resolveInfo.loadLabel(pm)?.toString() ?: ""
                            val packageName = resolveInfo.activityInfo.packageName
                            if (label.isNotEmpty() && packageName != context.packageName) {
                                var sizeBytes = 0L
                                try {
                                    val aInfo = pm.getApplicationInfo(packageName, 0)
                                    val bFile = aInfo.sourceDir?.let { java.io.File(it) }
                                    if (bFile != null && bFile.exists()) sizeBytes += bFile.length()
                                    aInfo.splitSourceDirs?.forEach { sPath ->
                                        val sFile = java.io.File(sPath)
                                        if (sFile.exists()) sizeBytes += sFile.length()
                                    }
                                } catch (_: Exception) {}
                                val sizeMb = String.format(java.util.Locale.US, "%.1f MB", sizeBytes / (1024.0 * 1024.0))
                                appList.add(mapOf(
                                    "name" to label,
                                    "packageName" to packageName,
                                    "sizeMb" to sizeMb,
                                    "sizeBytes" to sizeBytes.toString()
                                ))
                            }
                        }
                        result.success(appList)
                    } catch (e: Exception) {
                        result.error("APPS_ERROR", e.message, null)
                    }
                }
                "launchApp" -> {
                    val target = call.argument<String>("packageName") ?: call.argument<String>("name")
                    if (!target.isNullOrEmpty()) {
                        try {
                            val pm = context.packageManager
                            var launchIntent = pm.getLaunchIntentForPackage(target)

                            if (launchIntent == null) {
                                val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
                                    addCategory(Intent.CATEGORY_LAUNCHER)
                                }
                                val apps = pm.queryIntentActivities(mainIntent, 0)
                                val lowerTarget = target.lowercase().trim()

                                // Exact match first
                                for (resolveInfo in apps) {
                                    val label = resolveInfo.loadLabel(pm)?.toString() ?: ""
                                    val pkg = resolveInfo.activityInfo.packageName
                                    if (label.lowercase() == lowerTarget || pkg.lowercase() == lowerTarget) {
                                        launchIntent = pm.getLaunchIntentForPackage(pkg)
                                        break
                                    }
                                }

                                // Substring match fallback
                                if (launchIntent == null) {
                                    for (resolveInfo in apps) {
                                        val label = resolveInfo.loadLabel(pm)?.toString() ?: ""
                                        val pkg = resolveInfo.activityInfo.packageName
                                        if (label.lowercase().contains(lowerTarget) || pkg.lowercase().contains(lowerTarget)) {
                                            launchIntent = pm.getLaunchIntentForPackage(pkg)
                                            break
                                        }
                                    }
                                }

                                // Fuzzy typo match fallback (Levenshtein distance <= 2)
                                if (launchIntent == null) {
                                    var bestDist = Int.MAX_VALUE
                                    var bestPkg: String? = null
                                    for (resolveInfo in apps) {
                                        val label = (resolveInfo.loadLabel(pm)?.toString() ?: "").lowercase()
                                        val pkg = resolveInfo.activityInfo.packageName.lowercase()
                                        val dist = minOf(levenshtein(label, lowerTarget), levenshtein(pkg, lowerTarget))
                                        if (dist <= 2 && dist < bestDist) {
                                            bestDist = dist
                                            bestPkg = resolveInfo.activityInfo.packageName
                                        }
                                    }
                                    if (bestPkg != null) {
                                        launchIntent = pm.getLaunchIntentForPackage(bestPkg)
                                    }
                                }
                            }

                            if (launchIntent != null) {
                                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                context.startActivity(launchIntent)
                                result.success(true)
                            } else {
                                result.error("CANNOT_LAUNCH", "No launch intent found for $target", null)
                            }
                        } catch (e: Exception) {
                            result.error("LAUNCH_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_PACKAGE", "Package name is null or empty", null)
                    }
                }
                "getAppInfo" -> {
                    val target = call.argument<String>("packageName") ?: call.argument<String>("name")
                    if (!target.isNullOrEmpty()) {
                        try {
                            val pm = context.packageManager
                            var matchedPkg: String? = null
                            var matchedLabel: String? = null

                            val lowerTarget = target.lowercase().trim()
                            if (lowerTarget == "ras" || lowerTarget == "this app" || lowerTarget == "assistant" || lowerTarget.contains("amharic")) {
                                matchedPkg = context.packageName
                                matchedLabel = "Ras Assistant"
                            } else {
                                try {
                                    val pi = pm.getPackageInfo(target, 0)
                                    matchedPkg = pi.packageName
                                    matchedLabel = pi.applicationInfo?.loadLabel(pm)?.toString() ?: pi.packageName
                                } catch (_: Exception) {
                                    val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
                                        addCategory(Intent.CATEGORY_LAUNCHER)
                                    }
                                    val apps = pm.queryIntentActivities(mainIntent, 0)
                                for (resolveInfo in apps) {
                                    val label = resolveInfo.loadLabel(pm)?.toString() ?: ""
                                    val pkg = resolveInfo.activityInfo.packageName
                                    if (label.lowercase().contains(lowerTarget) || pkg.lowercase().contains(lowerTarget)) {
                                        matchedPkg = pkg
                                        matchedLabel = label
                                        break
                                    }
                                }

                                if (matchedPkg == null) {
                                    var bestDist = Int.MAX_VALUE
                                    for (resolveInfo in apps) {
                                        val label = (resolveInfo.loadLabel(pm)?.toString() ?: "").lowercase()
                                        val pkg = resolveInfo.activityInfo.packageName.lowercase()
                                        val dist = minOf(levenshtein(label, lowerTarget), levenshtein(pkg, lowerTarget))
                                        if (dist <= 2 && dist < bestDist) {
                                            bestDist = dist
                                            matchedPkg = resolveInfo.activityInfo.packageName
                                            matchedLabel = resolveInfo.loadLabel(pm)?.toString()
                                        }
                                    }
                                }
                            }
                        }

                            if (matchedPkg != null) {
                                val pInfo = pm.getPackageInfo(matchedPkg, 0)
                                val appInfo = try {
                                    pm.getApplicationInfo(matchedPkg, PackageManager.GET_META_DATA)
                                } catch (_: Exception) {
                                    pInfo.applicationInfo
                                }
                                var sizeBytes = 0L
                                val baseFile = appInfo?.sourceDir?.let { java.io.File(it) }
                                if (baseFile != null && baseFile.exists()) {
                                    sizeBytes += baseFile.length()
                                }
                                appInfo?.splitSourceDirs?.forEach { splitPath ->
                                    val splitFile = java.io.File(splitPath)
                                    if (splitFile.exists()) {
                                        sizeBytes += splitFile.length()
                                    }
                                }
                                val sizeMb = String.format(java.util.Locale.US, "%.1f MB", sizeBytes / (1024.0 * 1024.0))
                                val versionName = pInfo.versionName ?: "Unknown"

                                result.success(mapOf(
                                    "name" to (matchedLabel ?: matchedPkg),
                                    "packageName" to matchedPkg,
                                    "sizeMb" to sizeMb,
                                    "sizeBytes" to sizeBytes.toString(),
                                    "version" to versionName
                                ))
                            } else {
                                result.success(null)
                            }
                        } catch (e: Exception) {
                            result.error("APP_INFO_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_TARGET", "Application name or package is empty", null)
                    }
                }
                "searchFiles" -> {
                    val query = call.argument<String>("query")
                    val category = call.argument<String>("category") ?: "all"
                    val limit = call.argument<Int>("limit") ?: 20
                    try {
                        val files = DeviceSearchService.searchFiles(context, query, category, limit)
                        result.success(files)
                    } catch (e: Exception) {
                        result.error("SEARCH_ERROR", e.message, null)
                    }
                }
                "openFile" -> {
                    val filePath = call.argument<String>("filePath")
                    if (!filePath.isNullOrEmpty()) {
                        val opened = DeviceSearchService.openFile(context, filePath)
                        result.success(opened)
                    } else {
                        result.error("INVALID_PATH", "File path is empty", null)
                    }
                }
                "searchContacts" -> {
                    val query = call.argument<String>("query") ?: ""
                    try {
                        val contacts = DeviceSearchService.searchContacts(context, query)
                        result.success(contacts)
                    } catch (e: Exception) {
                        result.error("CONTACTS_ERROR", e.message, null)
                    }
                }
                "getStorageDiagnostics" -> {
                    try {
                        val diagnostics = DeviceSearchService.getStorageDiagnostics()
                        result.success(diagnostics)
                    } catch (e: Exception) {
                        result.error("STORAGE_ERROR", e.message, null)
                    }
                }
                "startBackgroundService" -> {
                    try {
                        val serviceIntent = Intent(this@MainActivity, RasVoiceService::class.java)
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_START_ERROR", e.message, null)
                    }
                }
                "stopBackgroundService" -> {
                    try {
                        val serviceIntent = Intent(this@MainActivity, RasVoiceService::class.java)
                        stopService(serviceIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_STOP_ERROR", e.message, null)
                    }
                }
                "confirmWakeWord" -> {
                    try {
                        RasVoiceService.triggerWake()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WAKE_ERROR", e.message, null)
                    }
                }
                "checkOverlayPermission" -> {
                    val canDraw = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    result.success(canDraw)
                }
                "requestOverlayPermission" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                        try {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            ).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OVERLAY_ERROR", e.message, null)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "checkStoragePermission" -> {
                    val hasAccess = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                        android.os.Environment.isExternalStorageManager()
                    } else {
                        true
                    }
                    result.success(hasAccess)
                }
                "requestStoragePermission" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R &&
                        !android.os.Environment.isExternalStorageManager()) {
                        try {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                Uri.parse("package:$packageName")
                            ).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            // Fallback to generic all files access settings
                            try {
                                val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("STORAGE_PERM_ERROR", e2.message, null)
                            }
                        }
                    } else {
                        result.success(true)
                    }
                }
                "playPcmAudio" -> {
                    val pcmData = call.argument<ByteArray>("pcmData")
                    if (pcmData != null && pcmData.isNotEmpty()) {
                        try {
                            ttsAudioTrack?.run {
                                try {
                                    stop()
                                    release()
                                } catch (_: Exception) {}
                            }
                            ttsAudioTrack = null

                            val sampleRate = 16000
                            val audioAttributes = AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_ASSISTANT)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                .build()
                            val audioFormat = AudioFormat.Builder()
                                .setSampleRate(sampleRate)
                                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                                .build()

                            val minBuf = AudioTrack.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
                            val bufSize = Math.max(minBuf, pcmData.size)

                            val track = AudioTrack(
                                audioAttributes,
                                audioFormat,
                                bufSize,
                                AudioTrack.MODE_STATIC,
                                AudioManager.AUDIO_SESSION_ID_GENERATE
                            )
                            val written = track.write(pcmData, 0, pcmData.size)
                            track.setVolume(1.0f)
                            val frames = pcmData.size / 2
                            android.util.Log.i("TTS-DIAG", "AudioTrack: pcmBytes=${pcmData.size}, written=$written, bufSize=$bufSize, minBuf=$minBuf, frames=$frames, duration=${frames * 1000 / sampleRate}ms, sampleRate=$sampleRate, mode=STATIC")
                            ttsAudioTrack = track
                            track.play()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("AUDIO_PLAY_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_AUDIO_DATA", "PCM byte array is empty", null)
                    }
                }
                "stopPcmAudio" -> {
                    try {
                        ttsAudioTrack?.run {
                            try {
                                stop()
                                release()
                            } catch (_: Exception) {}
                        }
                        ttsAudioTrack = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("AUDIO_STOP_ERROR", e.message, null)
                    }
                }
                "toggleFlashlight" -> {
                    val desiredState = call.argument<Boolean>("state")
                    try {
                        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
                        val cameraId = cameraManager?.cameraIdList?.firstOrNull { id ->
                            val chars = cameraManager.getCameraCharacteristics(id)
                            chars.get(android.hardware.camera2.CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                        } ?: cameraManager?.cameraIdList?.firstOrNull() ?: "0"

                        isFlashlightOn = desiredState ?: !isFlashlightOn
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                            cameraManager?.setTorchMode(cameraId, isFlashlightOn)
                        }
                        result.success(mapOf(
                            "enabled" to isFlashlightOn,
                            "message" to if (isFlashlightOn) "Flashlight turned on" else "Flashlight turned off"
                        ))
                    } catch (e: Exception) {
                        result.error("FLASHLIGHT_ERROR", e.message, null)
                    }
                }
                "getMemoryUsage" -> {
                    try {
                        val actManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                        val memInfo = ActivityManager.MemoryInfo()
                        actManager?.getMemoryInfo(memInfo)
                        val totalMb = memInfo.totalMem / (1024 * 1024)
                        val availMb = memInfo.availMem / (1024 * 1024)
                        val usedMb = totalMb - availMb
                        val percentUsed = if (totalMb > 0) ((usedMb * 100) / totalMb).toInt() else 0
                        val runningProcs = actManager?.runningAppProcesses?.size ?: 0

                        result.success(mapOf(
                            "totalRamMb" to totalMb,
                            "availRamMb" to availMb,
                            "usedRamMb" to usedMb,
                            "percentUsed" to percentUsed,
                            "isLowMemory" to memInfo.lowMemory,
                            "runningProcessesCount" to runningProcs
                        ))
                    } catch (e: Exception) {
                        result.error("MEMORY_ERROR", e.message, null)
                    }
                }
                "setVolume" -> {
                    val stream = call.argument<String>("stream") ?: "media"
                    val level = call.argument<Int>("level")
                    val direction = call.argument<String>("direction")
                    try {
                        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                        val streamType = when (stream.lowercase()) {
                            "ring" -> AudioManager.STREAM_RING
                            "notification" -> AudioManager.STREAM_NOTIFICATION
                            "alarm" -> AudioManager.STREAM_ALARM
                            else -> AudioManager.STREAM_MUSIC
                        }
                        if (level != null && level >= 0) {
                            audioManager?.setStreamVolume(streamType, level, AudioManager.FLAG_SHOW_UI)
                        } else if (direction == "up") {
                            audioManager?.adjustStreamVolume(streamType, AudioManager.ADJUST_RAISE, AudioManager.FLAG_SHOW_UI)
                        } else if (direction == "down") {
                            audioManager?.adjustStreamVolume(streamType, AudioManager.ADJUST_LOWER, AudioManager.FLAG_SHOW_UI)
                        }
                        val maxVol = audioManager?.getStreamMaxVolume(streamType) ?: 15
                        val currentVol = audioManager?.getStreamVolume(streamType) ?: 0
                        result.success(mapOf(
                            "stream" to stream,
                            "volume" to currentVol,
                            "maxVolume" to maxVol,
                            "percent" to if (maxVol > 0) (currentVol * 100 / maxVol) else 0
                        ))
                    } catch (e: Exception) {
                        result.error("VOLUME_ERROR", e.message, null)
                    }
                }
                "getVolume" -> {
                    try {
                        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                        val maxMusic = audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: 15
                        val curMusic = audioManager?.getStreamVolume(AudioManager.STREAM_MUSIC) ?: 0
                        val maxRing = audioManager?.getStreamMaxVolume(AudioManager.STREAM_RING) ?: 15
                        val curRing = audioManager?.getStreamVolume(AudioManager.STREAM_RING) ?: 0
                        result.success(mapOf(
                            "mediaVolume" to curMusic,
                            "mediaMax" to maxMusic,
                            "mediaPercent" to if (maxMusic > 0) (curMusic * 100 / maxMusic) else 0,
                            "ringVolume" to curRing,
                            "ringMax" to maxRing
                        ))
                    } catch (e: Exception) {
                        result.error("VOLUME_ERROR", e.message, null)
                    }
                }
                "setClipboard" -> {
                    val text = call.argument<String>("text") ?: ""
                    try {
                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                        val clip = ClipData.newPlainText("Assistant", text)
                        clipboard?.setPrimaryClip(clip)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CLIPBOARD_ERROR", e.message, null)
                    }
                }
                "getClipboard" -> {
                    try {
                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                        val item = clipboard?.primaryClip?.getItemAt(0)?.text?.toString() ?: ""
                        result.success(item)
                    } catch (e: Exception) {
                        result.error("CLIPBOARD_ERROR", e.message, null)
                    }
                }
                "getDeviceInfo" -> {
                    try {
                        result.success(mapOf(
                            "manufacturer" to android.os.Build.MANUFACTURER,
                            "model" to android.os.Build.MODEL,
                            "brand" to android.os.Build.BRAND,
                            "androidVersion" to android.os.Build.VERSION.RELEASE,
                            "sdkInt" to android.os.Build.VERSION.SDK_INT,
                            "device" to android.os.Build.DEVICE
                        ))
                    } catch (e: Exception) {
                        result.error("DEVICE_INFO_ERROR", e.message, null)
                    }
                }
                "sendSms" -> {
                    val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    try {
                        val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$phoneNumber")).apply {
                            putExtra("sms_body", message)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SMS_ERROR", e.message, null)
                    }
                }
                "openDialer" -> {
                    val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                    try {
                        val dialIntent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phoneNumber")).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(dialIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("DIALER_ERROR", e.message, null)
                    }
                }
                "getRunningApps" -> {
                    try {
                        val actManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                        val running = actManager?.runningAppProcesses?.map { it.processName } ?: emptyList()
                        result.success(running)
                    } catch (e: Exception) {
                        result.error("RUNNING_APPS_ERROR", e.message, null)
                    }
                }
                "mediaControl" -> {
                    val action = call.argument<String>("action") ?: "play_pause"
                    try {
                        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                        val keyCode = when (action.lowercase()) {
                            "play" -> KeyEvent.KEYCODE_MEDIA_PLAY
                            "pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
                            "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
                            "previous", "prev" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
                            "stop" -> KeyEvent.KEYCODE_MEDIA_STOP
                            else -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                        }
                        val eventDown = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
                        val eventUp = KeyEvent(KeyEvent.ACTION_UP, keyCode)
                        audioManager?.dispatchMediaKeyEvent(eventDown)
                        audioManager?.dispatchMediaKeyEvent(eventUp)
                        result.success(mapOf("success" to true, "action" to action))
                    } catch (e: Exception) {
                        result.error("MEDIA_ERROR", e.message, null)
                    }
                }
                "playMediaFromSearch" -> {
                    val query = call.argument<String>("query") ?: ""
                    try {
                        val encodedQuery = Uri.encode(query)
                        val uriIntent = Intent(Intent.ACTION_VIEW, Uri.parse("spotify:search:$encodedQuery")).apply {
                            setPackage("com.spotify.music")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        }
                        context.startActivity(uriIntent)

                        // Actively poll accessibility tree every 250ms for results to render, then click the track
                        var attempts = 0
                        val maxAttempts = 16
                        val words = query.split(" ").filter { it.length > 2 }
                        val handler = android.os.Handler(android.os.Looper.getMainLooper())
                        val pollRunnable = object : Runnable {
                            override fun run() {
                                attempts++
                                val clicked = RasAccessibilityService.clickFirstSpotifyTrack(words)
                                if (!clicked && attempts < maxAttempts) {
                                    handler.postDelayed(this, 250)
                                } else if (!clicked && attempts >= maxAttempts) {
                                    // Fallback: tap first song coordinate if node matching did not resolve
                                    RasAccessibilityService.tap(400f, 615f)
                                }
                            }
                        }
                        handler.postDelayed(pollRunnable, 700)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("MEDIA_PLAY_ERROR", e.message, null)
                    }
                }
                "searchYouTube" -> {
                    val query = call.argument<String>("query") ?: ""
                    try {
                        val encoded = Uri.encode(query)
                        val ytIntent = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.youtube.com/results?search_query=$encoded")).apply {
                            setPackage("com.google.android.youtube")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        context.startActivity(ytIntent)
                        result.success(mapOf("success" to true, "query" to query))
                    } catch (e: Exception) {
                        try {
                            val encoded = Uri.encode(query)
                            val webIntent = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.youtube.com/results?search_query=$encoded")).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            context.startActivity(webIntent)
                            result.success(mapOf("success" to true, "query" to query))
                        } catch (e2: Exception) {
                            result.error("YOUTUBE_ERROR", e2.message, null)
                        }
                    }
                }
                "showNotification" -> {
                    val title = call.argument<String>("title") ?: "Assistant"
                    val message = call.argument<String>("message") ?: ""
                    try {
                        showHeadsUpNotification(title, message)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("NOTIF_ERROR", e.message, null)
                    }
                }
                "setAlarm" -> {
                    val cal = java.util.Calendar.getInstance()
                    val hour = call.argument<Int>("hour") ?: cal.get(java.util.Calendar.HOUR_OF_DAY)
                    val minutes = call.argument<Int>("minutes") ?: 0
                    val message = call.argument<String>("message") ?: "Alarm"
                    try {
                        val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                            putExtra(AlarmClock.EXTRA_HOUR, hour)
                            putExtra(AlarmClock.EXTRA_MINUTES, minutes)
                            putExtra(AlarmClock.EXTRA_MESSAGE, message)
                            putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)

                        // Automatically commit the alarm by clicking "Save" in Samsung Clock
                        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                            try {
                                val saved = RasAccessibilityService.clickNodeContainingText("Save")
                                if (!saved) {
                                    // Tap Samsung Clock Save button inside bottom action pill (625, 2125)
                                    RasAccessibilityService.tap(625f, 2125f)
                                }
                                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                                    try {
                                        RasAccessibilityService.clickNodeContainingText("Save")
                                        RasAccessibilityService.tap(625f, 2125f)
                                    } catch (_: Exception) {}
                                }, 800)
                            } catch (_: Exception) {}
                        }, 1800)

                        result.success(mapOf("success" to true, "hour" to hour, "minutes" to minutes, "message" to message))
                    } catch (e: Exception) {
                        result.error("SET_ALARM_ERROR", e.message, null)
                    }
                }
                "setTimer" -> {
                    val lengthSeconds = call.argument<Int>("lengthSeconds") ?: 300
                    val message = call.argument<String>("message") ?: "Timer"
                    val skipUi = call.argument<Boolean>("skipUi") ?: false
                    try {
                        val intent = Intent(AlarmClock.ACTION_SET_TIMER).apply {
                            putExtra(AlarmClock.EXTRA_LENGTH, lengthSeconds)
                            putExtra(AlarmClock.EXTRA_MESSAGE, message)
                            putExtra(AlarmClock.EXTRA_SKIP_UI, skipUi)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                        result.success(mapOf("success" to true, "lengthSeconds" to lengthSeconds, "message" to message))
                    } catch (e: Exception) {
                        result.error("SET_TIMER_ERROR", e.message, null)
                    }
                }
                "sendKeyEvent" -> {
                    val keyName = call.argument<String>("key") ?: "back"
                    try {
                        val keyCode = when (keyName.lowercase()) {
                            "home" -> KeyEvent.KEYCODE_HOME
                            "back" -> KeyEvent.KEYCODE_BACK
                            "enter" -> KeyEvent.KEYCODE_ENTER
                            "volume_up" -> KeyEvent.KEYCODE_VOLUME_UP
                            "volume_down" -> KeyEvent.KEYCODE_VOLUME_DOWN
                            "power" -> KeyEvent.KEYCODE_POWER
                            "play_pause" -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                            else -> KeyEvent.KEYCODE_BACK
                        }
                        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                        if (keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE) {
                            audioManager?.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
                            audioManager?.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
                        } else {
                            Runtime.getRuntime().exec(arrayOf("input", "keyevent", keyCode.toString()))
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("KEYEVENT_ERROR", e.message, null)
                    }
                }
                "closeApp" -> {
                    val target = call.argument<String>("packageName") ?: call.argument<String>("name") ?: ""
                    try {
                        val actManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                        actManager?.killBackgroundProcesses(target)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CLOSE_APP_ERROR", e.message, null)
                    }
                }
                "readFile" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    try {
                        val file = java.io.File(filePath)
                        if (file.exists() && file.isFile) {
                            val content = file.readText(Charsets.UTF_8)
                            result.success(content)
                        } else {
                            result.error("FILE_NOT_FOUND", "File does not exist: $filePath", null)
                        }
                    } catch (e: Exception) {
                        result.error("READ_FILE_ERROR", e.message, null)
                    }
                }
                "writeFile" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    val content = call.argument<String>("content") ?: ""
                    val append = call.argument<Boolean>("append") ?: false
                    try {
                        val file = java.io.File(filePath)
                        file.parentFile?.mkdirs()
                        if (append) {
                            file.appendText(content, Charsets.UTF_8)
                        } else {
                            file.writeText(content, Charsets.UTF_8)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WRITE_FILE_ERROR", e.message, null)
                    }
                }
                "deleteFile" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    try {
                        val file = java.io.File(filePath)
                        val deleted = if (file.exists()) file.delete() else false
                        result.success(deleted)
                    } catch (e: Exception) {
                        result.error("DELETE_FILE_ERROR", e.message, null)
                    }
                }
                "listStorageLocations" -> {
                    try {
                        val ext = android.os.Environment.getExternalStorageDirectory()
                        val locations = mapOf(
                            "internal" to context.filesDir.absolutePath,
                            "external" to ext.absolutePath,
                            "downloads" to android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS).absolutePath,
                            "documents" to android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOCUMENTS).absolutePath,
                            "pictures" to android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_PICTURES).absolutePath,
                            "dcim" to android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DCIM).absolutePath,
                            "music" to android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_MUSIC).absolutePath
                        )
                        result.success(locations)
                    } catch (e: Exception) {
                        result.error("STORAGE_LOCATIONS_ERROR", e.message, null)
                    }
                }
                "openUri" -> {
                    val uriString = call.argument<String>("uri") ?: ""
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uriString)).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_URI_ERROR", e.message, null)
                    }
                }
                "sendIntent" -> {
                    val action = call.argument<String>("action") ?: Intent.ACTION_VIEW
                    val uri = call.argument<String>("uri")
                    try {
                        val intent = if (!uri.isNullOrEmpty()) {
                            Intent(action, Uri.parse(uri))
                        } else {
                            Intent(action)
                        }.apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SEND_INTENT_ERROR", e.message, null)
                    }
                }
                "shareText" -> {
                    val text = call.argument<String>("text") ?: ""
                    val subject = call.argument<String>("subject") ?: ""
                    try {
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                            if (subject.isNotEmpty()) putExtra(Intent.EXTRA_SUBJECT, subject)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(Intent.createChooser(intent, "Share").apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        })
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SHARE_ERROR", e.message, null)
                    }
                }
                "getLocation" -> {
                    try {
                        val locManager = context.getSystemService(Context.LOCATION_SERVICE) as? android.location.LocationManager
                        val providers = locManager?.getProviders(true) ?: emptyList()
                        var bestLoc: android.location.Location? = null
                        for (p in providers) {
                            try {
                                @Suppress("MissingPermission")
                                val l = locManager?.getLastKnownLocation(p)
                                if (l != null && (bestLoc == null || l.accuracy < bestLoc.accuracy)) {
                                    bestLoc = l
                                }
                            } catch (_: Exception) {}
                        }
                        if (bestLoc != null) {
                            result.success(mapOf(
                                "latitude" to bestLoc.latitude,
                                "longitude" to bestLoc.longitude,
                                "altitude" to bestLoc.altitude,
                                "accuracy" to bestLoc.accuracy
                            ))
                        } else {
                            result.success(mapOf("status" to "Location currently unavailable"))
                        }
                    } catch (e: Exception) {
                        result.error("LOCATION_ERROR", e.message, null)
                    }
                }
                "tap" -> {
                    val x = (call.argument<Number>("x") ?: 500).toFloat()
                    val y = (call.argument<Number>("y") ?: 500).toFloat()
                    val dispatched = RasAccessibilityService.tap(x, y) { success ->
                        // Callback completed
                    }
                    if (!dispatched) {
                        try {
                            Runtime.getRuntime().exec(arrayOf("input", "tap", x.toInt().toString(), y.toInt().toString()))
                        } catch (_: Exception) {}
                    }
                    result.success(true)
                }
                "doubleTap" -> {
                    val x = (call.argument<Number>("x") ?: 500).toFloat()
                    val y = (call.argument<Number>("y") ?: 500).toFloat()
                    RasAccessibilityService.doubleTap(x, y)
                    result.success(true)
                }
                "longPress" -> {
                    val x = (call.argument<Number>("x") ?: 500).toFloat()
                    val y = (call.argument<Number>("y") ?: 500).toFloat()
                    val duration = (call.argument<Number>("duration_ms") ?: 800).toLong()
                    RasAccessibilityService.longPress(x, y, duration)
                    result.success(true)
                }
                "swipe" -> {
                    val x1 = (call.argument<Number>("start_x") ?: 500).toFloat()
                    val y1 = (call.argument<Number>("start_y") ?: 800).toFloat()
                    val x2 = (call.argument<Number>("end_x") ?: 500).toFloat()
                    val y2 = (call.argument<Number>("end_y") ?: 200).toFloat()
                    val duration = (call.argument<Number>("duration_ms") ?: 300).toLong()
                    val dispatched = RasAccessibilityService.swipe(x1, y1, x2, y2, duration)
                    if (!dispatched) {
                        try {
                            Runtime.getRuntime().exec(arrayOf("input", "swipe", x1.toInt().toString(), y1.toInt().toString(), x2.toInt().toString(), y2.toInt().toString(), duration.toString()))
                        } catch (_: Exception) {}
                    }
                    result.success(true)
                }
                "scroll" -> {
                    val direction = call.argument<String>("direction") ?: "up"
                    RasAccessibilityService.scroll(direction)
                    result.success(true)
                }
                "typeText" -> {
                    val text = call.argument<String>("text") ?: ""
                    val success = RasAccessibilityService.typeText(text)
                    if (!success) {
                        try {
                            Runtime.getRuntime().exec(arrayOf("input", "text", text.replace(" ", "%s")))
                        } catch (_: Exception) {}
                    }
                    result.success(true)
                }
                "clearText" -> {
                    RasAccessibilityService.clearText()
                    result.success(true)
                }
                "getUiTree" -> {
                    val tree = RasAccessibilityService.getUiTree()
                    result.success(tree)
                }
                "listNotifications" -> {
                    val notifs = RasNotificationListenerService.getActiveNotifications()
                    result.success(notifs)
                }
                "dismissNotification" -> {
                    val key = call.argument<String>("key") ?: ""
                    val dismissed = RasNotificationListenerService.dismiss(key)
                    result.success(dismissed)
                }
                "listCameras" -> {
                    try {
                        val camManager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
                        val ids = camManager?.cameraIdList?.toList() ?: emptyList()
                        result.success(ids)
                    } catch (e: Exception) {
                        result.error("CAMERA_ERROR", e.message, null)
                    }
                }
                "takeScreenshot" -> {
                    val success = RasAccessibilityService.performGlobalAction(AccessibilityService.GLOBAL_ACTION_TAKE_SCREENSHOT)
                    result.success(mapOf("success" to success, "message" to "Triggered system screenshot capture"))
                }
                else -> result.notImplemented()
            }
        }
        currentMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        if (pendingWakeTrigger) {
            pendingWakeTrigger = false
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                notifyWakeWordTriggered()
            }, 600)
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.getBooleanExtra("triggered_by_wake_word", false)) {
            pendingWakeTrigger = true
        }
        handleCustomIntents(intent)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? android.app.KeyguardManager
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            keyguardManager?.requestDismissKeyguard(this, null)
        }
    }

    private fun handleCustomIntents(intent: Intent) {
        val testSuite = intent.getStringExtra("run_tests")
        if (!testSuite.isNullOrEmpty()) {
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                currentMethodChannel?.invokeMethod("runTests", testSuite)
            }, 800)
        }
        val testQuery = intent.getStringExtra("test_query")
        if (!testQuery.isNullOrEmpty()) {
            val isFromChat = intent.getBooleanExtra("is_from_chat", false)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                currentMethodChannel?.invokeMethod("onTestQuery", mapOf("query" to testQuery, "isFromChat" to isFromChat))
            }, 800)
        }
    }

    override fun onResume() {
        super.onResume()
        RasVoiceService.pauseMicrophone()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager
        nm?.cancel(RasVoiceService.WAKE_NOTIFICATION_ID)
    }

    override fun onPause() {
        super.onPause()
        try {
            ttsAudioTrack?.run {
                stop()
                release()
            }
            ttsAudioTrack = null
        } catch (_: Exception) {}
        RasVoiceService.resumeMicrophone()
    }

    override fun onDestroy() {
        try {
            ttsAudioTrack?.run {
                stop()
                release()
            }
            ttsAudioTrack = null
        } catch (_: Exception) {}
        currentMethodChannel = null
        RasVoiceService.resumeMicrophone()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager
        nm?.cancel(RasVoiceService.WAKE_NOTIFICATION_ID)
        val km = getSystemService(Context.KEYGUARD_SERVICE) as? android.app.KeyguardManager
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            km?.requestDismissKeyguard(this, null)
        }
        if (intent.getBooleanExtra("triggered_by_wake_word", false)) {
            notifyWakeWordTriggered()
        }
        handleCustomIntents(intent)
    }

    private fun levenshtein(s1: String, s2: String): Int {
        val dp = Array(s1.length + 1) { IntArray(s2.length + 1) }
        for (i in 0..s1.length) dp[i][0] = i
        for (j in 0..s2.length) dp[0][j] = j
        for (i in 1..s1.length) {
            for (j in 1..s2.length) {
                val cost = if (s1[i - 1] == s2[j - 1]) 0 else 1
                dp[i][j] = minOf(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost)
            }
        }
        return dp[s1.length][s2.length]
    }

    private fun showHeadsUpNotification(title: String, message: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val channelId = "assistant_response_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Assistant Answers",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Shows answers generated by assistant"
                enableVibration(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(channel)
        }

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            101,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(Notification.DEFAULT_ALL)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        nm.notify(2001, notification)
    }

    companion object {
        var currentMethodChannel: MethodChannel? = null

        fun notifyWakeWordTriggered() {
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                currentMethodChannel?.invokeMethod("onWakeWordTriggered", null)
            }
        }
    }
}
