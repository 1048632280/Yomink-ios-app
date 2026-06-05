# 大文件拆分规划

> 本文档是后续拆分大文件的唯一执行基准。每次开始拆分前必须先读取本文档；每次完成拆分后必须把实际改动、验证结果和遗留风险记录到本文档的“执行记录”中。

## 目标

- 降低超大 Swift 文件的维护成本。
- 保持行为不变，优先做“声明级搬运”，避免把拆分和重构混在一起。
- 每一步都能独立编译、独立回滚、独立记录。
- 先拆 UI/Presentation 中边界清晰的文件，最后再处理数据层和需要访问级别调整的复杂文件。

## 执行原则

1. 每次只处理一个原始大文件。
2. 每次只移动完整顶层类型、完整页面、完整控制器或完整辅助类型组。
3. 不改业务逻辑，不拆函数体，不改命名，不顺手优化实现。
4. 能保持原访问级别就保持原访问级别。
5. 跨文件必须访问时，只放宽必要的顶层类型访问级别，避免放宽属性和方法。
6. 修改 `Yomink.xcodeproj/project.pbxproj` 时，只做新增/移除 Swift 文件 target membership 的必要改动。
7. 每步完成后检查 diff，确认主要变化是代码搬运和工程文件登记。
8. 每步完成后更新本文档的执行记录。

## 每步固定流程

### 开始前

- 读取本文档，确认当前步骤、边界和风险。
- 运行文件引用搜索，确认待移动类型的使用方。
- 确认工作区状态，避免混入无关改动。
- 如果发现本文档计划与当前代码不一致，先更新计划，再执行拆分。

### 拆分中

- 只移动计划中的类型或连续代码块。
- 移动后保持原文件中剩余代码可读，不留下空壳注释。
- 新文件放在与原文件相同模块目录下，除非计划明确要求跨目录迁移。
- 对同一原文件拆出的新文件使用统一命名前缀。

### 完成后

- 运行可用的静态检查或构建检查。
- 记录无法在当前环境运行的检查。
- 更新“执行记录”，写明：
  - 拆分日期
  - 原始文件
  - 新增/删除/调整的文件
  - 是否有访问级别变化
  - 验证命令和结果
  - 遗留风险

## 当前基线

本基线来自 2026-06-05 的项目扫描。

| 优先级 | 文件 | 行数 | 主要问题 | 建议处理 |
| --- | --- | ---: | --- | --- |
| P0 | `Yomink/Presentation/Reader/ReaderHostView.swift` | 6709 | 阅读器主控制器、目录、设置、分页、渲染、组件混在一个文件 | 分阶段拆，先移出独立顶层类型，最后再考虑主控制器 extension 化 |
| P0 | `Yomink/Presentation/Library/LibraryDedicatedPages.swift` | 5158 | 多个书架专用页面、存储管理、随机抽书、导出服务、通用组件混在一起 | 按页面和组件组拆分 |
| P1 | `Yomink/Presentation/Library/LibraryView.swift` | 2626 | 主页面、ViewModel、搜索、书架 item、导入导出 presenter 混在一起 | 先拆 ViewModel 和独立组件 |
| P1 | `Yomink/Presentation/Reader/ReaderMoreViewControllers.swift` | 2204 | 多个 UIKit 控制器共用一个文件 | 优先作为低风险试拆 |
| P2 | `Yomink/Data/Database/GRDBLibraryRepository.swift` | 1368 | 仓库方法多，访问私有数据库属性，跨文件拆分会涉及访问级别 | 暂缓，等 UI 拆完后单独设计 |
| P2 | `YominkTests/AppDatabaseConstraintsTests.swift` | 1059 | 多个测试类集中在一个文件 | 可按测试类拆，风险低 |
| P3 | `Yomink/Data/Database/AppDatabase.swift` | 936 | 迁移、删除恢复、旧章节修复集中 | 暂缓，避免拆分数据库私有实现 |
| P3 | `Yomink/Domain/Services/ImportService.swift` | 720 | 导入、预览、批量导入、hash、iCloud 下载协调集中 | 暂不急，保持观察 |

资源文件补充：

- `tmp/icon-previews/` 已进入 Git，约 899 KB。
- 如果这些只是临时图标预览，后续应单独决定是否移入 `docs/icon-proposals/` 或从版本库移除并把 `tmp/` 加入 `.gitignore`。
- 资源清理不和源码拆分混在同一步做。

## 当前进度

- 已完成：第 1 步，拆分 `ReaderMoreViewControllers.swift`。
- 已完成：第 2 步，拆分 `LibraryDedicatedPages.swift`。
- 下一步：第 3 步，拆分 `ReaderHostView.swift`。
- 后续每次继续拆分前，先读取本文档的“当前进度”“推荐拆分顺序”和“执行记录”。

## 推荐拆分顺序

### 第 1 步：拆 `ReaderMoreViewControllers.swift`

选择原因：

- 顶层控制器边界清楚。
- 多数类型可整块移动。
- 适合作为第一轮验证 Xcode 工程文件更新流程的低风险试拆。

建议新文件：

- `Yomink/Presentation/Reader/ReaderBookDetailViewController.swift`
  - `ReaderBookDetailViewController`
  - `ReaderTagBubbleWrapView`
  - `ReaderTagBubbleLabel`
- `Yomink/Presentation/Reader/ReaderBookDetailEditViewController.swift`
  - `ReaderBookDetailEditViewController`
  - `ReaderBookTagPickerHostView`
- `Yomink/Presentation/Reader/ReaderFilterRulesViewController.swift`
  - `ReaderFilterRulesViewController`
- `Yomink/Presentation/Reader/ReaderContentSearchViewController.swift`
  - `ReaderContentSearchViewController`
  - `ReaderSearchResult`
  - search cache/result cell/position/batch helper types
- `Yomink/Presentation/Reader/ReaderBookCoverView.swift`
  - `ReaderBookCoverView`
- `Yomink/Presentation/Reader/ReaderPageTouchAreasViewController.swift`
  - `ReaderPageTouchAreasViewController`
  - touch area related extensions

注意事项：

- 尽量保留每个控制器自己的 private helper 在同一个新文件内。
- 不改搜索逻辑、过滤规则逻辑、详情页渲染逻辑。
- 如果原文件被清空，则删除原文件并同步更新 Xcode 工程。

### 第 2 步：拆 `LibraryDedicatedPages.swift`

选择原因：

- 文件行数很大，但页面边界相对明显。
- 拆分后能显著降低 Library 目录维护压力。

建议新文件：

- `Yomink/Presentation/Library/LibraryGroupsPage.swift`
  - `LibraryGroupsPage`
  - `GroupNameEditor`
- `Yomink/Presentation/Library/LibraryTagsPage.swift`
  - `LibraryTagsPage`
  - `LibraryTagListRow`
  - `TaggedBooksPage`
  - tag word cloud related types
- `Yomink/Presentation/Library/BookTagPickerPage.swift`
  - `BookTagPickerPage`
  - tag selection row/bubble
  - non-blocking long press helper
- `Yomink/Presentation/Library/ReadingHistoryPage.swift`
  - `ReadingHistoryPage`
  - `ReadingHistoryTableView`
  - `ReadingHistoryCell`
- `Yomink/Presentation/Library/RandomBookPickerPage.swift`
  - `RandomBookPickerPage`
  - random picker stats/cards/covers/scope helpers
- `Yomink/Presentation/Library/StorageManagementPage.swift`
  - `StorageManagementPage`
  - storage dashboard/chart/book usage/detail/filter/sort helpers
  - `StorageUsageScanner`
  - storage usage model types
  - `StorageExportPayload`
- `Yomink/Presentation/Library/BookExportService.swift`
  - `BookExportService`
  - 先只在 Library 目录内独立成文件，不跨到 Domain，避免同时做架构迁移
- `Yomink/Presentation/Library/ImportBookEditPage.swift`
  - `ImportBookEditPage`
  - import metadata row/editor
- `Yomink/Presentation/Library/LibrarySettingsPages.swift`
  - `LibrarySettingsPage`
  - sort order/view mode/settings option pages
- `Yomink/Presentation/Library/DedicatedPageComponents.swift`
  - back button
  - prompt/confirmation/modal backdrop
  - pop gesture restorer
  - shared list row/reorder handle
  - dedicated page styles
  - settings page styles
  - shared storage card style
  - dedicated book cover string helper

注意事项：

- 先按大块页面搬运，再处理共享组件。
- 不在本步骤调整 `BookExportService` 的目录层级归属，只做文件拆分。
- 如发现某个 private component 被多个新文件需要使用，只放宽该 component 的顶层访问级别。

### 第 3 步：拆 `ReaderHostView.swift`

选择原因：

- 当前最大文件，但内部主控制器耦合强，不适合第一轮直接大拆。
- 先拆独立顶层类型，降低单文件规模，再评估是否拆主控制器方法。

第一阶段建议新文件：

- `Yomink/Presentation/Reader/ReaderHostView.swift`
  - 保留 `ReaderHostView`
  - 目标是让文件名重新匹配 SwiftUI representable 职责
- `Yomink/Presentation/Reader/CollectionReaderViewController.swift`
  - `CollectionReaderViewController`
  - 第一阶段可继续保留主控制器完整实现，不拆方法
- `Yomink/Presentation/Reader/ReaderContentTarget.swift`
  - `ReaderContentTarget`
- `Yomink/Presentation/Reader/ReaderContentsViewController.swift`
  - `ReaderContentsViewController`
  - `ReaderBookmarkCell`
- `Yomink/Presentation/Reader/ReaderSettingsViewController.swift`
  - `ReaderSettingsViewController`
- `Yomink/Presentation/Reader/ReaderPageWidgets.swift`
  - progress slider
  - widget layout/snapshot/overlay
  - battery icon view
- `Yomink/Presentation/Reader/ReaderPagination.swift`
  - `ChapterPaginator`
  - `CollectionReaderPaginator`
  - `CollectionReaderPage`
  - `CollectionReaderError`
- `Yomink/Presentation/Reader/ReaderPageRendering.swift`
  - `ReaderLayoutConfiguration`
  - `ReaderTypography`
  - page cell
  - CoreText page view

第二阶段可选：

- `CollectionReaderViewController+Chrome.swift`
- `CollectionReaderViewController+SettingsPanel.swift`
- `CollectionReaderViewController+Paging.swift`
- `CollectionReaderViewController+Progress.swift`
- `CollectionReaderViewController+AutoRead.swift`
- `CollectionReaderViewController+Gestures.swift`

第二阶段注意事项：

- 主控制器 extension 化会涉及 private 成员跨文件访问，风险高于顶层类型搬运。
- 只有在第一阶段稳定后再做。
- 每次只拆一个职责组。

### 第 4 步：拆 `LibraryView.swift`

选择原因：

- 主视图和 ViewModel/组件混在一起。
- 拆分时可能需要少量访问级别调整，放在前面几步稳定后处理。

建议新文件：

- `Yomink/Presentation/Library/LibraryViewModel.swift`
  - `LibraryViewModel`
- `Yomink/Presentation/Library/LibraryRoutes.swift`
  - `LibraryRoute`
  - deletion/export/import transient models
- `Yomink/Presentation/Library/LibraryPresenters.swift`
  - `DocumentPickerPresenter`
  - `ActivityPresenter`
- `Yomink/Presentation/Library/BookShelfViews.swift`
  - row/grid item views
  - cover placeholder
  - progress bar
  - list/grid/cover style enums
- `Yomink/Presentation/Library/GlobalBookSearchView.swift`
  - global search view
  - focusable search text field
  - search bar style
- `Yomink/Presentation/Library/ReadingProgressFormatter.swift`
  - `ReadingProgressFormatter`

注意事项：

- 先拆 ViewModel，再拆 UI components。
- `LibraryView` 最终应保留页面组合、导航、drawer、selection action 等主流程。
- 不在本步骤改变书架搜索、导入、删除、导出的行为。

### 第 5 步：拆测试文件

建议新文件：

- `YominkTests/DatabaseConstraintsTests.swift`
- `YominkTests/DomainModelBoundsTests.swift`
- `YominkTests/AppFileStoreDeletionStagingTests.swift`
- `YominkTests/BookExportServiceTests.swift`
- `YominkTests/ReadingHistoryLimitTests.swift`
- `YominkTests/BookSearchEscapingTests.swift`
- `YominkTests/ImportServiceDuplicateTests.swift`

注意事项：

- 只按现有 test class 搬运。
- 不改断言，不改测试命名。

### 第 6 步：重新评估数据层

暂缓文件：

- `Yomink/Data/Database/GRDBLibraryRepository.swift`
- `Yomink/Data/Database/AppDatabase.swift`
- `Yomink/Domain/Services/ImportService.swift`

暂缓原因：

- 这些文件内部依赖 private 状态、数据库事务、迁移顺序或文件协调逻辑。
- 跨文件拆分可能需要访问级别或架构调整，不适合作为第一轮“无行为变化拆分”。

后续可选方向：

- `GRDBLibraryRepository+Books.swift`
- `GRDBLibraryRepository+TagsGroups.swift`
- `GRDBLibraryRepository+ProgressBookmarks.swift`
- `GRDBLibraryRepository+SettingsHistory.swift`
- `GRDBRecordMappings.swift`
- `AppDatabase+Migrations.swift`
- `AppDatabase+LegacyChapterRepair.swift`

## 验证命令

本地 Windows 环境无法直接完成 iOS Xcode 构建时，应记录“未运行原因”。在 macOS + Xcode 环境中优先运行：

```sh
xcodebuild build -project Yomink.xcodeproj -scheme Yomink -configuration Debug -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Yomink.xcodeproj -scheme Yomink -configuration Debug -destination "platform=iOS Simulator,name=iPhone 16" CODE_SIGNING_ALLOWED=NO
```

Windows 本地可用的辅助检查：

```powershell
rg --files
rg -n "final class|struct|enum|extension" Yomink YominkTests
git -c safe.directory=E:/GithubRepo/Yomink-ios-app status --short
```

## 执行记录

| 日期 | 步骤 | 原始文件 | 实际改动 | 访问级别变化 | 验证结果 | 遗留风险 |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-06-05 | 建立规划 | 无 | 新增 `docs/large-file-splitting-plan.md`，记录大文件基线、拆分顺序、执行流程和记录要求 | 无 | 文档创建，未改代码 | 现有 Xcode 构建未在 Windows 环境运行 |
| 2026-06-05 | 第 1 步：拆 `ReaderMoreViewControllers.swift` | `Yomink/Presentation/Reader/ReaderMoreViewControllers.swift` | 删除原聚合文件；新增 `ReaderBookDetailViewController.swift`、`ReaderBookDetailEditViewController.swift`、`ReaderFilterRulesViewController.swift`、`ReaderContentSearchViewController.swift`、`ReaderBookCoverView.swift`、`ReaderPageTouchAreasViewController.swift`；同步更新 `Yomink.xcodeproj/project.pbxproj` source entries | 无 | 已逐块对比新文件正文与 Git 中原文件对应行段，全部一致；已确认旧工程引用移除、新文件 sources 登记完成；`xcodebuild` 在当前 Windows 环境不可用，未运行 Xcode 构建 | 需在 macOS + Xcode 环境运行 build/test 做最终编译确认 |
| 2026-06-05 | 第 2 步：拆 `LibraryDedicatedPages.swift` | `Yomink/Presentation/Library/LibraryDedicatedPages.swift` | 删除原聚合文件；新增 `LibraryGroupsPage.swift`、`LibraryTagsPage.swift`、`BookTagPickerPage.swift`、`ReadingHistoryPage.swift`、`RandomBookPickerPage.swift`、`LibrarySettingsPages.swift`、`StorageManagementPage.swift`、`BookExportService.swift`、`ImportBookEditPage.swift`、`DedicatedPageComponents.swift`；同步更新 `Yomink.xcodeproj/project.pbxproj` source entries | `View.storageCardStyle`、`DedicatedPromptOverlay`、`DedicatedConfirmationOverlay`、`DedicatedGroupListRow`、`DedicatedPageStyle`、`String.dedicatedFirstBookCoverCharacter`、`SettingsPageStyle` 从 file-private/private 放宽为默认 internal，供拆分后的多个文件共享 | 已逐块对比新文件正文与 Git 中原文件对应行段，除上述访问级别调整外全部一致；已确认旧工程引用移除、新文件 sources 登记完成；`git diff --check` 通过；`xcodebuild` 在当前 Windows 环境不可用，未运行 Xcode 构建 | 需在 macOS + Xcode 环境运行 build/test 做最终编译确认 |

## 后续记录模板

复制以下模板追加到“执行记录”表格中：

```markdown
| YYYY-MM-DD | 第 N 步：拆 xxx | `原始文件路径` | 新增 `...`；移动 `...`；删除/保留 `...` | 无 / `TypeName` 从 private 改为 internal | 已运行 `...`，通过 / 未运行，原因：... | 无 / ... |
```
