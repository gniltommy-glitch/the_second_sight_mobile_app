package com.example.secondsight

import android.Manifest
import android.app.*
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.*
import android.speech.*
import java.text.Normalizer

/** Owns the background mic only during a user-started navigation session.
 * Started while the Activity is visible, before microphone while-in-use
 * access expires. No sticky restart, boot receiver, or saved audio. */
class NavigationVoiceService : Service() {
    companion object {
        var instance: NavigationVoiceService? = null
            private set
        var emit: ((String, Any?) -> Unit)? = null
        var background = false
        const val CHANNEL = "aurelia_navigation_voice"
        const val NOTIFICATION = 4201
    }
    private val handler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var generation = 0
    private var blocked = true
    private var allowBackground = false
    private lateinit var quietWake: QuietWakeEngine
    private var destroyed = false
    private var failures = 0
    private var phase = "wake"
    private var commandDeadline = 0L
    private var session = 0
    private var cpuLock: PowerManager.WakeLock? = null
    private val renewCpu = object : Runnable {
        override fun run() {
            if (destroyed) return
            cpuLock?.acquire(30 * 60 * 1000L)
            handler.postDelayed(this, 25 * 60 * 1000L)
        }
    }
    private val retry = Runnable { listen() }
    private val watchdog = Runnable { reset(); schedule(1000) }

    override fun onBind(intent: Intent?) = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        quietWake = QuietWakeEngine(this, { activateCommand() }, { fail(it) })
        cpuLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "secondsight:navigationVoice")
            .apply { setReferenceCounted(false) }
        renewCpu.run()
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL,
                "Aurelia trong hành trình", NotificationManager.IMPORTANCE_LOW))
        }
        val open = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1,
            Intent(this, NavigationVoiceService::class.java).setAction("mute"),
            PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
            else Notification.Builder(this)
        val notification = builder.setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Aurelia đang chờ câu gọi")
            .setContentText("Khi khóa màn hình: nói Hey Aurelia, rồi nói lệnh.")
            .setContentIntent(open).setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Tắt gọi Aurelia", stop).build()).build()
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else startForeground(NOTIFICATION, notification)
        } catch (_: Exception) {
            fail("Không bật được mic nền. Mở app và cấp quyền micro trước khi bắt đầu.")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "mute") {
            emit?.invoke("backgroundMuted", null)
            stopSelf()
        } else {
            blocked = intent?.getBooleanExtra("blocked", true) ?: true
            allowBackground = intent?.getBooleanExtra("allowBackground", false) ?: false
            refresh()
        }
        return START_NOT_STICKY
    }

    fun update(isBlocked: Boolean, interrupt: Boolean = false, inNavigation: Boolean = false) {
        allowBackground = inNavigation
        if (interrupt) reset()
        if (blocked != isBlocked) {
            blocked = isBlocked
            if (blocked && (interrupt || phase !in setOf("prompt", "processing"))) reset()
        }
        refresh()
    }

    fun refresh() {
        if (background && !allowBackground) reset()
        else if (blocked) {
            if (phase !in setOf("prompt", "processing")) reset()
        } else if (phase == "wake") {
            quietWake.start()
        } else if (!background && phase == "command") {
            reset()
            quietWake.start()
        }
    }

    fun activateCommand() {
        if (!allowed()) return
        reset()
        phase = "prompt"
        emit?.invoke("backgroundWake", session)
        handler.postDelayed(watchdog, 25000)
    }

    fun commandReady(ticket: Int) {
        if (ticket != session || phase != "prompt" || blocked || !background) return
        phase = "command"
        commandDeadline = SystemClock.elapsedRealtime() + 12000
        emit?.invoke("backgroundListening", true)
        schedule(400)
    }

    private fun allowed() = !destroyed && (!background || allowBackground) && !blocked
    private fun schedule(delay: Long) {
        if (!allowed() || recognizer != null || phase == "prompt" || phase == "processing") return
        if (phase == "wake") { quietWake.start(); return }
        if (!background) return
        handler.removeCallbacks(retry)
        handler.postDelayed(retry, delay)
    }

    private fun release() {
        generation++
        quietWake.stop()
        handler.removeCallbacks(watchdog)
        val old = recognizer
        recognizer = null
        runCatching { old?.cancel() }
        runCatching { old?.destroy() }
    }

    private fun reset() {
        handler.removeCallbacks(retry)
        release()
        phase = "wake"
        session++
        emit?.invoke("backgroundListening", false)
    }

    private fun fail(message: String) {
        emit?.invoke("backgroundError", message)
        stopSelf()
    }

    private val wakePattern = Regex("^(?:(?:hey|hay|hei) (?:aurelia|aurealia|auralia|au re lia|o re lia)|(?:aurelia|aurealia|auralia|au re lia|o re lia) oi)( |$)")

    private fun fold(text: String) = Normalizer.normalize(text.lowercase(), Normalizer.Form.NFD)
        .replace(Regex("\\p{M}+"), "").replace('đ', 'd')
        .replace(Regex("[.,!?;:]"), " ").trim().replace(Regex("\\s+"), " ")

    private fun listen() {
        if (!allowed() || recognizer != null) return
        if (phase == "wake") { quietWake.start(); return }
        if (!background) return
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            fail("Quyền micro đã bị tắt. Mic nền ngừng hoạt động.")
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            fail("Điện thoại chưa có dịch vụ nhận dạng giọng nói cho Aurelia.")
            return
        }
        if (phase == "command" && SystemClock.elapsedRealtime() > commandDeadline) reset()
        val token = ++generation
        try {
            val engine = SpeechRecognizer.createSpeechRecognizer(this)
            recognizer = engine
            var lastCommandText = ""
            engine.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onPartialResults(results: Bundle?) {
                    if (phase == "command") {
                        val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
                        if (text.isNotBlank()) lastCommandText = text
                    } else if (phase == "wake") {
                        val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
                        val folded = fold(text)
                        val wake = wakePattern.find(folded)
                        if (wake != null && folded.substring(wake.range.last + 1).isBlank()) onResults(results)
                    }
                }
                override fun onEvent(eventType: Int, params: Bundle?) {}
                override fun onError(error: Int) {
                    if (token != generation || !allowed()) return
                    if (phase == "command" && lastCommandText.isNotBlank() &&
                        (error == SpeechRecognizer.ERROR_NO_MATCH || error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT)) {
                        onResults(Bundle().apply {
                            putStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION, arrayListOf(lastCommandText))
                        })
                        return
                    }
                    release()
                    when (error) {
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> {
                            fail("Không có quyền micro. Mở app để cấp quyền rồi thử lại.")
                            return
                        }
                        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
                        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> {
                            fail("Dịch vụ nhận dạng chưa hỗ trợ tiếng Việt. Kiểm tra cài đặt giọng nói.")
                            return
                        }
                        SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> failures = 0
                        else -> failures++
                    }
                    if (failures >= 5) {
                        fail("Mic nền không nhận dạng được. Kiểm tra mạng và dịch vụ giọng nói, rồi mở lại app.")
                        return
                    }
                    // One command attempt only. Silence returns to quiet wake
                    // monitoring and never reopens the command mic.
                    if (phase == "command") reset()
                    schedule(if (failures == 0) 700 else (failures * 1500).toLong())
                }
                override fun onResults(results: Bundle?) {
                    if (token != generation || !allowed()) return
                    val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
                    val wasCommand = phase == "command"
                    release()
                    failures = 0
                    if (wasCommand) {
                        emit?.invoke("backgroundListening", false)
                        phase = "processing"
                        emit?.invoke("backgroundCommand", text)
                        // A bounded wait also handles a detached/stalled Dart engine.
                        handler.postDelayed(watchdog, 25000)
                        return
                    }
                    val folded = fold(text)
                    val wake = wakePattern.find(folded)
                    if (wake == null) { schedule(700); return }
                    val command = folded.substring(wake.range.last + 1).trim()
                    session++
                    if (command.isNotEmpty()) {
                        phase = "processing"
                        emit?.invoke("backgroundCommand", command)
                        handler.postDelayed(watchdog, 25000)
                    } else {
                        phase = "prompt"
                        emit?.invoke("backgroundWake", session)
                        handler.postDelayed(watchdog, 25000)
                    }
                }
            })
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE, "vi-VN")
                .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            engine.startListening(intent)
            handler.postDelayed(watchdog,
                if (phase == "command") maxOf(1L, commandDeadline - SystemClock.elapsedRealtime()) else 25000L)
        } catch (_: Exception) {
            release()
            fail("Không mở được mic nền. Mở app và kiểm tra quyền micro.")
        }
    }

    fun commandFinished() { reset(); schedule(700) }
    override fun onTaskRemoved(rootIntent: Intent?) { stopSelf() }
    override fun onDestroy() {
        destroyed = true
        handler.removeCallbacksAndMessages(null)
        if (cpuLock?.isHeld == true) cpuLock?.release()
        cpuLock = null
        release()
        quietWake.close()
        instance = null
        emit?.invoke("backgroundListening", false)
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else stopForeground(true)
        super.onDestroy()
    }
}
