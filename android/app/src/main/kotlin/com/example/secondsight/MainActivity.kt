package com.example.secondsight

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import okhttp3.*
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val client = OkHttpClient.Builder()
        .connectTimeout(7, TimeUnit.SECONDS).readTimeout(0, TimeUnit.SECONDS).build()
    private val main = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private var socket: WebSocket? = null
    private var socketId: Int? = null

    private fun emit(id: Int, type: String, text: String? = null) {
        main.post { if (socketId == id) events?.success(mapOf("id" to id, "type" to type, "text" to text)) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        EventChannel(messenger, "secondsight/okhttp/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { events = sink }
            override fun onCancel(arguments: Any?) { events = null }
        })
        MethodChannel(messenger, "secondsight/okhttp").setMethodCallHandler { call, result ->
            val id = call.argument<Int>("id")
            when (call.method) {
                "connect" -> {
                    val url = call.argument<String>("url")
                    val token = call.argument<String>("token")
                    if (id == null || url == null || token.isNullOrBlank()) {
                        result.error("invalid", "Thiếu thông tin kết nối", null)
                    } else {
                        try {
                            val request = Request.Builder().url(url)
                                .header("Authorization", "Bearer $token").build()
                            socket?.cancel()
                            socketId = id
                            socket = client.newWebSocket(request, object : WebSocketListener() {
                                override fun onOpen(ws: WebSocket, response: Response) { emit(id, "open") }
                                override fun onMessage(ws: WebSocket, text: String) {
                                    if (text.length <= 262144) emit(id, "message", text)
                                }
                                override fun onClosing(ws: WebSocket, code: Int, reason: String) { ws.close(code, null) }
                                override fun onClosed(ws: WebSocket, code: Int, reason: String) { emit(id, "closed") }
                                override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) { emit(id, "failure") }
                            })
                            result.success(null)
                        } catch (_: Exception) { result.error("connect", "Không mở được kết nối", null) }
                    }
                }
                "send" -> result.success(id == socketId && (call.argument<String>("text")?.let { socket?.send(it) } == true))
                "close" -> {
                    if (id == socketId) { socket?.cancel(); socket = null; socketId = null }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        socket?.cancel()
        events = null
        client.dispatcher.executorService.shutdown()
        super.onDestroy()
    }
}
