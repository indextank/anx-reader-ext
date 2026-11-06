# TTS 修复依赖评估（03）

日期：2026-11-04（以工作区当前锁文件为准）
范围：Windows 优先的 TTS 管线修复是否需要引入新的第三方依赖或新技术。

## 1. 结论

**不新增任何第三方运行时依赖。** 本次修复只需要：

- Dart / Flutter SDK（本机 Flutter `3.47.8`，工程约束 `sdk: '>=3.5.2 <4.0.0'`）；
- 已有依赖：`audioplayers 6.4.0` + vendored `audioplayers_windows 4.2.0`、`flutter_tts` fork `4.2.3`、`flutter_riverpod 2.6.1` / `riverpod 2.6.1`、`audio_service 0.18.17`、`audio_session 0.1.25`；
- 仅测试可选：Flutter SDK 自带的 `integration_test`（SDK package，dev-only，不进入发布产物）。**最终状态（2026-11-04 集成）**：已作为 SDK-only dev 依赖加入 `pubspec.yaml`（`integration_test: sdk: flutter`），用于 `integration_test/tts_pipeline_acceptance_test.dart`；无第三方运行时依赖、无发布包体积影响。

所有已报告的 6 类症状都可以在现有依赖的公开 API（`AudioPlayer.setSourceBytes/setPlaybackRate/pause`、`flutter_tts.pause` + 原生插件通道、`Riverpod`）内解决，不需要换引擎、加 native 包或引入音频混音库。

## 2. 现有依赖基线（`pubspec.lock` / `package_config.json`）

| 依赖 | 版本 | 许可证 | 角色 | Windows 实现 |
| --- | --- | --- | --- | --- |
| audioplayers | 6.4.0 | MIT | 在线 TTS 音频播放 | 由 `audioplayers_windows` 提供 |
| audioplayers_windows | 4.2.0（`third_party/audioplayers_windows`，`dependency_overrides` 本地补丁） | MIT | Windows 音频输出 | MediaFoundation `IMFMediaEngine`（`MediaEngineWrapper.cpp`、`audio_player.cpp`） |
| flutter_tts | 4.2.3（git `Anxcye/flutter_tts@88d20d2`） | MIT | 系统 TTS（Windows SAPI / Android / iOS） | `flutter_tts_plugin.cpp`：`ISpVoice`，含原生 `Pause()` / `Resume()` |
| flutter_riverpod / riverpod | 2.6.1 / 2.6.1 | MIT | 播放状态 UI 订阅 | 纯 Dart |
| riverpod_annotation / riverpod_generator | 2.6.1 / 2.6.5（dev） | MIT | 生成 `@riverpod` 代码 | 纯 Dart（build_runner） |
| audio_service | 0.18.17 | MIT | 系统媒体控制 / 后台播放 | 纯 Dart + 平台通道（`BaseAudioHandler`） |
| audio_session | 0.1.25 | MIT | 音频会话配置 | 纯 Dart + 平台通道 |
| win32（transitive，`window_manager` 引入） | 5.11.0 | BSD-3-Clause | 当前未用于 TTS | Dart FFI（本项目不直接使用） |
| integration_test | 已加入 `dev_dependencies`（Flutter SDK，`sdk: flutter`） | BSD-3-Clause（Flutter SDK） | Windows 集成测试 | `flutter test integration_test -d windows` 使用 |

说明：

- 现有 `third_party/audioplayers_windows` 的本地补丁用于修复 MediaEngine 回调在 MF 工作线程直接发送事件通道导致的错误（`platform_dispatch.h`），与本次双缓冲/热启动改动不冲突，应保留而非替换。
- `flutter_tts` fork 的 Windows 插件已实现 `ISpVoice::Pause()`（`pause` 方法）与 `Resume()`（`continuePlay`），但 Dart 侧 4.2.3 只公开了 `pause()`，没有公开 `resume()`/`continue()`；Windows 插件把恢复收敛在 `speak` 通道分支（`if (isPaused) { continuePlay(); ... }`）。**最终状态（2026-11-04）**：系统 TTS 适配器 `FlutterTtsNativeEngine.resume()` 直接使用 `speak('')` 走该分支（Windows/iOS/macOS），Android 重发原文本，无需修改 fork；此依赖风险降级为「实现已覆盖，运行时听感待真机」，不改变依赖集合。

## 3. 候选方案逐项评估

| 候选 | 版本 / 平台 | 许可证 | 维护与 Windows 实现 | 结论 |
| --- | --- | --- | --- | --- |
| (a) 保留 audioplayers_windows 4.2.0 + 本地补丁 | 当前已锁定 | MIT | 上游活跃；本仓库已有 vendored 补丁；MF 实现成熟 | **采用**：双缓冲输出（`FlutterTtsAudioOutput`）建立在其上 |
| (b) 保留 flutter_tts fork 4.2.3 | git ref 固定 | MIT | 上游 dlutton/flutter_tts 活跃；fork 增加 Windows 能力；SAPI 原生 pause/resume 已存在 | **采用**：只在新适配器内使用，不升级/不替换 |
| (c) 新增 flutter_soloud | 5.2.2；Windows ✅ | MIT（插件）；SoLoud 引擎 zlib | 活跃；miniaudio/SoLoud C++，Dart build hooks；低延迟、可内存流播放 | **拒绝**：需要引入第二套原生音频引擎与构建钩子，包体与维护面增大；当前问题可在 audioplayers 层用双缓冲 + 热启动解决，收益不足以抵消风险 |
| (d) 新增 just_audio | 0.10.6；Windows 无官方实现 | MIT | 活跃；Windows 必须再加 `just_audio_media_kit` + `media_kit_libs_windows_audio`，实际等于引入 media_kit | **拒绝**：依赖链更重，Windows 支持是社区/第三方层，问题定位不降反升 |
| (e) 新增 media_kit | 1.2.6；Windows ✅ | MIT（`media_kit`）；底层 libmpv 为 LGPL-2.1+ | 活跃；功能强但二进制大 | **拒绝**：libmpv 动态库体积大（数十 MB 级）、初始化与 audio_service 集成成本高；超出本次修复边界 |
| (f) win32 5.11.0 + 自写 SAPI COM 通道 | 5.11.0；Windows | BSD-3-Clause | win32 已是 transitive 依赖，但 SAPI COM 需自行写 isolate/COM 生命周期与平台通道，且只在 Windows 生效 | **拒绝**：重复已有 `flutter_tts` Windows 插件能力，跨平台分支与测试成本高；现有 fork 的 pause/resume 已可用 |
| (g) 新增 integration_test | Flutter SDK 版本（`integration_test: sdk: flutter`）；Windows ✅ | BSD-3-Clause（SDK） | 官方维护，仅 dev 依赖 | **已采用（dev-only）**：已加入 `dev_dependencies` 支撑 `integration_test/tts_pipeline_acceptance_test.dart`；不进入发布包，无运行时体积影响。本地 Windows 集成运行因缺 VS ATL 组件构建失败（`atlstr.h`，环境问题，非依赖问题） |

## 4. 兼容性核对

- **Dart 约束**：`pubspec.yaml` 为 `sdk: '>=3.5.2 <4.0.0'`。新增/沿用的所有 API（`sealed class`、`final class`、`unawaited`、`ValueNotifier`）均兼容 3.5.2；不引入需要更高 SDK 的语法。
- **Flutter**：本机 3.47.8，`flutter_lints 5.0.0`；主任务实测 `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` → 0 errors（140 既有 infos/warnings，含 third_party），新代码无 error。
- **Riverpod**：沿用 2.6.1 + `riverpod_generator 2.6.5`，不升级到 Riverpod 3；新 tri-state provider 使用与 `tts_reading_position_provider.dart` 相同的代码生成风格，避免引入迁移风险。
- **Windows**：`audioplayers_windows` MF 引擎对 `BytesSource` 走 `SetSourceBytes → CreateObjectFromByteStream → SetMediaSource → SetSource`，`setPlaybackRate` 走 `IMFMediaEngineEx::SetPlaybackRate`；双缓冲 = 两个 `AudioPlayer` 实例，不新增原生代码。
- **系统 TTS**：Windows SAPI 的 `ISpVoice` 由 fork 插件封装；不额外依赖 Windows SDK 包或 C++/WinRT 直接绑定。
- **构建/包体影响**：本次不新增动态库、不新增代码生成器、不改 Android/iOS 构建配置；`third_party/audioplayers_windows` 是已有源码，无新增体积。唯一可选变化是 `integration_test` dev 依赖，release 构建零影响。

## 5. 结论与边界

1. 运行时依赖集合保持现状：`audioplayers`、vendored `audioplayers_windows`、`flutter_tts` fork、`flutter_riverpod`、`audio_service`、`audio_session`。
2. 不引入 flutter_soloud / just_audio / media_kit / win32 直写 SAPI 等替代或补充音频技术；理由集中在「重复已有能力、包体与维护成本、Windows 支持成熟度」。
3. `integration_test` 已作为 SDK-only dev 依赖加入（2026-11-04 集成决定），仅用于 Windows 集成验收；无第三方运行时依赖，发布包零影响。
4. 依赖侧风险已收敛：`flutter_tts` 4.2.3 Dart API 缺公开 `resume()`，最终实现用「paused 状态下 `speak('')` 等价 continuePlay」覆盖（Windows/iOS/macOS），Android 重发原文本；无需修改 fork，也不改变本项目依赖集合。运行时听感仍待 Windows 真机（本地 ATL 缺失导致集成构建不可用，见 04）。
5. 唯一的环境性依赖发现（非依赖缺陷）：vendored `flutter_tts` Windows 插件编译需要 VS ATL 组件（`atlstr.h`）；本机未安装，导致 `flutter test integration_test/... -d windows` 构建失败（`C1083`）。这是开发机工具链前置条件，不是新增依赖。

（本文件只记录评估结论，不修改 `pubspec.yaml`；依赖变更由主任务统一决策。）
