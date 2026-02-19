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

            _bridge_openblas_for_numpy(extra_sys_paths)
            _preload_native_libs(extra_sys_paths)

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
