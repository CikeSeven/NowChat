"""NowChat Android Python 执行入口（Chaquopy 侧）。

职责概览：
1. 接收 Flutter/Kotlin 传入的代码与执行参数；
2. 安全注入临时 sys.path 与工作目录；
3. 捕获 stdout/stderr，并把日志实时回传给宿主；
4. 处理超时、异常与原生库预加载；
5. 输出统一结果结构给 Kotlin（再回传 Flutter）。

说明：
- 本文件运行在 Android 进程内，由 `MainActivity.kt` 调用 `execute_code(...)`。
"""

from __future__ import annotations

import contextlib
import ctypes
import io
import os
import shutil
import sys
import threading
import time
import traceback
from typing import Any

# 记录已成功预加载的 .so，避免重复加载同一路径导致无意义开销。
_LOADED_NATIVE_LIBS: set[str] = set()


class _RealtimeStream(io.TextIOBase):
    """把 Python 输出同时写入缓冲区，并逐行实时推送给宿主。

    设计目的：
    - stdout/stderr 仍完整保留在内存里，供最终返回；
    - 同时把每一行尽快推送到 Kotlin -> Flutter，便于实时日志观察；
    - 若实时推送失败，不影响主执行流程。

    Args:
        io.TextIOBase: 继承标准文本流接口，供 redirect_stdout/stderr 使用。
    """

    def __init__(self, stream_name: str, buffer: io.StringIO, emitter: Any):
        """初始化实时日志流包装器。

        Args:
            stream_name: 流名称，通常为 `stdout` 或 `stderr`。
            buffer: 最终结果缓冲区，用于收集完整输出文本。
            emitter: 宿主日志发射器，需提供 `emit(stream, line)` 方法。
        """
        super().__init__()
        self._stream_name = stream_name
        self._buffer = buffer
        self._emitter = emitter
        # 累积未换行片段。只有遇到 '\n' 才按“完整行”上报。
        self._pending = ""

    def writable(self) -> bool:
        """声明该流可写。

        Returns:
            bool: 固定返回 True。
        """
        return True

    def write(self, data: Any) -> int:
        """写入文本并按行实时推送。

        Args:
            data: 任意待写入对象，将被转为字符串。

        Returns:
            int: 本次写入的字符长度。
        """
        text = str(data or "")
        if not text:
            return 0

        # 无论是否有 emitter，都先写入最终缓冲区，保证返回结果完整。
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
                # 日志通道失败不应打断 Python 执行。
                pass
        return len(text)

    def flush(self) -> None:
        """刷新未换行的尾部内容并尝试上报。"""
        # 线程收尾时把末尾未换行数据也推送出去，避免“最后一行丢失”。
        if not self._pending:
            return
        if self._emitter is not None:
            try:
                self._emitter.emit(self._stream_name, self._pending)
            except Exception:
                pass
        self._pending = ""


def _clean_path_text(value: Any) -> str:
    """将任意对象安全转成去空白路径文本。

    Args:
        value: 原始对象，可为字符串、None 或其他类型。

    Returns:
        str: 去首尾空白后的字符串；空值会转为空字符串。
    """
    return str(value or "").strip()


def _safe_iter_items(value: Any) -> list[Any]:
    """把未知对象尽量展开为列表，兼容 Chaquopy Java 对象。

    该函数专门用于解决 `toArray()` 返回对象在类型检查中“不可迭代”的问题：
    - 先尝试标准 Python 迭代协议；
    - 再尝试 Java/数组常见的 len + 下标访问；
    - 均失败时返回空列表，不抛异常。

    Args:
        value: 任意待展开对象（Python 容器、Java 对象或单值）。

    Returns:
        list[Any]: 尽可能展开后的列表；无法展开时返回空列表。
    """
    if value is None:
        return []

    if isinstance(value, (list, tuple, set)):
        return list(value)

    # 常规 Python 可迭代对象路径。
    try:
        return list(iter(value))
    except Exception:
        pass

    # Java 对象兜底路径：支持 __len__ + __getitem__。
    try:
        length = len(value)  # type: ignore[arg-type]
    except Exception:
        return []

    result: list[Any] = []
    for index in range(length):
        try:
            result.append(value[index])  # type: ignore[index]
        except Exception:
            continue
    return result


def _normalize_sys_paths(extra_sys_paths: Any) -> list[str]:
    """把 Kotlin 传入的路径参数统一规范为 `list[str]`。
    Args:
        extra_sys_paths: Kotlin/Chaquopy 传入的路径参数。

    Returns:
        list[str]: 规范化后的非空路径列表。
    """
    if extra_sys_paths is None:
        return []

    normalized: list[str] = []

    # Chaquopy 场景下常见 Java List：优先用 toArray() 转成可枚举集合。
    # 这里不直接写 `for item in to_array()`，避免静态检查报“object 不可迭代”。
    to_array = getattr(extra_sys_paths, "toArray", None)
    if callable(to_array):
        try:
            raw_array = to_array()
            for item in _safe_iter_items(raw_array):
                path = _clean_path_text(item)
                if path:
                    normalized.append(path)
            if normalized:
                return normalized
        except Exception:
            # toArray 路径失败则继续尝试下一种解析方式。
            pass

    # 常规可迭代路径。
    for item in _safe_iter_items(extra_sys_paths):
        path = _clean_path_text(item)
        if path:
            normalized.append(path)
    if normalized:
        return normalized

    # 最后兜底：把输入当成单值路径。
    fallback = _clean_path_text(extra_sys_paths)
    return [fallback] if fallback else []


def _collect_native_lib_dirs(extra_sys_paths: list[str]) -> list[str]:
    """收集可能包含 `.so` 的目录。

    策略：
    - 先加入用户提供的路径本身；
    - 再递归扫描子目录，凡是命中 `.so` 文件的目录也加入；
    - 结果去重并保序，尽量保持“浅层目录优先”。

    Args:
        extra_sys_paths: 候选路径列表。

    Returns:
        list[str]: 可能包含原生库的目录列表。
    """
    result: list[str] = []
    seen: set[str] = set()
    for base in extra_sys_paths:
        base = _clean_path_text(base)
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


def _collect_so_files(folder: str) -> list[str]:
    """读取目录内 `.so` 文件并按依赖优先级排序。

    Args:
        folder: 待扫描目录。

    Returns:
        list[str]: 排序后的 `.so` 绝对路径列表。
    """
    try:
        names = [name for name in os.listdir(folder) if ".so" in name]
    except Exception:
        return []
    names.sort(key=_native_lib_priority)
    return [os.path.join(folder, name) for name in names]


def _resolve_openblas_binary(extra_sys_paths: list[str]) -> str | None:
    """定位 OpenBLAS 动态库路径，优先精确命中 `libopenblas.so`。

    Args:
        extra_sys_paths: 候选路径列表。

    Returns:
        str | None: 命中的 OpenBLAS 路径；未找到返回 None。
    """
    candidate: str | None = None
    for folder in _collect_native_lib_dirs(extra_sys_paths):
        for full_path in _collect_so_files(folder):
            lower = os.path.basename(full_path).lower()
            if not lower.startswith("libopenblas.so"):
                continue
            if lower == "libopenblas.so":
                return full_path
            if candidate is None:
                candidate = full_path
    return candidate


def _ensure_openblas_alias(openblas_path: str | None) -> str | None:
    """确保存在 `libopenblas.so` 这个稳定文件名。

    某些包只有 `libopenblas.so.X`，而 numpy 动态链接期望 `libopenblas.so`。
    因此这里会在同目录复制一个别名文件，降低导入失败概率。

    Args:
        openblas_path: 已找到的 OpenBLAS 路径。

    Returns:
        str | None: 可用的 `libopenblas.so` 路径；失败时返回原路径或 None。
    """
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
        # 复制失败时退化使用原路径，尽量不阻断后续流程。
        return openblas_path


def _bridge_openblas_for_numpy(extra_sys_paths: list[str]) -> None:
    """把 openblas 复制到 numpy/core 附近，解决 `_multiarray_umath` 找库失败。

    Args:
        extra_sys_paths: 候选路径列表。
    """
    openblas_path = _ensure_openblas_alias(_resolve_openblas_binary(extra_sys_paths))
    if not openblas_path or not os.path.isfile(openblas_path):
        return

    for base in extra_sys_paths:
        base = _clean_path_text(base)
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


def _native_lib_priority(name: str) -> int:
    """定义 `.so` 预加载优先级（越小越先加载）。

    Args:
        name: 动态库文件名或路径。

    Returns:
        int: 预加载优先级。
    """
    value = name.lower()
    if "openblas" in value:
        return 0
    if "gfortran" in value:
        return 1
    if "stdc++" in value or "c++" in value:
        return 2
    return 9


def _preload_native_libs(extra_sys_paths: list[str]) -> None:
    """尝试以 `RTLD_GLOBAL` 预加载动态库，提升后续扩展模块导入稳定性。

    Args:
        extra_sys_paths: 候选路径列表。
    """
    mode = getattr(ctypes, "RTLD_GLOBAL", 0)
    for folder in _collect_native_lib_dirs(extra_sys_paths):
        for full_path in _collect_so_files(folder):
            if full_path in _LOADED_NATIVE_LIBS:
                continue
            try:
                ctypes.CDLL(full_path, mode=mode)
                _LOADED_NATIVE_LIBS.add(full_path)
            except Exception:
                # 单个 so 失败不应影响整体执行，真实错误交给 import 时再暴露。
                continue


def execute_code(
    code: str,
    timeout_ms: int = 20000,
    extra_sys_paths: Any = None,
    working_directory: str = "",
    run_id: str = "",
    log_emitter: Any = None,
) -> dict[str, Any]:
    """执行一段 Python 代码并返回结构化结果。

    返回结构固定为：
    - stdout: str
    - stderr: str
    - exitCode: int  (0=成功, 1=异常, -1=超时)
    - timedOut: bool
    - durationMs: int

    Args:
        code: 待执行的 Python 代码文本。
        timeout_ms: 超时时间（毫秒）。
        extra_sys_paths: 额外 sys.path（可为 Python/Java 列表、数组、单值）。
        working_directory: 执行工作目录；为空则使用当前目录。
        run_id: 运行标识（预留字段，便于宿主侧日志关联）。
        log_emitter: 实时日志发射器，需提供 `emit(stream, line)`。

    Returns:
        dict[str, Any]: 标准执行结果字典，字段见上文说明。
    """
    started_at = time.time()
    stdout_buffer = io.StringIO()
    stderr_buffer = io.StringIO()
    normalized_paths = _normalize_sys_paths(extra_sys_paths)

    result: dict[str, Any] = {
        "stdout": "",
        "stderr": "",
        "exitCode": 0,
        "timedOut": False,
        "durationMs": 0,
    }

    def _worker() -> None:
        # 使用独立作用域执行用户代码，避免污染 runner 模块全局变量。
        globals_scope = {"__name__": "__main__", "__builtins__": __builtins__}
        locals_scope: dict[str, Any] = {}
        inserted_paths: list[str] = []
        previous_cwd: str | None = None
        realtime_stdout = _RealtimeStream("stdout", stdout_buffer, log_emitter)
        realtime_stderr = _RealtimeStream("stderr", stderr_buffer, log_emitter)

        try:
            # 若宿主传入工作目录，则切换到该目录执行，避免写入只读根目录 `/`。
            normalized_working_directory = _clean_path_text(working_directory)
            if normalized_working_directory:
                previous_cwd = os.getcwd()
                os.makedirs(normalized_working_directory, exist_ok=True)
                os.chdir(normalized_working_directory)

            # 临时注入插件路径，执行后会回滚，避免污染全局 sys.path。
            for item in normalized_paths:
                path = _clean_path_text(item)
                if not path:
                    continue
                if path not in sys.path:
                    sys.path.insert(0, path)
                    inserted_paths.append(path)

            # 在执行前做一次原生依赖预处理，减少 numpy/pandas 导入失败概率。
            _bridge_openblas_for_numpy(normalized_paths)
            _preload_native_libs(normalized_paths)

            # 统一重定向 stdout/stderr，既能实时上报，也能最终汇总返回。
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
            # 把最后残留的未换行日志刷新出去。
            realtime_stdout.flush()
            realtime_stderr.flush()

            # 回滚本次注入的 sys.path，保证执行前后环境一致。
            for path in inserted_paths:
                try:
                    sys.path.remove(path)
                except ValueError:
                    pass

            # 回滚 cwd，避免影响同进程后续任务。
            if previous_cwd:
                try:
                    os.chdir(previous_cwd)
                except Exception:
                    pass

    # 使用 daemon 线程执行，主线程负责超时监控与结果汇总。
    worker = threading.Thread(target=_worker, daemon=True)
    worker.start()
    timeout_sec = max(int(timeout_ms), 1) / 1000.0
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
