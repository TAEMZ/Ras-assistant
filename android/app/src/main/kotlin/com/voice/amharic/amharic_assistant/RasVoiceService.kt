package com.voice.amharic.amharic_assistant

import android.app.*
import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlin.math.sqrt

class RasVoiceService : Service() {
    companion object {
        const val CHANNEL_ID = "ras_voice_service_channel"
        const val WAKE_ALERT_CHANNEL_ID = "ras_wake_alert_channel"
        const val NOTIFICATION_ID = 1001
        const val WAKE_NOTIFICATION_ID = 1002
        const val TAG = "RasVoiceService"
        var isRunning = false
        @Volatile
        var isForegroundActive = false
        var instance: RasVoiceService? = null

        fun pauseMicrophone() {
            isForegroundActive = true
            instance?.stopListeningLoop()
        }

        fun resumeMicrophone() {
            isForegroundActive = false
            instance?.startListeningLoop()
        }

        fun triggerWake() {
            instance?.triggerWakeWordActivation()
        }
    }

    private var audioRecord: AudioRecord? = null
    private var isRecording = false
    private var workerThread: Thread? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
            "Ras:VoiceWakeLock"
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildForegroundNotification()
        startForeground(NOTIFICATION_ID, notification)
        isRunning = true
        if (!isForegroundActive) {
            startListeningLoop()
        }
        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            val persistentChannel = NotificationChannel(
                CHANNEL_ID,
                "Ras Background Voice Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Monitors for wake phrase (ሰላም ራስ / Hey Ras)"
                setShowBadge(false)
            }
            manager.createNotificationChannel(persistentChannel)

            val wakeAlertChannel = NotificationChannel(
                WAKE_ALERT_CHANNEL_ID,
                "Ras Wake Word Activation",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Full-screen assistant activation when wake phrase is detected"
                setShowBadge(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(wakeAlertChannel)
        }
    }

    private fun buildForegroundNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Ras Voice Assistant")
            .setContentText("Listening for 'ሰላም ራስ' / 'Hey Ras'")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    fun stopListeningLoop() {
        if (!isRecording) return
        isRecording = false
        try {
            audioRecord?.stop()
            audioRecord?.release()
            audioRecord = null
        } catch (ignored: Exception) {}
        try {
            workerThread?.interrupt()
            workerThread = null
        } catch (ignored: Exception) {}
        Log.i(TAG, "Ras background microphone monitor paused for foreground activity")
    }

    fun startListeningLoop() {
        if (isRecording || isForegroundActive) return
        isRecording = true

        workerThread = Thread {
            val sampleRate = 16000
            val channelConfig = AudioFormat.CHANNEL_IN_MONO
            val audioFormat = AudioFormat.ENCODING_PCM_16BIT
            val minBufSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
            val bufferSize = maxOf(minBufSize, 3200)

            try {
                audioRecord = AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    sampleRate,
                    channelConfig,
                    audioFormat,
                    bufferSize
                )

                if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                    Log.e(TAG, "AudioRecord failed to initialize")
                    isRecording = false
                    return@Thread
                }

                audioRecord?.startRecording()
                Log.i(TAG, "Ras background microphone monitor started")

                val audioBuffer = ShortArray(1600) // 100ms chunk at 16kHz
                var consecutiveSpeechChunks = 0
                var consecutiveSilenceChunks = 0
                val speechBuffer = mutableListOf<Short>()

                while (isRecording && !isForegroundActive) {
                    val readSamples = audioRecord?.read(audioBuffer, 0, audioBuffer.size) ?: 0
                    if (readSamples > 0) {
                        var sumSq = 0.0
                        for (i in 0 until readSamples) {
                            sumSq += audioBuffer[i] * audioBuffer[i]
                        }
                        val rms = sqrt(sumSq / readSamples)

                        if (rms > 1200.0) { // Deliberate speech energy gate (~ -28 dBFS), ignores ambient room noise
                            consecutiveSpeechChunks++
                            consecutiveSilenceChunks = 0
                            for (i in 0 until readSamples) {
                                speechBuffer.add(audioBuffer[i])
                            }
                            if (consecutiveSpeechChunks > 30) { // Max 3.0 seconds
                                speechBuffer.clear()
                                consecutiveSpeechChunks = 0
                                consecutiveSilenceChunks = 0
                            }
                        } else {
                            if (consecutiveSpeechChunks > 0) {
                                consecutiveSilenceChunks++
                                for (i in 0 until readSamples) {
                                    speechBuffer.add(audioBuffer[i])
                                }
                                // 4 consecutive silence chunks = 400ms trailing pause
                                if (consecutiveSilenceChunks >= 4) {
                                    if (consecutiveSpeechChunks in 3..25 && speechBuffer.isNotEmpty()) {
                                        Log.i(TAG, "Speech candidate ($consecutiveSpeechChunks speech chunks, ${speechBuffer.size} samples). Verifying...")
                                        sendCandidateToFlutter(speechBuffer)
                                    }
                                    speechBuffer.clear()
                                    consecutiveSpeechChunks = 0
                                    consecutiveSilenceChunks = 0
                                    Thread.sleep(1500)
                                }
                            } else {
                                speechBuffer.clear()
                                consecutiveSpeechChunks = 0
                                consecutiveSilenceChunks = 0
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Background audio error: ${e.message}")
            } finally {
                try {
                    audioRecord?.stop()
                    audioRecord?.release()
                    audioRecord = null
                } catch (ignored: Exception) {}
                isRecording = false
            }
        }.apply {
            priority = Thread.NORM_PRIORITY
            start()
        }
    }

    private fun sendCandidateToFlutter(speechSamples: MutableList<Short>) {
        val byteBuffer = java.nio.ByteBuffer.allocate(speechSamples.size * 2)
            .order(java.nio.ByteOrder.LITTLE_ENDIAN)
        for (s in speechSamples) {
            byteBuffer.putShort(s)
        }
        val pcmBytes = byteBuffer.array()

        android.os.Handler(android.os.Looper.getMainLooper()).post {
            val channel = MainActivity.currentMethodChannel
            if (channel == null) {
                Log.i(TAG, "Flutter channel unavailable (app closed). Speech candidate detected (${speechSamples.size} samples) — triggering wake activation!")
                triggerWakeWordActivation()
                return@post
            }
            try {
                channel.invokeMethod("onWakeWordCandidate", pcmBytes)
                Log.i(TAG, "Sent ${pcmBytes.size} bytes to Flutter for ASR verification")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send candidate to Flutter: ${e.message}")
            }
        }
    }

    fun triggerWakeWordActivation() {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            try {
                wakeLock?.acquire(3500) // Keep screen on for 3.5s
            } catch (ignored: Exception) {}

            // Immediate Audio Chime Feedback
            try {
                val toneGen = android.media.ToneGenerator(android.media.AudioManager.STREAM_NOTIFICATION, 90)
                toneGen.startTone(android.media.ToneGenerator.TONE_PROP_ACK, 220)
            } catch (ignored: Exception) {}

            // Immediate Double-Pulse Haptic Vibration Feedback
            try {
                val vibrator = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                    val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager
                    manager.defaultVibrator
                } else {
                    @Suppress("DEPRECATION")
                    getSystemService(Context.VIBRATOR_SERVICE) as android.os.Vibrator
                }

                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    val effect = android.os.VibrationEffect.createWaveform(
                        longArrayOf(0, 90, 80, 140),
                        -1
                    )
                    vibrator.vibrate(effect)
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(longArrayOf(0, 90, 80, 140), -1)
                }
            } catch (ignored: Exception) {}

            try {
                val launchIntent = Intent(this@RasVoiceService, MainActivity::class.java).apply {
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                    )
                    putExtra("triggered_by_wake_word", true)
                }

                val pendingIntent = PendingIntent.getActivity(
                    this@RasVoiceService,
                    WAKE_NOTIFICATION_ID,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                val wakeNotification = NotificationCompat.Builder(this@RasVoiceService, WAKE_ALERT_CHANNEL_ID)
                    .setContentTitle("ሰላም ራስ")
                    .setContentText("Listening for your command...")
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setPriority(NotificationCompat.PRIORITY_MAX)
                    .setCategory(NotificationCompat.CATEGORY_CALL)
                    .setFullScreenIntent(pendingIntent, true)
                    .setContentIntent(pendingIntent)
                    .setAutoCancel(true)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .build()

                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.notify(WAKE_NOTIFICATION_ID, wakeNotification)

                try {
                    startActivity(launchIntent)
                } catch (ignored: Exception) {}

                MainActivity.notifyWakeWordTriggered()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to launch activity: ${e.message}")
            }
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "App task removed (swiped away from recents). Keeping background voice service active.")
        try {
            val restartIntent = Intent(applicationContext, RasVoiceService::class.java).also {
                it.setPackage(packageName)
            }
            val pendingIntent = PendingIntent.getService(
                applicationContext,
                1003,
                restartIntent,
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
            )
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            alarmManager?.set(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                android.os.SystemClock.elapsedRealtime() + 1000,
                pendingIntent
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to schedule service revival on task removal: ${e.message}")
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        stopListeningLoop()
        isRunning = false
        if (instance == this) instance = null
        try {
            wakeLock?.release()
        } catch (ignored: Exception) {}
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
