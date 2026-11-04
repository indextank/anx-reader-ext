# 统一 dist 打包与选择性清理实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将 Android、Windows、Linux、macOS 最终产物统一输出到 `dist/<platform>/`，并在构建和校验成功后选择性清理临时文件，同时保留增量构建缓存。

**架构：** 使用 Python 标准库实现共享打包辅助模块，负责版本、路径、复制、ZIP 校验、白名单清理和路径安全；现有 BAT/PowerShell/Bash 入口继续负责平台构建。CI 和 Windows 安装器迁移到 dist，不保留双份最终产物。

**技术栈：** Python 3 标准库、BAT、PowerShell、Bash、Flutter 构建命令、GitHub Actions YAML。

**执行工作区：** `E:/openSource_project/anx-reader-ext-dist-packaging`，分支 `feature/dist-packaging`。主工作区存在其他未提交修改，不在主工作区直接实施。

**设计规格：** `docs/superpowers/specs/2026-11-04-dist-packaging-design.md`

---

## 文件结构与职责

- 创建 `scripts/packaging.py`：共享版本解析、dist 路径、产物复制/校验、白名单清理、路径安全和进程占用保护。
- 创建 `scripts/tests/test_packaging.py`：Python `unittest` 临时目录测试，不依赖项目生成代码或真实编译。
- 修改 `build_test.bat`：保留 `[rN] [all|android|windows]`，Android/Windows 最终产物输出 dist，成功后清理临时副本/staging。
- 修改 `scripts/build_windows.ps1`：移除 D:\inno 硬编码，使用共享辅助和 dist/windows。
- 修改 `scripts/build_windows_exe.ps1`：从 dist/windows 读取输入并输出安装器，清理 Inno 临时目录。
- 修改 `scripts/compile_windows_setup-inno.iss`：通过命令行定义传入 staging/output 路径，移除 D:\inno 硬编码。
- 修改 `scripts/build_linux_appimage.sh`：最终 AppImage/tar.gz 输出 dist/linux，工具缓存与临时 AppDir 分离。
- 创建 `scripts/package_macos.sh`：将既有 DMG/ZIP 输出 dist/macos 并清理临时源目录。
- 修改 `release_build.sh`：保留 macOS 构建和 `-d` 部署行为，调用打包辅助输出最终产物。
- 修改 `.github/workflows/build-{android,windows,linux,macos}.yaml`：上传、签名、重命名和缓存路径迁移到 dist。
- 修改 `.gitignore`：忽略根目录 `/dist/`。

## 执行前准备

- [ ] **步骤 1：确认隔离分支**

```bash
cd "E:/openSource_project/anx-reader-ext-dist-packaging"
git status --short --branch
git log -2 --oneline
```

预期：分支 `feature/dist-packaging`，工作区干净，包含规格提交 `6742e3aa`。

- [ ] **步骤 2：确认 Python 测试环境**

```bash
python --version
python -I -m unittest --help
```

预期：Python 3 可用，unittest 可运行。测试脚本放在 `scripts/tests/`，读取的临时假项目由测试自行创建；运行时使用 `python -I`，不从下载目录或临时产物目录启动解释器。

---

### 任务 1：共享打包辅助与安全清理

**文件：**
- 创建：`scripts/packaging.py`
- 创建：`scripts/__init__.py`、`scripts/tests/__init__.py`（空包标记）
- 创建：`scripts/tests/test_packaging.py`
- 修改：`.gitignore`

- [ ] **步骤 1：编写版本、路径和复制校验失败测试**

```python
import tempfile
import unittest
import zipfile
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts import packaging

class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / 'pubspec.yaml').write_text('version: 1.2.3+42\n')

    def tearDown(self):
        self.temp.cleanup()

    def test_version_and_platform_paths(self):
        self.assertEqual(packaging.read_version(self.root), '1.2.3')
        self.assertEqual(
            packaging.platform_dist(self.root, 'android'),
            self.root / 'dist' / 'android',
        )

    def test_copy_artifact_requires_nonempty_file(self):
        source = self.root / 'build' / 'app.apk'
        source.parent.mkdir(parents=True)
        source.write_bytes(b'apk')
        target = packaging.copy_artifact(source, self.root, 'android', 'app.apk')
        self.assertEqual(target.read_bytes(), b'apk')
        with self.assertRaises(packaging.PackagingError):
            packaging.copy_artifact(source, self.root, 'android', '../outside')

    def test_zip_validation_checks_integrity_and_required_entries(self):
        archive = self.root / 'app.zip'
        with zipfile.ZipFile(archive, 'w') as output:
            output.writestr('anx_reader.exe', b'exe')
            output.writestr('data/icudtl.dat', b'icu')
        packaging.validate_zip(archive, ['anx_reader.exe', 'icudtl.dat'])
        with self.assertRaises(packaging.PackagingError):
            packaging.validate_zip(archive, ['missing.dll'])
```

测试文件通过 `Path(__file__).resolve().parents[2]` 将项目根目录显式加入 `sys.path` 后导入 `scripts.packaging`；不从临时假项目目录运行解释器。`scripts/__init__.py` 和 `scripts/tests/__init__.py` 作为空包标记一并创建，保证 `python -I -m unittest` 可导入。

- [ ] **步骤 2：运行测试确认辅助模块不存在**

```bash
python -I -m unittest scripts.tests.test_packaging -v
```

预期：FAIL，无法导入 `scripts.packaging`。

- [ ] **步骤 3：实现最小版本、复制和 ZIP 校验**

公共接口：

```python
class PackagingError(RuntimeError): ...
def read_version(root: Path) -> str: ...
def platform_dist(root: Path, platform: str) -> Path: ...
def copy_artifact(source: Path, root: Path, platform: str, name: str) -> Path: ...
def validate_zip(path: Path, required_entries: list[str]) -> None: ...
```

`copy_artifact` 只允许平台目录内的普通文件名，拒绝绝对路径、`..`、空文件和缺失源文件；先复制到同目录临时文件，再原子替换目标。`validate_zip` 同时执行 `testzip()` 和必需条目检查。

- [ ] **步骤 4：编写白名单清理和路径安全失败测试**

```python
def test_cleanup_only_removes_registered_build_temp_paths(self):
    temp_dir = self.root / 'build' / 'windows' / 'test-stage'
    temp_dir.mkdir(parents=True)
    (temp_dir / 'temp.txt').write_text('temp')
    cache = self.root / 'build' / 'windows' / 'x64' / 'CMakeCache.txt'
    cache.parent.mkdir(parents=True)
    cache.write_text('cache')
    packaging.cleanup_paths(self.root, [temp_dir])
    self.assertFalse(temp_dir.exists())
    self.assertTrue(cache.exists())

def test_cleanup_rejects_root_dist_outside_and_links(self):
    for target in [self.root, self.root / 'dist', self.root.parent]:
        with self.assertRaises(packaging.PackagingError):
            packaging.cleanup_paths(self.root, [target])
```

补充不存在路径、文件/目录、删除失败和符号链接测试。清理接口只接受 `root/build/<platform>/` 下登记的临时路径，拒绝根目录、dist、项目外路径和链接目录。

- [ ] **步骤 5：实现清理与占用保护**

```python
def cleanup_paths(root: Path, paths: list[Path]) -> None: ...
def ensure_no_active_build(root: Path, current_pid: int | None = None) -> None: ...
```

`ensure_no_active_build` 使用项目锁文件 `build/.packaging.lock` 和当前进程 PID，不扫描或终止其他进程。入口在构建前创建锁并写入 PID，成功/失败均在 finally 中释放；发现其他存活 PID 时拒绝开始或跳过清理。测试用当前 PID 和不可能存活的 PID 验证，不依赖 Windows POSIX 信号差异。

- [ ] **步骤 6：运行辅助测试并提交**

```bash
python -I -m unittest scripts.tests.test_packaging -v
git add scripts/packaging.py scripts/__init__.py scripts/tests/__init__.py scripts/tests/test_packaging.py .gitignore
git commit -m "feat(build): add safe dist packaging helpers"
```

预期：全部 PASS，`.gitignore` 新增 `/dist/`。

---

### 任务 2：Android 与 Windows 测试包入口

**文件：**
- 修改：`build_test.bat`
- 修改：`scripts/build_windows.ps1`
- 修改：`scripts/build_windows_exe.ps1`
- 修改：`scripts/compile_windows_setup-inno.iss`
- 创建：`scripts/tests/test_packaging_scripts.py`

- [ ] **步骤 1：编写 BAT/PowerShell 静态契约测试**

```python
def test_build_test_uses_dist_and_preserves_cli(self):
    source = (ROOT / 'build_test.bat').read_text()
    self.assertIn('build_test.bat [rN]', source)
    self.assertIn('dist\\android', source)
    self.assertIn('dist\\windows', source)
    self.assertIn('packaging.py', source)
    self.assertIn('apksigner', source)
    self.assertIn('--no-tree-shake-icons', source)

def test_windows_scripts_have_no_hardcoded_inno_paths(self):
    for name in ['build_windows.ps1', 'build_windows_exe.ps1']:
        source = (ROOT / 'scripts' / name).read_text()
        self.assertNotIn('D:\\inno', source)
        self.assertIn('dist\\windows', source)
```

静态契约只作为冒烟检查，真实复制/校验/清理由任务 1 的单元测试和后续构建验证覆盖。

- [ ] **步骤 2：运行契约测试确认旧脚本失败**

```bash
python -I -m unittest scripts.tests.test_packaging_scripts -v
```

预期：FAIL，旧脚本仍使用 build 输出和 D:\inno。

- [ ] **步骤 3：迁移 build_test.bat**

保留参数和构建命令：

- rN 扫描改为 `dist/android` 与 `dist/windows`。
- Android 最终文件复制到 `dist/android`，沿用 zipfile/apksigner 校验。
- Windows staging 留在 `build/windows/test-stage`，最终 ZIP 输出 `dist/windows`。
- 只有全部目标构建和校验成功后，调用共享清理删除本次 staging 和不再需要的重命名临时副本。
- 构建/复制/校验失败直接退出，不清理。
- 保留现有环境变量、版本读取、ABI、universal 包和日志。

- [ ] **步骤 4：迁移 Windows PowerShell 与 Inno**

- `build_windows.ps1` 使用项目根目录和 `build/windows/packaging-stage`，通过共享辅助输出并校验 `dist/windows/app.zip`。
- `build_windows_exe.ps1` 接受 `-InputZip` 参数，默认 `dist/windows/app.zip`；CI 在签名或 alpha 准备后将实际存在的 ZIP 路径显式传入，不依赖固定文件名。解压到项目 staging，调用 ISCC 时传入 `MyPackagingDir` 和 `MyOutputDir`，最终 EXE 输出 `dist/windows/app.exe`。
- `compile_windows_setup-inno.iss` 使用 `#ifndef` 提供路径默认值或要求命令行定义，Source、OutputDir、SetupIconFile 不再硬编码 D:\inno。
- 成功后清理 staging，失败保留。

- [ ] **步骤 5：运行脚本测试和真实 Windows/Android 验证**

```bash
python -I -m unittest scripts.tests.test_packaging scripts.tests.test_packaging_scripts -v
cmd.exe //d //c "E:\openSource_project\anx-reader-ext-dist-packaging\build_test.bat"
```

预期：辅助/契约测试全过；真实构建生成 dist/android 和 dist/windows，校验通过，staging 清理，Gradle/CMake 缓存保留。若环境或并行构建阻塞，记录具体阻塞，不伪称构建通过。

- [ ] **步骤 6：提交 Windows/Android 改造**

```bash
git add build_test.bat scripts/build_windows.ps1 scripts/build_windows_exe.ps1 scripts/compile_windows_setup-inno.iss scripts/tests/test_packaging_scripts.py
git commit -m "feat(build): output Android and Windows packages to dist"
```

---

### 任务 3：Linux、macOS 与 CI 路径迁移

**文件：**
- 修改：`scripts/build_linux_appimage.sh`
- 创建：`scripts/package_macos.sh`
- 修改：`release_build.sh`
- 修改：`.github/workflows/build-android.yaml`
- 修改：`.github/workflows/build-windows.yaml`
- 修改：`.github/workflows/build-linux.yaml`
- 修改：`.github/workflows/build-macos.yaml`
- 修改：`scripts/tests/test_packaging_scripts.py`

- [ ] **步骤 1：编写 Linux/macOS/CI 契约失败测试**

```python
def test_all_platform_workflows_upload_from_dist(self):
    for platform in ['android', 'windows', 'linux', 'macos']:
        source = (ROOT / '.github' / 'workflows' / f'build-{platform}.yaml').read_text()
        self.assertIn(f'dist/{platform}/', source)
        self.assertNotIn('build/app/outputs/flutter-apk/*.apk', source)

def test_linux_tool_cache_is_not_final_dist(self):
    source = (ROOT / 'scripts' / 'build_linux_appimage.sh').read_text()
    self.assertIn('dist/linux', source)
    self.assertIn('APPIMAGETOOL', source)
    self.assertNotIn('FINAL_DIR="$ROOT_DIR/build/linux"', source)
```

检查 Windows 签名和 EXE 路径、Linux appimagetool 缓存、macOS DMG/ZIP 上传均使用 dist；不保留旧最终产物路径。

- [ ] **步骤 2：运行契约测试确认旧路径失败**

```bash
python -I -m unittest scripts.tests.test_packaging_scripts -v
```

预期：FAIL，CI 和 Linux/macOS 仍使用旧路径。

- [ ] **步骤 3：迁移 Linux 打包**

- 最终 AppImage/tar.gz 输出 `dist/linux`。
- staging/AppDir 留在 `build/linux/packaging/`，成功后删除。
- appimagetool 默认放 `build/linux/tools/` 或用户缓存，CI 缓存路径同步；不得被 AppDir 清理删除。
- 保留 SKIP_FLUTTER_BUILD、ARCH、VERSION 和现有 bundle 校验。

- [ ] **步骤 4：新增 macOS 打包辅助并保留部署**

`package_macos.sh` 接受既有 Release 目录中的 DMG/ZIP，复制并校验到 `dist/macos`，清理本次 DMG 临时源目录。`release_build.sh macos` 构建后调用它；`-d` 仍只负责部署到 `/Applications`，不因 dist 改造自动部署。

CI macOS 在现有 hdiutil/ditto 后调用辅助脚本，上传 `dist/macos/*.dmg` 和 `.zip`。

- [ ] **步骤 5：迁移四个 CI 工作流**

- Android 上传 `dist/android/*.apk`。
- Windows 上传、签名输入/输出、alpha 准备、重命名和最终上传统一 `dist/windows/`。
- Linux 上传 `dist/linux/*`，appimagetool 缓存指向工具目录。
- macOS 上传 `dist/macos/*`。
- 保留 `if-no-files-found: error` 和签名流程，不修改发布审批。

- [ ] **步骤 6：运行脚本测试、Shell 语法和可用平台验证**

```bash
python -I -m unittest scripts.tests.test_packaging scripts.tests.test_packaging_scripts -v
bash -n scripts/build_linux_appimage.sh scripts/package_macos.sh release_build.sh
```

预期：全部 PASS。Linux/macOS 真实构建只在对应环境可用时执行；不可用时明确记录未执行，不以静态检查冒充构建。

- [ ] **步骤 7：提交 Linux/macOS/CI 改造**

```bash
git add scripts/build_linux_appimage.sh scripts/package_macos.sh release_build.sh .github/workflows/build-android.yaml .github/workflows/build-windows.yaml .github/workflows/build-linux.yaml .github/workflows/build-macos.yaml scripts/tests/test_packaging_scripts.py
git commit -m "feat(build): unify desktop packages and CI outputs"
```

---

### 任务 4：整体回归与分支收尾

**文件：**
- 验证本计划全部变更；不修改主工作区其他未提交文件。

- [ ] **步骤 1：运行全部脚本测试**

```bash
python -I -m unittest discover -s scripts/tests -v
```

预期：全部 PASS，覆盖版本、复制、ZIP、清理、路径安全、锁和平台契约。

- [ ] **步骤 2：检查脚本和 YAML 语法**

```bash
bash -n scripts/build_linux_appimage.sh scripts/package_macos.sh release_build.sh
python -I -c "import yaml; from pathlib import Path; [yaml.safe_load(p.read_text()) for p in Path('.github/workflows').glob('build-*.yaml')]"
```

若 PyYAML 不可用，使用现有 YAML 解析工具或记录未执行，不安装新依赖仅为测试。

- [ ] **步骤 3：检查差异和范围**

```bash
git status --short
git diff --check 6742e3aa..HEAD
git diff --stat 6742e3aa..HEAD
```

预期：仅本计划文件；无真实产物、临时 staging 或生成缓存进入 Git。

- [ ] **步骤 4：最终验收**

- 各平台最终产物只在 dist/<platform>/。
- 成功后白名单临时文件清理，增量缓存保留。
- 失败时现场保留，无部分产物误报成功。
- 连续多次打包不累积 staging/AppDir/Inno 临时目录。
- 现有构建命令和测试不受影响。

- [ ] **步骤 5：两阶段审查与合回**

每个任务先规格审查、再代码质量审查；所有 Critical/Important 修复后，进行整体审查。合回主工作区前检查未提交改动，若路径重叠则停止并报告，不 stash、不 clean、不覆盖。合并后在主工作区重新运行脚本测试和可用的平台构建验证。

---

## 计划自检结果

- 四个现有平台、dist 输出、rN、签名、CI 和安装器路径均有对应任务。
- 成功校验后清理、失败保留、路径安全、并行锁和增量缓存保留均有单元测试。
- 共享辅助只负责通用打包逻辑，平台构建命令仍由现有入口负责。
- 所有生产任务先写失败测试再实现，任务独立提交，主工作区未提交改动不被覆盖。
