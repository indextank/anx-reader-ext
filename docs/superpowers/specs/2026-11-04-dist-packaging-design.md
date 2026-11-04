# 统一打包输出与选择性清理设计

日期：2026-11-04
状态：已确认
目标：将 Android、Windows、Linux、macOS 的最终打包产物统一输出到根目录 `dist`，并在构建成功后选择性清理不再需要的 `build` 临时文件。

## 背景与现状

当前产物分散在：

- Android：`build/app/outputs/flutter-apk/`。
- Windows：`build/windows/unsigned/`、签名流程中的 `build/windows/`。
- Linux：`build/linux/` 和 `build/linux/dist/`。
- macOS：`build/macos/`。

`build_test.bat` 负责 Android 和 Windows 测试包；Linux 使用 `scripts/build_linux_appimage.sh`；macOS 的 DMG/ZIP 在 CI 中生成。Windows 安装器、CI 上传和缓存路径与旧目录耦合。直接执行 `flutter clean` 会同时删除打包输入和产物，不能作为成功后的默认清理方式。

## 目标

- 最终产物统一进入 `dist/<platform>/`。
- 保留现有版本、ABI、rN、签名和平台包格式。
- 构建、复制和校验成功后，自动清理明确不再需要的临时文件。
- 保留可加速后续构建的 Gradle、CMake 等增量缓存，避免每次完整重建。
- 构建失败、复制失败或校验失败时保留现场，不执行清理。
- 更新 CI 和安装器路径，不长期维护双份最终产物。

## 统一输出结构

```text
dist/
  android/
    Anx-Reader-android-<version>-<abi>[-rN].apk
  windows/
    Anx-Reader-windows-<version>[-rN].zip
    Anx-Reader-windows-<version>.exe
  linux/
    Anx-Reader-linux-<version>-<arch>.AppImage
    Anx-Reader-linux-<version>-<arch>.tar.gz
  macos/
    Anx-Reader-macos-<version>.dmg
    Anx-Reader-macos-<version>.zip
```

现有 `build_test.bat [rN] [all|android|windows]` 的用法保持不变，默认仍构建 Android 和 Windows。rN 自动递增需扫描新的 `dist/android` 和 `dist/windows`，不能继续只扫描旧 build 目录。

`dist` 是最终产物目录，不作为编译、staging 或下载工具缓存目录。将 `/dist/` 加入 `.gitignore`，避免本地打包产物进入版本控制。

## 方案 A：共享辅助模块与平台入口

抽取共享打包辅助模块，负责：

- 从 `pubspec.yaml` 读取并校验版本。
- 计算项目根目录、`dist` 和平台输出路径。
- 创建输出目录、复制产物并验证目标文件存在且非空。
- 执行平台既有的 ZIP/APK 完整性与必需条目校验。
- 校验成功后执行白名单清理。
- 统一错误信息和非零退出码。

平台入口继续负责各自的构建和打包步骤，不将 Flutter、Gradle、CMake、Inno Setup 或 Xcode 的具体命令抽象成新的通用构建语言。

### Windows

`build_test.bat` 的 Windows 分支继续：

- release 构建。
- 将 runner Release、图标和 VC runtime 复制到临时 staging。
- 压缩并校验 exe、logo、icudtl、flutter_assets 等必需条目。
- 将最终 ZIP 输出到 `dist/windows/`。

`scripts/build_windows.ps1` 不再使用硬编码 `D:\inno`、`D:\inno-result` 或旧 `build/windows/unsigned/app.zip` 作为最终路径。临时目录放在项目 `build` 下的明确 staging 子目录，最终输出到 `dist/windows/`。

`scripts/build_windows_exe.ps1` 从 `dist/windows/` 读取签名流程输入，并将安装器输出到同一目录。签名流程中的中间 ZIP/EXE 不覆盖最终已校验包，除非现有签名流程明确要求替换。

### Android

`build_test.bat` 的 Android 分支继续 release、split-per-abi、no-tree-shake-icons，并保留 zipfile 与 apksigner 校验。校验后的 APK 输出到 `dist/android/`，不再把重命名后的最终副本留在 `build/app/outputs/flutter-apk/`。

### Linux

`scripts/build_linux_appimage.sh` 继续生成 AppImage 和 tar.gz。最终文件只输出到 `dist/linux/`。

`appimagetool` 是下载工具而非最终产物，移到项目外的用户缓存目录，或 `build` 下明确不参与清理的工具缓存目录；不得因清理 AppDir/staging 而重复下载。CI 的 appimagetool 缓存路径同步更新。

### macOS

保留现有 macOS 应用构建、DMG 和 ZIP 生成方式。新增平台打包辅助入口，将 DMG/ZIP 输出到 `dist/macos/`。`release_build.sh` 的 `-d` 部署行为保持独立，不因统一输出而自动部署到 `/Applications`。

## 选择性清理策略

### 清理时机

只有以下步骤全部成功后才清理：

1. 平台构建成功。
2. 最终产物已复制到预期 `dist` 路径。
3. 产物完整性和平台必需条目校验通过。
4. 没有其他正在使用同一构建目录的打包进程。

任一失败都跳过后续清理并返回非零退出码。

### 白名单

按平台明确列出可删除路径：

- Windows：本次打包创建的 staging、临时压缩目录、Inno 输入/输出临时目录。
- Linux：本次创建的 staging、`AnxReader.AppDir` 和临时打包目录。
- macOS：本次 DMG 创建的临时源目录。
- Android：本次已校验并复制后不再需要的重命名临时副本。

不删除整个 `build`，不默认执行 `flutter clean`，不删除 Gradle、CMake、编译器或平台 SDK 缓存。后续构建仍需要的 runner、bundle 和编译输入保留。

### 路径安全

清理函数必须：

- 拒绝空路径、项目根目录、`dist` 和项目外路径。
- 拒绝不在预期平台 `build` 子树内的路径。
- 只删除本次任务明确登记且仍存在的临时路径。
- 遇到删除失败时报告警告或错误，不继续删除其他未登记目录。
- 不跟随指向项目外的链接目录。

构建期间不清理；检测到同一项目的活动构建/打包进程时跳过清理并提示，避免与并行任务争用。

## CI 与旧路径迁移

更新 Android、Windows、Linux、macOS 工作流的上传路径到 `dist/<platform>/`。Windows 签名和安装器步骤也使用 `dist/windows/`，不再通过复制回旧路径维持兼容。

CI 的缓存路径只迁移真正的工具缓存，例如 appimagetool；最终产物不作为缓存。工作流中的重命名、上传和 `if-no-files-found` 校验继续生效。

不保留长期双份最终产物。若某个外部发布流程尚未迁移，应在该流程中显式指定输入路径，而不是由打包脚本默认再复制一份到旧目录。

## 错误处理

- 版本缺失或格式非法：在构建前失败。
- 平台构建失败：不复制、不清理，保留日志和现场。
- 目标复制失败：不将部分文件宣称为成功产物，不清理。
- ZIP/APK 校验失败：删除或隔离未完成的目标临时文件，保留构建现场，返回失败。
- 清理失败：最终产物仍保留，但脚本报告清理未完成；不得误报整个打包失败原因。
- 并行构建占用：跳过清理并提示，不强制结束其他进程。

## 测试与验收

### 辅助模块测试

使用临时假项目和假产物，不运行真实编译：

- 版本解析、平台路径和 rN 扫描。
- 产物复制、非空校验和 ZIP 必需条目校验。
- 成功后只删除白名单临时目录。
- 构建失败、复制失败、校验失败时不清理。
- 拒绝根目录、`dist`、项目外路径和链接目录。
- 并行占用时跳过清理。
- 既有 Gradle/CMake 缓存保持存在。

### 平台回归

- `build_test.bat` 的默认、Android-only、Windows-only 和显式 rN 用法不变。
- Android APK 的 ABI、命名、zipfile 和 apksigner 校验通过。
- Windows ZIP 的目录树、必需条目和安装器输入/输出正确。
- Linux AppImage/tar.gz 生成并校验，appimagetool 不被重复下载。
- macOS DMG/ZIP 输出路径正确，部署行为不变。
- CI 上传路径和缓存路径与新结构一致。

### 最终验收

- 各平台最终产物只出现在 `dist/<platform>/`。
- 成功后白名单临时文件被清理，增量缓存保留。
- 失败时现场保留，无部分产物被误报成功。
- 连续多次打包不会累积 staging/AppDir/临时安装目录。
- 现有构建和测试功能不受影响。

## 非目标

- 不引入新的统一跨平台 CLI 或参数体系。
- 不改变签名证书、发布审批或应用部署策略。
- 不清理项目外的 Pub、Gradle、Android SDK、Visual Studio 或 Xcode 缓存。
- 不为了释放空间而强制每次完整重建。
