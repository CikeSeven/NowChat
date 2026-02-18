import contextlib
import io
import sys
import threading
import time
import traceback


def _normalize_sys_paths(extra_sys_paths):
    """兼容 Chaquopy 传入的 java.util.ArrayList / Python list / None。"""
    if extra_sys_paths is None:
        return []

    # Chaquopy 侧常见：java.util.ArrayList，不可直接按 Python iterable 用。
    to_array = getattr(extra_sys_paths, "toArray", None)
    if callable(to_array):
        try:
            return [str(item).strip() for item in to_array() if str(item).strip()]
        except Exception:
            pass

    try:
        return [str(item).strip() for item in extra_sys_paths if str(item).strip()]
    except Exception:
        # 最后兜底：当成单值处理。
        value = str(extra_sys_paths).strip()
        return [value] if value else []


def execute_code(code: str, timeout_ms: int = 20000, extra_sys_paths=None):
    """执行一段 Python 代码并返回结构化结果。"""
    started_at = time.time()
    stdout_buffer = io.StringIO()
    stderr_buffer = io.StringIO()
    extra_sys_paths = _normalize_sys_paths(extra_sys_paths)

    result = {
        "stdout": "",
        "stderr": "",
        "exitCode": 0,
        "timedOut": False,
        "durationMs": 0,
    }

    def _worker():
        globals_scope = {"__name__": "__main__", "__builtins__": __builtins__}
        locals_scope = {}
        inserted_paths = []
        try:
            for item in extra_sys_paths:
                path = str(item).strip()
                if not path:
                    continue
                if path not in sys.path:
                    sys.path.insert(0, path)
                    inserted_paths.append(path)

            with contextlib.redirect_stdout(stdout_buffer), contextlib.redirect_stderr(
                stderr_buffer
            ):
                compiled = compile(code, "<now_chat_python>", "exec")
                exec(compiled, globals_scope, locals_scope)
        except Exception:
            traceback.print_exc(file=stderr_buffer)
            result["exitCode"] = 1
        finally:
            for path in inserted_paths:
                try:
                    sys.path.remove(path)
                except ValueError:
                    pass

    worker = threading.Thread(target=_worker, daemon=True)
    worker.start()
    timeout_sec = max(timeout_ms, 1) / 1000.0
    worker.join(timeout_sec)

    if worker.is_alive():
        result["timedOut"] = True
        result["exitCode"] = -1
        if stderr_buffer.tell() > 0:
            stderr_buffer.write("\n")
        stderr_buffer.write(f"Execution timed out after {timeout_sec:.2f} seconds.")

    duration_ms = int((time.time() - started_at) * 1000)
    result["durationMs"] = duration_ms
    result["stdout"] = stdout_buffer.getvalue()
    result["stderr"] = stderr_buffer.getvalue()
    return result
