# Yomink 项目整体 Review

> 本文档作为后续 review 与修复的基准文件。当前状态字段用于持续更新：`待处理`、`处理中`、`已修复`、`已验证`、`暂缓`。
> 本次 review 忽略暂存区/工作树里的 `docs/review-notes.md` 删除状态。

## 项目结构地图

```text
Yomink-ios-app/
├── .github/workflows/
│   └── build-unsigned-ipa.yml        # GitHub Actions: 解析依赖、Debug 模拟器构建/测试、Release unsigned IPA
├── docs/
│   ├── PROJECT_DEVELOPMENT_PLAN.md   # 项目开发计划
│   └── review-all.md                 # 本 review 基准文档
├── Yomink/
│   ├── App/
│   │   ├── YominkApp.swift           # App 入口
│   │   ├── AppEnvironment.swift      # 启动状态、依赖注入环境
│   │   ├── AppServices.swift         # FileStore/Database/Repository/ImportService 组装
│   │   ├── HostingControllerHomeIndicatorBridge.swift
│   │   ├── Info.plist
│   │   ├── Assets.xcassets/
│   │   └── Resources/zh-Hans.lproj/Localizable.strings
│   ├── Domain/
│   │   ├── Models/                   # Book、Chapter、Bookmark、ReaderSettings、ReadingProgress 等领域模型
│   │   └── Services/                 # LibraryRepository 协议、ImportService、PreviewLibraryRepository
│   ├── Data/
│   │   ├── Database/                 # AppDatabase 迁移、GRDBLibraryRepository、Record 映射
│   │   ├── FileStore/                # Documents/Books/Application Support 路径与删除 staging
│   │   ├── ChapterIndexer/           # TXT 章节识别与超大章节切分
│   │   └── TextDecoder/              # UTF-8/GB18030/GBK/GB2312 解码
│   └── Presentation/
│       ├── Library/                  # 书架主界面、分组/历史/存储/随机等页面、导出服务
│       ├── Reader/                   # UIKit 阅读器、分页、过滤、更多面板
│       └── Sidebars/                 # 左右侧边栏
├── YominkTests/
│   ├── AppDatabaseConstraintsTests.swift
│   └── ChapterIndexerTests.swift
└── Yomink.xcodeproj/                 # Xcode 工程与 SwiftPM resolved
```

## 核心模块职责

- App 层：创建应用入口、初始化文件存储/数据库/仓储/导入服务，并通过 `AppEnvironment` 将启动状态注入 SwiftUI。
- Domain 层：定义书籍、章节、书签、阅读进度、阅读设置等业务模型；`LibraryRepository` 规定书架、阅读器、设置、历史、搜索等数据访问契约。
- Data 层：`AppDatabase` 负责 GRDB 迁移、外键、数据边界保护和遗留章节修复；`GRDBLibraryRepository` 实现持久化读写；`AppFileStore` 管理正文文件路径和删除 staging；`ImportService` 完成 TXT 读取、解码、去重、写入正文和生成导入草稿。
- Presentation/Library：书架列表/网格、导入、搜索、分组、历史、随机抽书、存储管理、导出和删除流程。
- Presentation/Reader：UIKit 高性能阅读器，负责分页/滚动/仿翻页、进度保存、书签、目录、过滤规则、阅读设置、自动阅读、状态栏/手势管理。
- Tests：目前覆盖数据库边界归一化、遗留章节修复、删除 staging、导出文件名去重、阅读历史 limit、搜索转义和重复导入。

## 可运行检查命令

> Windows 本机无法构建 iOS 工程；以下构建/测试命令需在 macOS + Xcode 上运行。Windows PowerShell 5 读取 UTF-8 中文可能显示乱码，审查中文文件建议用 `rg`、Node/Python UTF-8 读取，或先切换终端 UTF-8。

```sh
xcodebuild -resolvePackageDependencies -project Yomink.xcodeproj -scheme Yomink
xcodebuild build -project Yomink.xcodeproj -scheme Yomink -configuration Debug -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Yomink.xcodeproj -scheme Yomink -configuration Debug -destination "platform=iOS Simulator,name=iPhone 16" CODE_SIGNING_ALLOWED=NO
xcodebuild archive -project Yomink.xcodeproj -scheme Yomink -configuration Release -destination "generic/platform=iOS" -archivePath build/Yomink.xcarchive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" AD_HOC_CODE_SIGNING_ALLOWED=NO
```

本地只读辅助检查：

```sh
rg --files
rg -n "TODO|FIXME|print\\(|debugPrint\\(|NSLog\\(|#warning|try!|as!" Yomink YominkTests
rg -n "deleteBook|deleteBooks|saveReadingProgress|Task\\.detached|fatalError" Yomink YominkTests
```

## 初步风险列表

### 必须修

| 编号 | 模块 | 文件行号 | 严重程度 | 问题 | 建议处理方式 | 当前状态 |
| --- | --- | --- | --- | --- | --- | --- |
| R-001 | Reader/进度保存 | `Yomink/Presentation/Reader/ReaderHostView.swift:429`, `Yomink/Presentation/Reader/ReaderHostView.swift:2757` | 高 | `saveProgressImmediately()` 取消 `saveTask` 后创建了一个未赋值给 `saveTask` 的新 `Task`。`deinit` 只取消旧 `saveTask`，退出阅读器或对象释放时无法跟踪这次立即保存，可能出现最后阅读位置丢失；同类问题也出现在 `saveSettingsImmediately()`。 | 将立即保存任务赋值给对应属性，或抽出统一保存入口；退出/后台时保证最后一次进度和设置保存完成或至少可追踪。补充“退出阅读器后仍保存最后进度”的单元/集成测试。 | 已修复，待 Xcode 验证 |
| R-002 | Reader/空章节与过滤 | `Yomink/Presentation/Reader/ReaderHostView.swift:6272`, `Yomink/Presentation/Reader/ReaderHostView.swift:6317`, `Yomink/Presentation/Reader/ReaderHostView.swift:6349` | 高 | 当过滤规则把章节内容全部过滤为空时，页面显示占位文本，但 `pageStartOffset` 使用当前偏移，`pageEndOffset` 直接设为章节末尾。若当前偏移已经等于章节末尾，`endAbsoluteOffset > startAbsoluteOffset` 不成立并抛出 `emptyPage`，用户可能打不开或跳转到空章节末尾时报错。 | 对空显示章节单独生成稳定占位页：起点 clamp 到章节有效范围，终点至少前进 1 或允许占位页不依赖真实字节跨度；补充过滤后空章节、章节末尾恢复进度的测试。 | 已修复，待 Xcode 验证 |
| R-003 | Library/导出 | `Yomink/Presentation/Library/LibraryDedicatedPages.swift:2856`, `Yomink/Presentation/Library/LibraryDedicatedPages.swift:2876`, `Yomink/Presentation/Library/LibraryView.swift:1128` | 中高 | `BookExportService.exportURLs` 每次先清理全局临时目录 `YominkExports`，分享面板完成后也清理同一目录。若同时从书架多选导出和存储页单本导出，或分享面板尚未完成时再次导出，可能互相删除待分享文件。 | 为每次导出创建带 UUID 的独立临时目录，并让 payload 持有该目录，在对应分享完成后只清理自己的目录。补充并发/连续导出测试。 | 已修复，待 Xcode 验证 |

### 建议修

| 编号 | 模块 | 文件行号 | 严重程度 | 问题 | 建议处理方式 | 当前状态 |
| --- | --- | --- | --- | --- | --- | --- |
| R-004 | Data/仓储接口 | `Yomink/Data/Database/GRDBLibraryRepository.swift:901`, `Yomink/Data/Database/GRDBLibraryRepository.swift:907`, `Yomink/Presentation/Library/LibraryView.swift:1370`, `Yomink/Presentation/Library/LibraryDedicatedPages.swift:1858` | 中 | `deleteBook(s)` 仓储方法只删除数据库记录，文件删除依赖 UI 层先 stage 再清理。当前主流程做了 staging，但接口名称容易被其他调用方误用，导致正文文件孤儿或数据库/文件不一致。 | 将“删除书籍”用例上移为服务层，统一封装文件 staging + DB 删除 + 回滚；或在协议命名中明确 `deleteBookRecord`。补充从服务层删除的测试。 | 待处理 |
| R-005 | Presentation/结构 | `Yomink/Presentation/Reader/ReaderHostView.swift:1`, `Yomink/Presentation/Library/LibraryDedicatedPages.swift:1`, `Yomink/Presentation/Library/LibraryView.swift:1`, `Yomink/Presentation/Reader/ReaderMoreViewControllers.swift:1` | 中 | 单文件体量过大：阅读器 6641 行、DedicatedPages 4002 行、LibraryView 2231 行、ReaderMore 1843 行。分页、设置、手势、导出、存储扫描、历史 UI 等职责混在少数文件里，后续修改容易引入回归，也不利于测试。 | 按职责拆分：Reader 分为控制器、分页器、设置面板、自动阅读、手势/状态栏、页面 Cell；Library 分为 ViewModel、导入/导出、搜索、书架组件、存储页面。先做无行为变更拆分并跑测试。 | 待处理 |
| R-006 | Test/构建检查 | `.github/workflows/build-unsigned-ipa.yml:47`, `.github/workflows/build-unsigned-ipa.yml:54`, `.github/workflows/build-unsigned-ipa.yml:63` | 中 | CI 只有依赖解析、构建和单元测试，没有 SwiftLint/SwiftFormat、静态分析、未使用代码检查，也没有 UI/阅读器关键路径测试。大型 UIKit/SwiftUI 文件里的手势、导航、分页、空章节、导出并发风险难被当前测试发现。 | 增加 `xcodebuild analyze` 或等价静态分析步骤；引入格式/ lint 规则；补充 ReaderPaginator/ReaderTextFilter 的纯逻辑测试和关键 UI 流程测试。 | 待处理 |
| R-007 | Data/导入性能 | `Yomink/Domain/Services/ImportService.swift:177`, `Yomink/Domain/Services/ImportService.swift:184`, `Yomink/Domain/Services/ImportService.swift:239`, `Yomink/Data/ChapterIndexer/ChapterIndexer.swift:55` | 中 | 导入会一次性读完整 TXT、解码成完整 String、再生成完整 UTF-8 Data、再逐字符扫描章节和字数。超大 TXT 在低内存设备上可能出现卡顿或内存峰值过高。 | 为可接受文件大小设上限或导入前提示；逐步评估流式 hash/解码/章节扫描；至少增加大文件导入性能测试和内存观察。 | 待处理 |
| R-008 | App/本地化与可访问性 | `Yomink/Presentation/Library/LibraryView.swift:98`, `Yomink/Presentation/Library/LibraryView.swift:118`, `Yomink/Presentation/Library/LibraryView.swift:181` | 中低 | 多处 `Text("key")`、`accessibilityLabel(Text("key"))` 依赖 SwiftUI 自动本地化，UIKit 侧则多为 `NSLocalizedString`。混用本身可工作，但 review/重构时容易误把 key 当展示文案，也不利于统一检查缺失本地化。 | 约定 SwiftUI 文案写法，关键可访问性文案使用 `LocalizedStringKey` 或封装 helper；增加本地化 key 完整性检查。 | 待处理 |

### 可选优化

| 编号 | 模块 | 文件行号 | 严重程度 | 问题 | 建议处理方式 | 当前状态 |
| --- | --- | --- | --- | --- | --- | --- |
| R-009 | Reader/残留注释可读性 | `Yomink/Presentation/Reader/ReaderHostView.swift:365`, `Yomink/Presentation/Reader/ReaderHostView.swift:450`, `Yomink/Presentation/Reader/ReaderHostView.swift:490` | 低 | 文件内容是 UTF-8，但 Windows PowerShell 5 默认读取时中文注释会显示乱码；这不影响 Xcode 构建，但影响 Windows 环境审查和协作。 | 保持文件 UTF-8；Windows 审查命令使用 UTF-8 读取。必要时将关键中文注释改为 ASCII/英文，减少终端编码干扰。 | 待处理 |
| R-010 | Data/重复设置读写 | `Yomink/Data/Database/GRDBLibraryRepository.swift:620`, `Yomink/Data/Database/GRDBLibraryRepository.swift:652`, `Yomink/Data/Database/GRDBLibraryRepository.swift:674`, `Yomink/Data/Database/GRDBLibraryRepository.swift:729`, `Yomink/Data/Database/GRDBLibraryRepository.swift:761` | 低 | `LibrarySettings`、`RandomPickerState`、`ReaderSettings` 的 JSON 读写逻辑高度重复。 | 抽出泛型 app setting 读写 helper，统一日志、UTF-8、默认值和 normalized 处理。 | 待处理 |
| R-011 | Tests/测试文件结构 | `YominkTests/AppDatabaseConstraintsTests.swift:1` | 低 | 一个测试文件包含数据库约束、领域模型、文件删除 staging、导出、历史、搜索、重复导入等多个测试类，后续定位和维护成本会升高。 | 按模块拆成 `DatabaseConstraintsTests`、`DomainModelTests`、`AppFileStoreTests`、`BookExportServiceTests`、`ImportServiceTests`。 | 待处理 |
| R-012 | Tooling/Git 安全目录 | 仓库根目录 | 低 | 当前环境执行普通 `git status` 会因 dubious ownership 失败，需要命令内添加 `-c safe.directory=E:/GithubRepo/Yomink-ios-app`。这不影响代码，但会影响自动化脚本和本地 review 流程。 | 在受信任环境配置 safe.directory，或在本地工具文档中说明；不要把用户级配置写入仓库。 | 待处理 |

## 构建、测试、类型检查风险

- 本次在 Windows 环境未运行 Xcode 构建/测试，iOS 构建需 macOS + Xcode。
- GitHub Actions 使用 `macos-15`、Xcode 默认版本和 iPhone 16 模拟器；如果 runner 镜像变化，模拟器名称可能需要调整。
- 工程 `SWIFT_VERSION = 5.0`，但代码使用 async/await、SwiftUI、GRDB 7；实际由现代 Xcode 编译。建议确认是否需要显式升级工程 Swift Language Version，以免未来工具链提示混乱。
- 当前没有 lint/format/static analyze gate；无用代码、重复代码、UI 状态竞争主要靠人工 review 发现。
- 现有测试偏数据层，阅读器分页、过滤、导航、手势、导出分享生命周期缺少自动化覆盖。

## 残留调试代码、无用文件、无用依赖检查结论

- 未发现 `print(`、`debugPrint(`、`NSLog(`、`TODO`、`FIXME`、`#warning` 残留。
- `fatalError("init(coder:) has not been implemented")` 均位于 `@available(*, unavailable)` 的 UIKit coder 初始化器，属于常规写法，暂不作为问题。
- SwiftPM 仅发现 GRDB 7.10.0，当前数据库层实际使用，未发现明显无用依赖。
- `docs/review-notes.md` 处于删除状态，本次按用户要求忽略。
