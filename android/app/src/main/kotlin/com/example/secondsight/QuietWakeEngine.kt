package com.example.secondsight

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService
import java.io.File

/** Continuous local keyword listening. Never starts Android SpeechRecognizer,
 * changes system volume, or saves microphone audio. */
class QuietWakeEngine(
    private val context: Context,
    private val onWake: () -> Unit,
    private val onFailure: (String) -> Unit,
) {
    companion object { private val modelLoadLock = Any() }
    private val main = Handler(Looper.getMainLooper())
    private var model: Model? = null
    private var stream: SpeechService? = null
    private var decoder: Recognizer? = null
    private var enabled = false
    private var loading = false
    private var closed = false
    private var generation = 0

    fun start() {
        if (closed) return
        enabled = true
        if (stream != null || loading) return
        if (model == null) {
            loading = true
            Thread({
                try {
                    // Service restarts during permission/lifecycle changes
                    // must not copy/delete the same model directory together.
                    val loaded = synchronized(modelLoadLock) {
                        val folder = File(context.filesDir, "wake-en-0.15")
                        val ready = File(folder, ".ready")
                        if (!ready.exists()) {
                            folder.deleteRecursively()
                            copyAssets("wake-en", folder)
                            ready.writeText("0.15")
                        }
                        Model(folder.absolutePath)
                    }
                    main.post {
                        loading = false
                        if (closed) loaded.close() else {
                            model = loaded
                            if (enabled) start()
                        }
                    }
                } catch (_: Exception) {
                    main.post {
                        loading = false
                        if (!closed) onFailure("Không tải được bộ chờ câu gọi cục bộ. Hãy dùng nút mic.")
                    }
                }
            }, "Aurelia-model").start()
            return
        }
        val token = ++generation
        try {
            val recognizer = Recognizer(model, 16000f,
                JSONArray(listOf("hey aurelia", "[unk]")).toString())
            decoder = recognizer
            recognizer.setWords(true)
            val service = SpeechService(recognizer, 16000f)
            stream = service
            val started = service.startListening(object : RecognitionListener {
                override fun onPartialResult(hypothesis: String?) {}
                override fun onResult(hypothesis: String?) { detect(hypothesis, token) }
                override fun onFinalResult(hypothesis: String?) { detect(hypothesis, token) }
                override fun onError(exception: Exception?) {
                    if (token != generation || !enabled || closed) return
                    stop()
                    onFailure("Bộ chờ câu gọi bị gián đoạn. Hãy dùng nút mic và kiểm tra quyền micro.")
                }
                override fun onTimeout() {
                    // No timeout is supplied: never renew a periodic session.
                }
            })
            if (!started) throw IllegalStateException("wake audio not started")
        } catch (_: Exception) {
            stop()
            onFailure("Không mở được mic chờ câu gọi. Hãy dùng nút mic.")
        }
    }

    private fun detect(hypothesis: String?, token: Int) {
        if (token != generation || !enabled || closed) return
        val result = runCatching { JSONObject(hypothesis.orEmpty()) }.getOrNull() ?: return
        if (result.optString("text").trim() != "hey aurelia") return
        val words = result.optJSONArray("result") ?: return
        if (words.length() != 2) return
        for (i in 0 until words.length()) {
            if (words.getJSONObject(i).optDouble("conf", 0.0) < 0.75) return
        }
        stop()
        onWake()
    }

    fun stop() {
        enabled = false
        generation++
        val old = stream
        stream = null
        runCatching { old?.cancel() }
        runCatching { old?.shutdown() }
        runCatching { decoder?.close() }
        decoder = null
    }

    fun close() {
        closed = true
        stop()
        runCatching { model?.close() }
        model = null
    }

    private fun copyAssets(path: String, target: File) {
        val children = context.assets.list(path).orEmpty()
        if (children.isEmpty()) {
            target.parentFile?.mkdirs()
            context.assets.open(path).use { input -> target.outputStream().use { input.copyTo(it) } }
        } else {
            target.mkdirs()
            children.forEach { copyAssets("$path/$it", File(target, it)) }
        }
    }
}
