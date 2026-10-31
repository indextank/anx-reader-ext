# WebDAV 设置同步设计（v1）

- 日期：2026-10-31
- 状态：已批准（用户于对话中批准）
- 分支：`local/upstream-sync`

## 1. 背景与目标

现状：anx-reader 的 WebDAV 同步只覆盖 SQLite 数据库（阅读进度、书架、笔记）与书籍/封面文件；全部应用设置（SharedPreferences，100+ 键，含 AI 配置与各类服务密钥）不参与同步，仅存在于本地导出 zip 备份。WebDAV 凭据与 AI API key 均以明文存储于 SharedPreferences。

目标：

1. 同步范围扩展至全部用户设置（外观、阅读、TTS、翻译、AI 配置、账号凭据类），在现有书籍与阅读进度同步之上，默认开启、零配置生效。
2. 敏感数据（账号凭证、AI 密钥等）在传输与远端存储中全程密文，避免明文暴露。
3. 按设置类别（同步项）合并与冲突处理，last-write-wins，优先最新有效配置。
4. 提供开关允许用户排除特定类别。
5. 与现有 WebDAV 服务及旧版客户端完全兼容。
6. 同步失败不影响本地功能与既有数据库/文件同步，并给出清晰可读的提示。

非目标（本次不做）：

- 本地 SharedPreferences 的加密存储（引入 secure storage 为后续独立增强）。
- FTP/S3 等其他同步协议的设置同步（架构上随 `SyncClientBase` 天然可用，但不在本次验证范围）。
- 设置项级别的两两 diff 界面展示。

## 2. 方案选型

| 方案 | 结论 |
| --- | --- |
| A. 独立加密设置文件（采纳） | 远端新增 `anx/settings.v1.enc`，AES-256-GCM 整体加密的 JSON，按类别分块、各带 `updatedAt`；不动现有同步管线，旧客户端忽略新文件，解密/解析失败可整体放弃 |
| B. 设置写入 SQLite 随库同步（否决） | 被现有整库覆盖/方向二选一模型绑定，无法按类别合并；db 明文；需 bump 库版本，旧客户端拒收 |
| C. 逐 pref 键时间戳（否决） | 需侵入 `Prefs` 全部 setter（100+ 处）；键无类别元数据；相对类别粒度收益极小 |

## 3. 架构

新增三个单元（相互独立、均可单测）：

| 单元 | 文件 | 职责 |
| --- | --- | --- |
| `SettingsSyncCrypto` | `lib/service/sync/settings_sync_crypto.dart` | 密钥派生（PBKDF2）与 AES-256-GCM 加解密；无状态纯函数；二进制文件头封包 |
| `SettingsSyncCatalog` | `lib/service/sync/settings_sync_catalog.dart` | 类别到 pref 键的映射目录（精确键 + 前缀通配）；默认排除键；未映射键一律不同步 |
| `SettingsSyncManager` | `lib/service/sync/settings_sync_manager.dart` | 编排：本地快照采集 → 与远端合并 → 应用 → 上传；维护上次同步快照 |

挂接点：`Sync.syncData()`（`lib/providers/sync.dart`）中，在 `syncFiles()` 成功后调用 `SettingsSyncManager.sync(direction)`，包在独立 try-catch 中；设置同步的成败不改变数据库/文件同步的结果，也不抛出中断主流程。

### 数据流

```
本地 SharedPreferences
   │ SettingsSyncCatalog 采集（排除被排除类别与未映射键）
   ▼
本地类别快照 { category: { keys: {key: {type,value}}, updatedAt } }
   │ 与本地保存的「上次同步快照」比对内容 → 变化则 updatedAt = now
   ▼
远端 anx/settings.v1.enc ──解密──► 远端类别快照
   │
   ▼ 逐类别 last-write-wins 合并
   ├─► 应用到 SharedPreferences（类型校验，类型不符丢弃该项并记日志）
   └─► 合并结果重新加密上传（upload/both/download 后均回写远端，多设备收敛）
```

方向语义：

- `upload`：本地较新的类别推送至远端；远端较新的类别不动（下次 both/download 收敛）。
- `download`：远端较新的类别应用至本地；随后把合并结果回写远端。
- `both`：完整双向合并后回写。

说明：upload 方向也读远端文件（用于比对与保留未上传类别的远端原值）；读不到（网络失败）时 upload 直接失败并提示，不做盲覆盖。

## 4. 加密设计

- 算法：AES-256-GCM（认证加密），密钥经 PBKDF2-SHA256 派生：密码 = WebDAV 密码，salt = `"anx-reader-settings-sync-v1:" + WebDAV 用户名`，迭代 210,000 次，输出 256 bit。
- 密钥来源理由：同一 WebDAV 账号的多设备自动派生出相同密钥，满足「默认开启、零配置」；不引入用户额外输入。
- 文件格式（二进制）：

```
offset  size  字段
0       7     magic = "ANXSET1"
7       16    kdfSalt（当前等于用户名派生盐的原始随机部分；见下）
23      12    nonce（AES-GCM）
35      —     ciphertext || tag(16B)
```

kdfSalt 说明：v1 采用确定性盐以保证多设备同钥——盐 = `SHA-256("anx-reader-settings-sync-v1:" + WebDAV 用户名)` 的前 16 字节（定长），并写入文件头；读取时以文件头盐为准派生密钥，为未来切换随机盐（如独立同步密码）保留前向兼容。

- 加密范围：整个 payload（全部类别，含非敏感项）整体加密。理由：无需逐项判定敏感性；任何 WebDAV 服务（含纯 HTTP）上传输与存储均为密文。
- 解密失败（GCM 认证失败 / magic 不符 / 版本不识别）：保留本地、不修改远端、toast 提示一次并记日志；用户本地改动后下次上传会以当前密钥重写整个文件（改 WebDAV 密码后的自愈路径）。
- 本地密钥不落盘：每次同步时即时派生，用后丢弃。
- 依赖：`cryptography`（纯 Dart，全平台含 Web，无原生插件）。

## 5. 同步类别与排除开关

类别目录（未列入目录的键一律不同步，以保护设备相关项）：

| 类别 ID | 内容 | 含敏感数据 |
| --- | --- | --- |
| `appearance` | themeColor、themeMode、locale、trueDarkMode、eInkMode、书架样式（bookCoverWidth、bookshelfFolderStyle 等） | 否 |
| `reading` | readStyle、readTheme、font、readingRules、pageTurn*、annotationColor、readingInfo、volumeKeyTurnPage 等 | 否 |
| `tts` | ttsService、ttsVolume/Pitch/Rate、ttsVoiceModel_*、onlineTtsConfig_* | 是（服务 key） |
| `translate` | translateService、translateServiceConfig_*、translationMode、bookTranslationModes | 是（服务 key） |
| `ai` | aiProviders（含 API keys）、selectedAiService、aiPrompt_*、userPrompts、enabledAiTools、aiRpm、maxAiCacheCount、aiPanelWidth/Height、aiChatDisplayMode、旧 aiConfig_* | 是（API key） |
| `advanced` | chapterSplit*、searchEngines、customCSS、clearLogWhenStart、enableJsForEpub、statisticsDashboardTiles | 否 |

实现期修订（2026-10-31）：取消原「account」类别——盘点全部 pref 键后确认不存在归属其下的键（应用无登录账号体系，服务凭据已分别归入 tts/translate/ai），保留空类别违背 YAGNI。类别数为 6。

排除规则：

- 明确不同步的键：`webdavInfo`（WebDAV 凭据本身——没有它无法连接 WebDAV，同步零收益；覆盖正在使用的连接配置有真实风险）、`customStoragePath`、`httpProxy*`、`trustUserCertificates`、同步自身状态键（`settingsSync*`、`lastUploadBookDate`、`webdavStatus`、`autoSync`、`onlySyncWhenWifi`、`syncCompletedToast` 等）、`iapPurchaseStatus`、`iapLastCheckTime`、`__prefsBackupVersion`。
- 类别目录在代码中为显式清单：精确键集合 + 前缀模式列表；新增设置键需显式登记才会被同步（保守默认）。
- `account` 类别为显式列举的凭据类键集合（实现时按凭据命名约定逐个登记，如含 `api_key`/`token` 的服务配置键）；它不是自动兜底，无法归类的键一律不进入同步。

用户开关：

- `settingsSyncEnabled: bool`，默认 `true`（WebDAV 启用即生效）。
- `settingsSyncExcludedCategories: List<String>`，默认空（全部类别参与）。
- 被排除类别的行为：本地不采集；远端文件中该类别保留原值（解密远端 → 覆盖未排除类别 → 重加密上传）；下载应用时跳过。

## 6. 合并与冲突处理

- 时间戳：本地以单键 `settingsSyncState` 保存每个类别的上次同步内容哈希（canonical JSON 的 SHA-256）与 `updatedAt`。每次同步重新采集快照并与上次哈希比对：内容变化 → `updatedAt = now`；未变 → 沿用旧值。不依赖 `Prefs` 写钩子；哈希而非完整快照，避免双份存储敏感数据。
- 合并规则：远端 `updatedAt` 严格大于本地 → 取远端并写入本地；否则本地胜（相等取本地，避免时钟抖动回退）。即 last-write-wins、优先最新有效配置。
- 有效性校验：远端值以备份 schema 的 `{type, value}` 标签写入，应用时按类型分发到 `prefs.setBool/setInt/setDouble/setString/setStringList`；类型或结构不符的项丢弃并记日志，不中断整批。
- 首次同步（远端无该文件）→ 直接上传本地。
- 已知限制：多设备时钟漂移可能使 LWW 选出较旧的值；设置冲突为低风险场景，接受该限制。

## 7. 错误处理与兼容性

- 设置同步在 `syncData()` 中独立 try-catch：任何异常只 toast + 日志，不影响数据库/书籍文件同步与本地功能；不修改 `isSyncing` 语义之外的状态。
- 提示文案（l10n，arb 流程，中英先行）：
  - 解密失败：「设置同步失败：无法解密云端设置（WebDAV 密码可能已更改），已保留本地设置」
  - 网络/IO 失败：沿用现有同步失败文案风格
  - 类型不符项：静默跳过 + 日志
- 兼容性：远端仅新增 `anx/settings.v1.enc`；不触碰 `anx/database{N}.db` 与 `anx/data/*`；旧版客户端忽略新文件；新版客户端对旧远端（无该文件）按首次同步处理。任何标准 WebDAV 服务无需变更。

## 8. UI 变更

`lib/page/settings_page/sync.dart` 的「WebDAV」Section 下新增「设置同步」子区块：

- 总开关（`settingsSyncEnabled`）。
- 6 个类别排除开关（复用现有 `SwitchListTile` 风格；关闭即加入 `settingsSyncExcludedCategories`）。
- 简短说明：默认同步外观、阅读、朗读、翻译、AI 等设置；AI 密钥等敏感数据加密后同步。

## 9. 测试策略（TDD）

- `SettingsSyncCrypto`：加解密 roundtrip；错误密码解密抛认证错误；同输入派生密钥确定；magic/版本不匹配的防误读；文件头偏移正确。
- `SettingsSyncCatalog`：类别覆盖与优先级（精确 > 前缀 > 排除）；排除键不被采集；未映射键不同步。
- `SettingsSyncManager`：合并矩阵——本地新 / 远端新 / 相等 / 远端缺失 / 本地缺失 / 类别被排除 / 解密失败 / 类型不符；上传回写保留远端未排除类别原值；快照时间戳仅在内容变化时更新。沿用现有测试模式：`SharedPreferences.setMockInitialValues` + `initPrefs`，WebDAV 客户端以可注入方式 mock（内存远端）。

## 10. 决策记录

| 决策 | 选择 | 理由 |
| --- | --- | --- |
| 加密密钥来源 | PBKDF2 从 WebDAV 凭据派生 | 满足零配置；多设备同账号自动同钥 |
| 合并粒度 | 类别（7 类） | 平衡侵入性与需求；逐键时间戳成本高收益小 |
| webdavInfo | 不同步 | 无 WebDAV 凭据无法连接，同步零收益；覆盖在用配置有风险 |
| 解密失败 | 不覆盖远端 | 防止 bug 或误操作吞掉云端有效数据 |
| 加密范围 | 整 payload | 免逐项判定敏感性；实现简单可靠 |
| 本地存储加密 | 不做（后续增强） | 控制本次范围；云端与传输已密文 |
