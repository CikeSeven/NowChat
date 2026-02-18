package com.nowchat

import com.chaquo.python.PyObject
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private val channelName = "nowchat/python_bridge"
    private val methodExecute = "executePython"
    private val methodIsReady = "isPythonReady"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
    }

    private fun executePython(call: MethodCall, result: MethodChannel.Result) {
        val code = call.argument<String>("code")?.trim().orEmpty()
        val timeoutMs = call.argument<Int>("timeoutMs") ?: 20_000
        val rawPaths = call.argument<List<String>>("extraSysPaths") ?: emptyList()
        val extraSysPaths = rawPaths.map { it.trim() }.filter { it.isNotEmpty() }

        if (code.isEmpty()) {
            result.error("empty_code", "代码不能为空", null)
            return
        }

        Thread {
            runCatching {
                ensurePythonStarted()
                val py = Python.getInstance()
                val module = py.getModule("runner")
                val pyResult = module.callAttr("execute_code", code, timeoutMs, extraSysPaths)
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

    private fun ensurePythonStarted() {
        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
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
