package com.nowchat

import android.content.ContentValues
import android.os.Build
import android.util.Log
import android.provider.MediaStore
import com.chaquo.python.PyObject
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity
import android.os.Handler
import android.os.Looper
import java.io.File
import java.util.Locale
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val channelName = "nowchat/python_bridge"
    private val logChannelName = "nowchat/python_bridge/log_stream"
    private val mediaChannelName = "nowchat/media_bridge"
    private val methodExecute = "executePython"
    private val methodIsReady = "isPythonReady"
    private val methodSaveImageToGallery = "saveImageToGallery"
    private val loadedNativeLibs = mutableSetOf<String>()
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile
    private var logEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, logChannelName)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(
                        arguments: Any?,
                        events: EventChannel.EventSink?,
                    ) {
                        logEventSink = events
                    }

                    override fun onCancel(arguments: Any?) {
                        logEventSink = null
                    }
                },
            )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    methodIsReady -> {
                        runCatching { ensurePythonStarted() }
                            .onSuccess { result.success(true) }
                            .onFailure { result.success(false) }
                    }

                    methodExecute -> executePython(call, result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    methodSaveImageToGallery -> saveImageToGallery(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun executePython(call: MethodCall, result: MethodChannel.Result) {
        val code = call.argument<String>("code")?.trim().orEmpty()
        val timeoutMs = call.argument<Int>("timeoutMs") ?: 20_000
        val workingDirectory = call.argument<String>("workingDirectory")?.trim().orEmpty()
        val runId = call.argument<String>("runId")?.trim().orEmpty().ifEmpty {
            UUID.randomUUID().toString()
        }
        val rawPaths = call.argument<List<String>>("extraSysPaths") ?: emptyList()
        val extraSysPaths = rawPaths.map { it.trim() }.filter { it.isNotEmpty() }

        if (code.isEmpty()) {
            result.error("empty_code", "代码不能为空", null)
            return
        }

        Thread {
            runCatching {
                preloadNativeLibraries(extraSysPaths)
                ensurePythonStarted()
                val py = Python.getInstance()
                val module = py.getModule("runner")
                val emitter = PythonLogEmitter(runId)
                val pyResult = module.callAttr(
                    "execute_code",
                    code,
                    timeoutMs,
                    extraSysPaths,
                    workingDirectory,
                    runId,
                    emitter,
                )
                val map = pyResultToMap(pyResult)
                runOnUiThread { result.success(map) }
            }.onFailure { error ->
                runOnUiThread {
                    result.error(
                        "python_exec_failed",
                        error.message ?: "Python 执行失败",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun saveImageToGallery(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val mimeType = call.argument<String>("mimeType")?.trim().orEmpty().ifEmpty { "image/png" }
        val rawFileName = call.argument<String>("fileName")?.trim().orEmpty()
        val fallbackExt = when (mimeType.lowercase(Locale.ROOT)) {
            "image/jpeg" -> "jpg"
            "image/webp" -> "webp"
            else -> "png"
        }
        val fileName = rawFileName.ifEmpty {
            "nowchat_${System.currentTimeMillis()}.$fallbackExt"
        }

        if (bytes == null || bytes.isEmpty()) {
            result.error("invalid_args", "图片字节为空", null)
            return
        }

        Thread {
            runCatching {
                val resolver = applicationContext.contentResolver
                val collection =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    } else {
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                    }
                val values =
                    ContentValues().apply {
                        put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                        put(MediaStore.Images.Media.MIME_TYPE, mimeType)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/NowChat")
                            put(MediaStore.Images.Media.IS_PENDING, 1)
                        }
                    }
                val itemUri = resolver.insert(collection, values)
                    ?: throw IllegalStateException("创建相册媒体记录失败")
                resolver.openOutputStream(itemUri)?.use { output ->
                    output.write(bytes)
                    output.flush()
                } ?: throw IllegalStateException("打开相册输出流失败")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val completed = ContentValues().apply {
                        put(MediaStore.Images.Media.IS_PENDING, 0)
                    }
                    resolver.update(itemUri, completed, null, null)
                }
                itemUri.toString()
            }.onSuccess { uri ->
                runOnUiThread {
                    result.success(
                        mapOf(
                            "ok" to true,
                            "uri" to uri,
                        ),
                    )
                }
            }.onFailure { error ->
                runOnUiThread {
                    result.error(
                        "save_image_failed",
                        error.message ?: "保存到相册失败",
                        null,
                    )
                }
            }
        }.start()
    }

    private inner class PythonLogEmitter(
        private val runId: String,
    ) {
        fun emit(stream: String, text: String) {
            emitPythonLog(runId = runId, stream = stream, text = text)
        }
    }

    private fun emitPythonLog(
        runId: String,
        stream: String,
        text: String,
    ) {
        if (text.isBlank()) return
        val normalizedStream = stream.trim().lowercase(Locale.ROOT)
        val trimmed = text.trimEnd()
        val tag = "NowChatPython"
        val message = "[PyRT][$runId][$normalizedStream] $trimmed"
        if (normalizedStream == "stderr") {
            Log.w(tag, message)
        } else {
            Log.i(tag, message)
        }

        val sink = logEventSink ?: return
        val payload = mapOf(
            "runId" to runId,
            "stream" to normalizedStream,
            "line" to trimmed,
            "timestampMs" to System.currentTimeMillis(),
        )
        mainHandler.post {
            runCatching { sink.success(payload) }
        }
    }

    private fun ensurePythonStarted() {
        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }
    }

    private fun preloadNativeLibraries(extraSysPaths: List<String>) {
        val candidates = collectNativeLibraries(extraSysPaths)
        for (path in candidates) {
            val alreadyLoaded = synchronized(loadedNativeLibs) {
                loadedNativeLibs.contains(path)
            }
            if (alreadyLoaded) continue
            runCatching {
                System.load(path)
                synchronized(loadedNativeLibs) {
                    loadedNativeLibs.add(path)
                }
                Log.i("NowChatPython", "Loaded native lib: $path")
            }.onFailure { error ->
                Log.w("NowChatPython", "Skip native lib load: $path, reason=${error.message}")
            }
        }
    }

    private fun collectNativeLibraries(extraSysPaths: List<String>): List<String> {
        val result = mutableListOf<String>()
        for (basePath in extraSysPaths) {
            val base = File(basePath)
            if (!base.exists()) continue
            if (base.isFile) {
                if (base.name.contains(".so")) {
                    result.add(base.absolutePath)
                }
                continue
            }
            for (file in base.walkTopDown()) {
                if (file.isFile && file.name.contains(".so")) {
                    result.add(file.absolutePath)
                }
            }
        }
        result.sortWith(
            compareBy<String> { nativeLibPriority(it) }.thenBy { it.lowercase(Locale.ROOT) },
        )
        return result
    }

    private fun nativeLibPriority(path: String): Int {
        val name = File(path).name.lowercase(Locale.ROOT)
        return when {
            name.contains("openblas") -> 0
            name.contains("gfortran") -> 1
            name.contains("stdc++") || name.contains("c++") -> 2
            else -> 9
        }
    }

    private fun pyResultToMap(value: PyObject): Map<String, Any> {
        return mapOf(
            "stdout" to readStringField(value, "stdout"),
            "stderr" to readStringField(value, "stderr"),
            "exitCode" to readIntField(value, "exitCode", -1),
            "timedOut" to readBoolField(value, "timedOut", false),
            "durationMs" to readIntField(value, "durationMs", 0),
        )
    }

    private fun readStringField(value: PyObject, key: String): String {
        val field = readField(value, key) ?: return ""
        return field.toString()
    }

    private fun readIntField(value: PyObject, key: String, fallback: Int): Int {
        val field = readField(value, key) ?: return fallback
        return runCatching { field.toInt() }.getOrElse {
            field.toString().toIntOrNull() ?: fallback
        }
    }

    private fun readBoolField(value: PyObject, key: String, fallback: Boolean): Boolean {
        val field = readField(value, key) ?: return fallback
        return when (field.toString().lowercase()) {
            "true", "1" -> true
            "false", "0" -> false
            else -> fallback
        }
    }

    private fun readField(value: PyObject, key: String): PyObject? {
        val field = runCatching { value.callAttr("get", key) }.getOrNull() ?: return null
        if (field.toString() == "None") return null
        return field
    }
}
