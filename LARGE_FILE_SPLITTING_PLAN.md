# 大文件拆分规划

> 本文档是本仓库的大文件拆分活文档，独立于 `docs/large-file-splitting-plan.md`。
> 后续每次代码改动前必须先阅读本文档；改动完成后必须同步更新本文档中的状态、记录或结论。

## 维护规则

- 改动前先阅读本文档，确认当前优先级、拆分边界和未完成事项。
- 改动后更新本文档，至少记录：日期、改动文件、拆分结果、验证方式、遗留风险。
- 不把纯格式化、临时调试、生成物清理混入拆分提交。
- 拆分优先做无行为变更：先移动代码、补齐访问控制和编译验证，再考虑职责下沉。
- 单次拆分控制在一个明确边界内，避免同时改多个业务方向。
- 若发现本文档与实际代码不一致，以代码为准，并立即修正文档。

## 当前扫描基线

扫描日期：2026-06-06

范围：忽略 `docs/`。

Swift 文件概况：

| 指标 | 数值 |
| --- | ---: |
| Swift 文件数 | 71 |
| Swift 总行数 | 21,785 |
| 超过 300 行 | 22 |
| 超过 500 行 | 10 |
| 超过 1000 行 | 2 |

最大 Swift 文件：

| 优先级 | 文件 | 行数 | 判断 |
| --- | --- | ---: | --- |
| P0 | `Yomink/Presentation/Reader/CollectionReaderViewController.swift` | 4,098 | 明显巨型控制器，混合 UI 组装、分页、手势、进度、书签、自动阅读、设置面板、导航 |
| P1 | `Yomink/Presentation/Library/LibraryView.swift` | 1,109 | SwiftUI 入口视图过重，混合抽屉、书架、路由、导入、选择操作 |
| P1 | `YominkTests/AppDatabaseConstraintsTests.swift` | 960 | 多个测试主题挤在同一文件，适合按测试域拆分 |
| P2 | `Yomink/Data/Database/GRDBLibraryRepository.swift` | 921 | 仓储实现覆盖书籍、标签、分组、书签、进度、设置、导入 |
| P2 | `Yomink/Data/Database/AppDatabase.swift` | 831 | 数据库迁移和遗留修复逻辑偏重 |
| P3 | `Yomink/Presentation/Reader/ReaderContentsViewController.swift` | 739 | 可后续按 UI、搜索/跳转、数据绑定拆 |
| P3 | `Yomink/Presentation/Reader/ReaderContentSearchViewController.swift` | 710 | 可后续按搜索状态、结果列表、导航动作拆 |
| P3 | `Yomink/Presentation/Library/RandomBookPickerPage.swift` | 618 | 可后续拆页面主体和选择逻辑 |
| P3 | `Yomink/Presentation/Library/StorageManagementComponents.swift` | 606 | 组件集合文件，后续按组件族拆 |
| P3 | `Yomink/Domain/Services/ImportService.swift` | 593 | 导入流程可按单本导入、批量导入、去重/校验拆 |

非源码大文件观察：

- `tmp/icon-previews/` 下有多张 100KB 以上图片且当前被 Git 跟踪。
- 若这些图片只是临时预览，后续应单独做一次清理提交：把 `tmp/` 加入 `.gitignore`，并移出已跟踪临时文件。
- 若这些图片是设计资产，应迁移到明确的资产或设计目录，避免继续放在 `tmp/`。

## 拆分原则

- 优先拆文件边界，再拆对象职责。先用 `extension` 分文件降低冲突和阅读成本。
- 保持现有公开 API 和行为不变，避免在拆分提交里顺手重构业务逻辑。
- 新文件命名采用 `TypeName+Concern.swift`，例如 `CollectionReaderViewController+Paging.swift`。
- UIKit 控制器拆分时，先按事件/生命周期/委托协议/功能面板分组。
- SwiftUI 视图拆分时，优先提取稳定子视图，其次才拆私有 computed view。
- 数据层拆分时，优先按协议能力和表域分 `extension`，保留共享 helper。
- 测试拆分时，按测试主题拆文件，避免改变测试断言本身。

## P0：阅读器控制器拆分

目标文件：`Yomink/Presentation/Reader/CollectionReaderViewController.swift`

当前状态：

- 已拆出 `Yomink/Presentation/Reader/CollectionReaderViewController+CollectionView.swift`。
- 已拆出 `Yomink/Presentation/Reader/CollectionReaderViewController+Gestures.swift`。
- 已拆出 `Yomink/Presentation/Reader/CollectionReaderViewController+AutoRead.swift`。
- `CollectionReaderViewController.swift` 已从 4,098 行降到 3,529 行。
- `CollectionReaderViewController+AutoRead.swift` 当前 401 行，包含自动阅读面板、速度、display link、暂停恢复和自动阅读拖拽减速。
- 为支持扩展文件访问，已将部分原 `private` 成员放宽为模块内访问；后续职责拆稳后可再评估是否用更小的状态对象收回可见性。

当前问题：

- 单文件 4,098 行，是仓库中最大 Swift 文件。
- 一个 `UIViewController` 承担阅读器主流程、页面加载、布局、设置、自动阅读、书签、进度保存、导航和手势。
- 文件内缺少稳定分段标记，定位改动成本高。

建议拆分顺序：

1. `CollectionReaderViewController+CollectionView.swift`
   - 移动 `UICollectionViewDataSource`、`UICollectionViewDelegateFlowLayout`、`UIScrollViewDelegate` 方法。
   - 风险较低，边界清晰。
   - 状态：已完成主体拆分；自动阅读减速相关的 `scrollViewWillEndDragging` 已随 AutoRead 拆分移出。

2. `CollectionReaderViewController+Gestures.swift`
   - 移动点击、滑动、边缘返回、手势代理相关方法。
   - 包括 `tapAction`、`handleTap`、`handlePageSwipe`、`handleEdgeBack`、`gestureRecognizer...`。
   - 状态：已完成。

3. `CollectionReaderViewController+Chrome.swift`
   - 移动顶部栏、底部栏、菜单、浮动按钮、主题、状态栏、加载状态相关方法。
   - 包括 `configureTopBar`、`configureBottomBar`、`configureMenus`、`setMenuVisible`、`applyTheme`。

4. `CollectionReaderViewController+Settings.swift`
   - 移动设置面板、字号、布局调节、开关、设置保存相关方法。
   - 包括 `configureSettingsPanel`、`layoutAdjustment...`、`settings...Changed`、`saveSettingsImmediately`。

5. `CollectionReaderViewController+Paging.swift`
   - 移动加载页面、追加/前插、trim、prefetch、滚动定位、页码计算。
   - 包括 `openPage`、`loadPage`、`appendPage`、`prependPage`、`prefetchPagesNearCurrent`。

6. `CollectionReaderViewController+AutoRead.swift`
   - 移动自动阅读面板、速度、display link、暂停恢复。
   - 包括 `startAutoReading`、`stopAutoReading`、`advanceAutoRead`。
   - 状态：已完成。

7. `CollectionReaderViewController+ProgressAndBookmarks.swift`
   - 移动当前进度、书签状态、进度保存、阅读历史。
   - 包括 `updateCurrentProgress`、`scheduleProgressSave`、`bookmarkButtonTapped`。

拆分完成判定：

- 主文件保留属性、初始化、生命周期和核心协调入口，目标控制在 700 行以内。
- 每个扩展文件建议低于 700 行。
- 编译通过，阅读器打开、翻页、目录、搜索、设置、书签、自动阅读至少手动 smoke test 一轮。

## P1：书库入口视图拆分

目标文件：`Yomink/Presentation/Library/LibraryView.swift`

当前问题：

- 单文件 1,109 行，入口视图混合页面结构、抽屉、路由、书架内容、导入、选择操作。
- SwiftUI computed view 较多，后续改 UI 容易产生冲突。

建议拆分顺序：

1. `LibraryView+Drawers.swift`
   - 移动抽屉显示、宽度、关闭手势、打开/关闭逻辑。

2. `LibraryView+Routes.swift`
   - 移动 `routeLinks`、reader navigation binding、路由打开/关闭逻辑。

3. `LibraryView+Shelf.swift`
   - 移动书架内容、列表、网格、空状态、骨架屏。

4. `LibraryView+Import.swift`
   - 移动导入入口、导入 overlay、导入进度状态。

5. 后续视情况提取独立子视图：
   - `LibraryShelfContentView`
   - `LibrarySelectionActionBar`
   - `LibraryImportingOverlay`

拆分完成判定：

- `LibraryView.swift` 目标控制在 400 行以内。
- 抽屉、导入、搜索、标签/分组路由、阅读器打开路径行为不变。

## P1：测试文件拆分

目标文件：`YominkTests/AppDatabaseConstraintsTests.swift`

当前问题：

- 单文件 960 行，包含数据库约束、领域模型边界、文件删除恢复、导出、历史、搜索、标签、导入去重、批量导入等多个主题。

建议拆分为：

- `AppDatabaseConstraintsTests.swift`
- `DomainModelBoundsTests.swift`
- `AppFileStoreDeletionStagingTests.swift`
- `BookExportServiceTests.swift`
- `ReadingHistoryLimitTests.swift`
- `BookSearchEscapingTests.swift`
- `ImportServiceDuplicateTests.swift`

拆分完成判定：

- 仅移动测试代码和共享 helper，不改断言。
- 测试目标可编译；相关 XCTest 可运行时应全部通过。

## P2：GRDB 仓储拆分

目标文件：`Yomink/Data/Database/GRDBLibraryRepository.swift`

当前问题：

- 单文件 921 行，一个类型覆盖多个领域能力。

建议拆分为：

- `GRDBLibraryRepository+Books.swift`
- `GRDBLibraryRepository+Search.swift`
- `GRDBLibraryRepository+Tags.swift`
- `GRDBLibraryRepository+Groups.swift`
- `GRDBLibraryRepository+Bookmarks.swift`
- `GRDBLibraryRepository+ReadingProgress.swift`
- `GRDBLibraryRepository+Settings.swift`
- `GRDBLibraryRepository+Import.swift`

拆分注意：

- 先保留 `struct GRDBLibraryRepository` 和共享属性在原文件。
- 共享 SQL/helper 若增多，再提 `GRDBLibraryRepositoryHelpers.swift`，仓库已有同名 helper 文件时优先复用。
- 每步拆分后跑数据库相关测试。

## P2：数据库迁移拆分

目标文件：`Yomink/Data/Database/AppDatabase.swift`

当前问题：

- 初始化、迁移、遗留修复集中在一个文件。

建议拆分为：

- `AppDatabase.swift`：初始化、writer、公开入口。
- `AppDatabase+Migrations.swift`：`migrate()` 和迁移注册。
- `AppDatabase+LegacyRepair.swift`：遗留 oversized chapters 修复。
- `AppDatabase+DeletionRecovery.swift`： staged deletion recovery。

拆分完成判定：

- 数据库初始化和 in-memory 数据库测试通过。
- 迁移顺序保持不变。

## 后续队列

- `Yomink/Presentation/Reader/ReaderContentsViewController.swift`
- `Yomink/Presentation/Reader/ReaderContentSearchViewController.swift`
- `Yomink/Presentation/Library/RandomBookPickerPage.swift`
- `Yomink/Presentation/Library/StorageManagementComponents.swift`
- `Yomink/Domain/Services/ImportService.swift`
- `Yomink/Presentation/Library/LibraryTagsComponents.swift`
- `Yomink/Presentation/Library/LibraryViewModel.swift`

## 变更记录

| 日期 | 改动 | 文件 | 验证 | 备注 |
| --- | --- | --- | --- | --- |
| 2026-06-06 | 拆出阅读器 CollectionView/ScrollView 基础委托和手势扩展 | `CollectionReaderViewController.swift`、`CollectionReaderViewController+CollectionView.swift`、`CollectionReaderViewController+Gestures.swift`、`Yomink.xcodeproj/project.pbxproj` | `git diff --check` 通过；确认新文件已加入 Xcode Sources；本环境无 `xcodebuild`/`swift`，未能编译 | 主文件降至 3,888 行；`scrollViewWillEndDragging` 留待 AutoRead 拆分 |
| 2026-06-06 | 拆出阅读器自动阅读扩展 | `CollectionReaderViewController.swift`、`CollectionReaderViewController+AutoRead.swift`、`Yomink.xcodeproj/project.pbxproj` | `git diff --check` 通过；确认 AutoRead 新文件已加入 Xcode Sources；静态搜索确认 AutoRead 方法只在扩展中定义；本环境无 `xcodebuild`/`swift`，未能编译 | 主文件降至 3,529 行；AutoRead 扩展 401 行 |
| 2026-06-06 | 建立新的大文件拆分规划和维护规则 | `LARGE_FILE_SPLITTING_PLAN.md` | 文档新增，未改业务代码 | 后续改动前必须读本文档，改动后必须更新本文档 |
