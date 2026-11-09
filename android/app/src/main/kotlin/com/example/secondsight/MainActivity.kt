package com.example.secondsight

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.view.KeyEvent
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
    private var voiceChannel: MethodChannel? = null
    private var accessibilityBridge: AccessibilityBridge? = null
    private var visible = false
    private var voiceStarting = false
    private var permissionReply: MethodChannel.Result? = null
    private var permissionResumeReply: MethodChannel.Result? = null
    private var voiceBlocked = true
    private var voiceAllowBackground = false
    private var voiceInterrupted = false

    private fun startNavigationVoice(result: MethodChannel.Result) {
        try {
            val intent = Intent(this, NavigationVoiceService::class.java)
                .putExtra("blocked", voiceBlocked)
                .putExtra("allowBackground", voiceAllowBackground)
            voiceStarting = true
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
            result.success(true)
            main.postDelayed({ voiceStarting = false }, 1000)
        } catch (_: Exception) {
            voiceStarting = false
            result.error("voice_service", "Mở app để bật mic nền trước khi khóa màn hình.", null)
        }
    }

    private fun configureNavigationVoice(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        voiceBlocked = call.argument<Boolean>("blocked") ?: true
        voiceAllowBackground = call.argument<Boolean>("allowBackground") ?: false
        voiceInterrupted = call.argument<Boolean>("interrupt") ?: false
        if (call.argument<Boolean>("enabled") != true) {
            stopService(Intent(this, NavigationVoiceService::class.java))
            permissionReply?.success(false)
            permissionReply = null
            permissionResumeReply?.success(false)
            permissionResumeReply = null
            result.success(false)
            return
        }
        val service = NavigationVoiceService.instance
        if (service != null) {
            service.update(voiceBlocked, voiceInterrupted, voiceAllowBackground)
            result.success(true)
            return
        }
        if (voiceStarting || permissionReply != null || permissionResumeReply != null) { result.success(false); return }
        if (!visible) {
            result.error("voice_background_start", "Mở app để bật mic nền, rồi khóa màn hình.", null)
            return
        }
        val permissions = mutableListOf<String>()
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED)
            permissions.add(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        if (permissions.isNotEmpty()) {
            permissionReply = result
            requestPermissions(permissions.toTypedArray(), 4201)
        } else startNavigationVoice(result)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 4201) return
        val reply = permissionReply ?: return
        permissionReply = null
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            reply.error("voice_permission", "Chưa có quyền micro. Aurelia không nghe khi khóa màn hình.", null)
        } else if (visible) startNavigationVoice(reply)
        else permissionResumeReply = reply
    }

    override fun onResume() {
        super.onResume()
        visible = true
        accessibilityBridge?.publish()
        NavigationVoiceService.background = false
        NavigationVoiceService.instance?.refresh()
        permissionResumeReply?.let {
            permissionResumeReply = null
            startNavigationVoice(it)
        }
    }

    override fun onPause() {
        visible = false
        NavigationVoiceService.background = true
        NavigationVoiceService.instance?.refresh()
        super.onPause()
    }


    private fun emit(id: Int, type: String, text: String? = null) {
        main.post { if (socketId == id) events?.success(mapOf("id" to id, "type" to type, "text" to text)) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        accessibilityBridge?.dispose()
        accessibilityBridge = AccessibilityBridge(this, messenger)
        voiceChannel = MethodChannel(messenger, "secondsight/voice")
        NavigationVoiceService.emit = { method, value -> main.post { voiceChannel?.invokeMethod(method, value) } }
        voiceChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "configureNavigation" -> configureNavigationVoice(call, result)
                "activateCommand" -> { NavigationVoiceService.instance?.activateCommand(); result.success(null) }
                "commandReady" -> {
                    call.argument<Int>("ticket")?.let { NavigationVoiceService.instance?.commandReady(it) }
                    result.success(null)
                }
                "commandFinished" -> { NavigationVoiceService.instance?.commandFinished(); result.success(null) }
                else -> result.notImplemented()
            }
        }
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

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode in setOf(KeyEvent.KEYCODE_HEADSETHOOK,
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_VOICE_ASSIST)) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                voiceChannel?.invokeMethod("activate", null)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onDestroy() {
        accessibilityBridge?.dispose()
        accessibilityBridge = null
        stopService(Intent(this, NavigationVoiceService::class.java))
        permissionReply?.success(false)
        permissionReply = null
        permissionResumeReply?.success(false)
        permissionResumeReply = null
        NavigationVoiceService.emit = null
        voiceChannel = null
        socket?.cancel()
        events = null
        client.dispatcher.executorService.shutdown()
        super.onDestroy()
    }
}
