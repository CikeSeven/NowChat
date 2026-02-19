import contextlib
import ctypes
import io
import os
import shutil
import sys
import threading
import time
import traceback

_LOADED_NATIVE_LIBS = set()


class _RealtimeStream(io.TextIOBase):
    """同时写入内存缓冲并向宿主实时推送日志行。"""

    def __init__(self, stream_name, buffer, emitter):
        super().__init__()
        self._stream_name = stream_name
        self._buffer = buffer
        self._emitter = emitter
        self._pending = ""

    def writable(self):
        return True

    def write(self, data):
        text = str(data or "")
        if not text:
            return 0
        self._buffer.write(text)
        if self._emitter is None:
            return len(text)

        self._pending += text
        while True:
            index = self._pending.find("\n")
            if index < 0:
                break
            line = self._pending[:index]
            self._pending = self._pending[index + 1 :]
            try:
                self._emitter.emit(self._stream_name, line)
            except Exception:
                # 实时日志失败不影响主执行流程。
                pass
        return len(text)

    def flush(self):
        if not self._pending:
            return
        if self._emitter is not None:
            try:
                self._emitter.emit(self._stream_name, self._pending)
            except Exception:
                pass
        self._pending = ""


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


def _collect_native_lib_dirs(extra_sys_paths):
    """收集可能包含 .so 的目录，优先返回浅层目录。"""
    result = []
    seen = set()
    for base in extra_sys_paths:
        base = str(base).strip()
        if not base or not os.path.isdir(base):
            continue
        if base not in seen:
            result.append(base)
            seen.add(base)
        for root, _, files in os.walk(base):
            has_so = any(".so" in name for name in files)
            if not has_so:
                continue
            if root not in seen:
                result.append(root)
                seen.add(root)
    return result


def _collect_so_files(folder):
    try:
        names = [n for n in os.listdir(folder) if ".so" in n]
    except Exception:
        return []
    names.sort(key=_native_lib_priority)
    return [os.path.join(folder, name) for name in names]


def _resolve_openblas_binary(extra_sys_paths):
    candidate = None
    for folder in _collect_native_lib_dirs(extra_sys_paths):
        for full_path in _collect_so_files(folder):
            lower = os.path.basename(full_path).lower()
            if not lower.startswith("libopenblas.so"):
                continue
            # 命中精确名时直接返回。
            if lower == "libopenblas.so":
                return full_path
            if candidate is None:
                candidate = full_path
    return candidate


def _ensure_openblas_alias(openblas_path):
    """若只有 libopenblas.so.*，则复制一份 libopenblas.so 供 numpy 动态链接。"""
    if not openblas_path:
        return None
    folder = os.path.dirname(openblas_path)
    base = os.path.basename(openblas_path)
    if base == "libopenblas.so":
        return openblas_path
    alias = os.path.join(folder, "libopenblas.so")
    if os.path.isfile(alias):
        return alias
    try:
        shutil.copy2(openblas_path, alias)
        return alias
    except Exception:
        return openblas_path


def _bridge_openblas_for_numpy(extra_sys_paths):
    """将 openblas 复制到 numpy/core 同目录，避免 _multiarray_umath 依赖解析失败。"""
    openblas_path = _ensure_openblas_alias(_resolve_openblas_binary(extra_sys_paths))
    if not openblas_path or not os.path.isfile(openblas_path):
        return

    for base in extra_sys_paths:
        base = str(base).strip()
        if not base or not os.path.isdir(base):
            continue
        for root, _, files in os.walk(base):
            if "_multiarray_umath.so" not in files:
                continue
            target = os.path.join(root, "libopenblas.so")
            if os.path.isfile(target):
                continue
            try:
                shutil.copy2(openblas_path, target)
            except Exception:
                continue


def _native_lib_priority(name: str):
    """基础依赖优先加载，减少后续扩展加载失败概率。"""
    value = name.lower()
    if "openblas" in value:
        return 0
    if "gfortran" in value:
        return 1
    if "stdc++" in value or "c++" in value:
        return 2
    return 9


def _preload_native_libs(extra_sys_paths):
    """尝试以 RTLD_GLOBAL 预加载动态库，便于 numpy/pandas 等原生扩展导入。"""
    mode = getattr(ctypes, "RTLD_GLOBAL", 0)
    for folder in _collect_native_lib_dirs(extra_sys_paths):
        for full_path in _collect_so_files(folder):
            if full_path in _LOADED_NATIVE_LIBS:
                continue
            try:
                ctypes.CDLL(full_path, mode=mode)
                _LOADED_NATIVE_LIBS.add(full_path)
            except Exception:
                # 忽略单个库预加载失败，实际 import 报错时再由调用方看到详细信息。
                continue


def execute_code(
    code: str,
    timeout_ms: int = 20000,
    extra_sys_paths=None,
    working_directory: str = "",
    run_id: str = "",
    log_emitter=None,
):
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
        previous_cwd = None
        realtime_stdout = _RealtimeStream("stdout", stdout_buffer, log_emitter)
        realtime_stderr = _RealtimeStream("stderr", stderr_buffer, log_emitter)
        try:
            # 若宿主传入工作目录，则切换到该目录执行，避免默认 cwd 指向只读根目录 `/`。
            normalized_working_directory = str(working_directory or "").strip()
            if normalized_working_directory:
                previous_cwd = os.getcwd()
                os.makedirs(normalized_working_directory, exist_ok=True)
                os.chdir(normalized_working_directory)

            for item in extra_sys_paths:
                path = str(item).strip()
                if not path:
                    continue
                if path not in sys.path:
                    sys.path.insert(0, path)
                    inserted_paths.append(path)

            _bridge_openblas_for_numpy(extra_sys_paths)
            _preload_native_libs(extra_sys_paths)

            with contextlib.redirect_stdout(
                realtime_stdout
            ), contextlib.redirect_stderr(
                realtime_stderr
            ):
                compiled = compile(code, "<now_chat_python>", "exec")
                exec(compiled, globals_scope, locals_scope)
        except Exception:
            traceback.print_exc(file=stderr_buffer)
            result["exitCode"] = 1
        finally:
            realtime_stdout.flush()
            realtime_stderr.flush()
            for path in inserted_paths:
                try:
                    sys.path.remove(path)
                except ValueError:
                    pass
            if previous_cwd:
                try:
                    os.chdir(previous_cwd)
                except Exception:
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
