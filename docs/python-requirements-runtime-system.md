# Python Requirements 运行时安装系统（当前实现）

本文描述 NowChat 当前代码中的 Python requirements 安装行为，用于插件开发、排障和发布验收。

## 1. 目标

requirements 系统用于替代“把第三方库直接打进插件包”的单一路径，实现：

1. 插件按 `plugin.json` 声明依赖并在安装阶段自动拉取。
2. 插件版本级依赖隔离，避免不同插件相互污染。
3. 通过 lock 文件记录可追溯安装结果。

## 2. 数据来源与入口

### 2.1 requirements 声明入口

插件 `plugin.json`：

```json
{
  "requirements": ["numpy", "pandas", "matplotlib"]
}
```

### 2.2 安装调用入口

调用链：

1. `PluginProvider._installRequirementsPackageIfNeeded`
2. `PythonPluginService.installRequirements`

相关文件：

- `lib/providers/plugin_provider.dart`
- `lib/core/plugin/python_plugin_service.dart`

## 3. 安装目录与产物

对于某个插件版本目录：`<pluginTargetDir>`

1. requirements 安装目录：`<pluginTargetDir>/__requirements__`
2. lock 文件：`<pluginTargetDir>/plugin_requirements_lock.json`

示例（本地导入）：

- `plugin_runtime/local_plugins/<pluginId>/<version>/__requirements__`
- `plugin_runtime/local_plugins/<pluginId>/<version>/plugin_requirements_lock.json`

示例（仓库安装）：

- `plugin_runtime/remote_plugins/<pluginId>/<version>/__requirements__`
- `plugin_runtime/remote_plugins/<pluginId>/<version>/plugin_requirements_lock.json`

## 4. 镜像链路

镜像配置文件：`lib/core/network/python_package_mirror_config.dart`

当前策略：

1. 优先 Chaquopy 源（`direct`）。
2. 解析不到候选时回退 PyPI simple：
   - `https://pypi.tuna.tsinghua.edu.cn/simple`
   - `https://pypi.org/simple`

说明：

1. PyPI 回退是解析层回退，不代表接受任意 wheel。
2. 安装器会继续做 wheel 兼容筛选。

## 5. 依赖解析规则

### 5.1 直接依赖

支持示例：

- `name`
- `name==1.2.3`
- `name>=1.0,<2.0`

### 5.2 传递依赖

安装器会读取 wheel metadata 的 `Requires-Dist`，并追加到待安装队列。

关键点：

1. 支持常见 marker：`python_version/sys_platform/platform_system/os_name/extra`。
2. marker 无法可靠解析时，采用保守策略避免漏装关键依赖。
3. extras 条件在当前运行模式下按“无 extras 选择”处理。

### 5.3 wheel 候选评分

安装器会按 Python 版本、ABI、平台标签进行候选评分，优先匹配 Android 场景。

PyPI 回退路径额外限制：

1. 优先纯 Python wheel（如 `py3-none-any`）。
2. 以降低 ABI 不兼容和 native 崩溃概率。

## 6. lock 文件字段

`plugin_requirements_lock.json` 当前主要字段：

- `pluginId`
- `resolvedAt`
- `targetDir`
- `requirements`
- `mirrorChain`
- `pypiFallback`
- `packages[]`

`packages[]` 典型字段：

- `requirement`
- `sourceRequirement`
- `package`
- `version`
- `sourceType`（`chaquopy` 或 `pypi`）
- `mirrorId`
- `indexUrl`
- `downloadUrl`
- `sha256`
- `discoveredDependencies`
- `fallbackTried`

## 7. 覆盖安装与依赖复用

同 ID 本地插件覆盖安装时：

1. 若旧版与新版 requirements 签名一致，可复用旧 `__requirements__`。
2. 若不一致，重新安装 requirements。
3. 旧版本中不再需要的包目录会被清理。

相关逻辑：`PluginProvider.importLocalPluginPayload`。

## 8. 失败类型与排障

常见失败类型：

1. 镜像不可达 / 索引 404。
2. requirements 无可用候选 wheel。
3. checksum 不匹配。
4. 运行时 native 依赖缺失（如部分科学计算库场景）。

排障顺序：

1. 看安装阶段日志：`解析依赖`、`依赖索引请求失败`、`依赖安装成功`。
2. 看 lock 文件：确认最终包版本、来源、回退链。
3. 看运行时报错：定位是导入错误、路径错误还是 native `.so` 问题。

## 9. 发布建议

1. 插件 requirements 保持最小集合。
2. 优先验证主流机型（Android 版本 + ABI）。
3. 每次发布都保留 lock 安装日志做回归比对。
4. 对有 native 依赖的库优先做真机验证，不依赖模拟器结论。
