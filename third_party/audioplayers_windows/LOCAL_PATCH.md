# 本地补丁说明

来源：`audioplayers_windows 4.2.0`（pub.dev，与 audioplayers 6.4.0 约束匹配）。

## 补丁内容（相对原版）

修复 Windows 端 "sent a message from native to Flutter on a non-platform
thread" 引擎错误（上游 issue #1635/#1917，截至 4.4.1 未修复）：

- 新增 `windows/platform_dispatch.{h,cpp}`：在插件注册（平台线程）时创建
  message-only 窗口，`Post()` 可从任意线程把任务投递回平台线程执行。
- `windows/audio_player.{h,cpp}`：MediaEngine 的五个回调
  （onLoaded/onError/onBuffering/onPlaybackEnded/onSeekCompleted，来自
  Media Foundation 工作线程的 EventNotify）改为经 PlatformDispatch
  投递后再触达 EventSink；`_alive` 原子守卫丢弃玩家析构后的遗留任务。
- `windows/audioplayers_windows_plugin.cpp`：注册时启动调度器。
- `windows/CMakeLists.txt`：加入新源文件。

注：源码注释保持 ASCII（MSVC 在 GBK 代码页下会把 UTF-8 中文注释
当成 C4819 警告并因 /WX 升级为错误）。

同步上游新版本时，需要重放以上改动。
