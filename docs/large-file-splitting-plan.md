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
- 已完成：第 3 步，拆分 `ReaderHostView.swift` 顶层类型；阶段 A、阶段 B、阶段 C 已完成。
- 已完成：第 4 步，拆分 `LibraryView.swift` 顶层类型；阶段 A 至阶段 F 已完成，已拆出 `LibraryViewModel.swift`、`LibraryRoutes.swift`、`LibraryPresenters.swift`、`BookShelfViews.swift`、`GlobalBookSearchView.swift` 和 `ReadingProgressFormatter.swift`。
- 已跳过：第 5 步，测试文件拆分；2026-06-06 用户要求跳过，后续如需可单独恢复。
- 已完成：第 6 步阶段 A，拆 `GRDBLibraryRepository.swift` 尾部 row mapping extensions 到 `GRDBRecordMappings.swift`。
- 已完成：第 6 步阶段 B 只读评估，建议下一刀拆 `GRDBLibraryRepository` 的查询 helper 到 `GRDBLibraryRepositoryQuery.swift`。
- 已完成：第 6 步阶段 C，拆 `GRDBLibraryRepository` 查询 helper 到 `GRDBLibraryRepositoryQuery.swift`。
- 已完成：第 7 步只读全量评估，已补充剩余大文件拆分路线图。
- 已完成：第 8 步，批次 A 低风险顶层类型一次性拆分。
- 已完成：第 9 步，批次 B 阶段 A，拆 `CollectionReaderViewController.swift` 底部 ReaderSettings presentation helpers 到 `ReaderSettingsPresentationHelpers.swift`。
- 已完成：第 10 步，批次 B 阶段 B，拆 `GRDBLibraryRepository.swift` 静态 helper 到 `GRDBLibraryRepositoryHelpers.swift`。
- 已完成：第 11 步，批次 B 阶段 C，拆 `ImportService.swift` 顶部导入模型到 `ImportModels.swift`。
- 当前低风险拆分阶段收尾完成；下一步优先在 macOS + Xcode/CI 环境确认编译。若继续拆高风险文件，需另起阶段先做只读规划。
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

2026-06-06 用户要求跳过本步骤。后续如果需要恢复测试文件拆分，仍按以下原计划执行。

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

### 第 6 步只读评估结果（2026-06-06）

用户跳过测试拆分后，已对以下候选文件做只读扫描：

- `Yomink/Data/Database/GRDBLibraryRepository.swift`：约 1368 行，主仓库方法集中在同一类型内，尾部有一组 `private extension Model { init?(row:) }` / `init?(record:)` 映射。
- `Yomink/Data/Database/AppDatabase.swift`：约 936 行，迁移、删除恢复、旧章节修复高度集中，涉及 `writer`、`fileStore`、迁移顺序和 repair plan 嵌套类型。
- `Yomink/Domain/Services/ImportService.swift`：约 720 行，导入、批量导入、iCloud 下载、文件协调、hash、失败清理互相依赖，内部 private helper 较多。

推荐第一刀：

- `Yomink/Data/Database/GRDBRecordMappings.swift`
  - 从 `GRDBLibraryRepository.swift` 尾部搬出：
    - `Book.init(row:)`
    - `BookGroup.init(record:)`
    - `BookTag.init(row:)`
    - `BookTagUsage.init(row:)`
    - `Chapter.init(row:)`
    - `ReadingProgress.init(row:)`
    - `Bookmark.init(row:)`
    - `TextFilterRule.init(row:)`
    - `SearchHistoryItem.init(row:)`
    - `ReadingHistoryItem.init(row:)`
  - 选择原因：这些映射是纯 row/record 转 model 的声明级搬运，不访问 `GRDBLibraryRepository.database`，不改变事务边界，不触碰 SQL 执行顺序。
  - 访问级别影响：原本在 `private extension` 中；搬到新文件后，供 `GRDBLibraryRepository.swift` 调用的 init 需要从 private 放宽为默认 internal。`Book.rowLogger` 可继续保持 private。
  - 验证重点：确认所有 `Model(row:)` / `BookGroup(record:)` 引用仍可见，确认 `GRDBRecordMappings.swift` 已登记到 Xcode Sources，运行 `git diff --check`；最终仍需 macOS + Xcode/CI 编译确认。

暂不建议立刻拆：

- `GRDBLibraryRepository+Books.swift` / `+TagsGroups.swift` / `+ProgressBookmarks.swift`：会让 extension 跨文件访问 `database`、`BookQuery`、normalization helper、`bookNotFoundError()` 等私有成员，访问级别放宽面较大。
- `GRDBLibraryRepository+SettingsHistory.swift`：可作为第二或第三刀，但涉及 `settingsLogger`、JSON 编解码、多个 storage key，建议等 `GRDBRecordMappings.swift` 编译稳定后再做。
- `AppDatabase+Migrations.swift`：迁移体量大且顺序敏感，虽然可拆 `makeMigrator()`，但风险高于 row mapping。
- `AppDatabase+LegacyChapterRepair.swift`：涉及 `fileStore`、嵌套 repair model、remap 逻辑和文件读取，访问级别与行为风险较高。
- `ImportService` 拆分：顶部导入进度/预览模型可低风险搬到 `ImportModels.swift`，但主 helper 依赖文件协调、安全作用域、iCloud 下载和清理流程，建议排在 repository 映射稳定之后。

### 第 6 步阶段 B 只读评估结果（2026-06-06）

本轮只读扫描对象：

- `Yomink/Data/Database/GRDBLibraryRepository.swift`：映射扩展搬走后约 1138 行，剩余主体仍包含图书查询、搜索历史、标签、分组、书签、过滤规则、阅读进度、阅读历史、设置、导入和删除。
- `Yomink/Data/Database/GRDBRecordMappings.swift`：约 233 行，已承接 row/record 到 domain model 的映射。
- `Yomink/Data/Database/AppDatabase.swift`：约 936 行，仍建议暂缓。
- `Yomink/Domain/Services/ImportService.swift`：约 720 行，仍建议暂缓。

推荐下一刀：

- `Yomink/Data/Database/GRDBLibraryRepositoryQuery.swift`
  - 从 `GRDBLibraryRepository.swift` 搬出：
    - `private enum BookQuery`
    - `private static func fetchBook(_ db: Database, contentHash: String) throws -> Book?`
  - 选择原因：这组 helper 不访问 `database` 实例属性，不改变事务边界，只负责生成 books 查询 SQL 和按 contentHash 读取单本书；比拆 settings/history 更接近声明级搬运。
  - 访问级别影响：`BookQuery` 和 `fetchBook` 需要从 `private` 放宽为默认 internal，供 `GRDBLibraryRepository.swift` 继续调用；`BookQuery.orderClause(for:)` 可继续保持 internal 或在新类型内保持不额外暴露，下一轮执行时以 Swift 编译可见性为准。
  - 验证重点：确认 `BookQuery.booksSQL`、`BookQuery.selectedColumns`、`BookQuery.progressJoin` 和 `GRDBLibraryRepository.fetchBook` 的引用仍可见；确认 `GRDBLibraryRepositoryQuery.swift` 登记到 Xcode Sources；运行 `git diff --check` 和行尾空白检查；最终仍需 macOS + Xcode/CI 编译确认。

暂不建议作为下一刀：

- `GRDBLibraryRepository+SettingsHistory.swift`：虽然方法区间集中，但会让跨文件 extension 访问 `database` 和 `settingsLogger`，且涉及 JSON 编解码失败兜底，访问级别和行为风险都高于 query helper。
- `GRDBLibraryRepository+SearchHistory.swift`：方法短，但拆成 protocol conformance extension 后仍要跨文件访问 `database`，收益小于风险。
- `GRDBLibraryRepository+TagsGroups.swift` / `+ProgressBookmarks.swift`：会同时牵动 normalization helper、`fetchTag`、`bookNotFoundError()` 等私有 helper，建议等 query helper 稳定后再重新评估。

## 剩余大文件全量路线图（2026-06-06）

本轮只读扫描当前 Swift 文件体量后，超过约 700 行且需要继续关注的文件如下：

| 文件 | 当前行数 | 评估结论 | 风险 |
| --- | ---: | --- | --- |
| `Yomink/Presentation/Reader/CollectionReaderViewController.swift` | 约 4599 | 仍是最大文件；只建议先搬底部 ReaderSettings layout/theme 顶层 extension，暂不拆主控制器方法 | 中到高 |
| `Yomink/Presentation/Library/StorageManagementPage.swift` | 约 1192 | 有大量顶层 private support types，可按模型/扫描器和视图组件分两刀拆 | 低到中 |
| `Yomink/Presentation/Library/RandomBookPickerPage.swift` | 约 1107 | 尾部 stats/components 已是顶层 private types，可整块搬到组件文件 | 低 |
| `Yomink/Data/Database/GRDBLibraryRepository.swift` | 约 1077 | 已拆 mappings 和 query helper；下一步只建议拆静态 normalization/helper，暂缓拆 repository 方法组 | 中到高 |
| `YominkTests/AppDatabaseConstraintsTests.swift` | 约 1059 | 用户已要求跳过测试文件拆分 | 跳过 |
| `Yomink/Data/Database/AppDatabase.swift` | 约 936 | 迁移和 legacy repair 顺序敏感，继续暂缓 | 高 |
| `Yomink/Presentation/Reader/ReaderContentsViewController.swift` | 约 832 | 单一目录/书签控制器，结构相对聚合；不作为近期优先项 | 中 |
| `Yomink/Presentation/Library/LibraryTagsPage.swift` | 约 822 | Tag word cloud 和 tag 子组件可拆，收益明确 | 低到中 |
| `Yomink/Presentation/Reader/ReaderContentSearchViewController.swift` | 约 782 | 单一搜索控制器，内部 search helper 可拆但优先级低 | 中 |
| `Yomink/Domain/Services/ImportService.swift` | 约 720 | 顶部 import model 可低风险搬出，但主流程依赖文件协调/iCloud/清理，暂不拆主服务 | 中到高 |

### 推荐后续批次

#### 批次 A：低风险顶层类型搬运

2026-06-06 已完成本批次一次性拆分：

1. `StorageUsageSupport.swift`
   - 原文件：`Yomink/Presentation/Library/StorageManagementPage.swift`
   - 搬出：`StorageUsageScanner`、`StorageUsageSnapshot`、`StorageUsageCategory`、`StorageUsageKind`、`StorageDonutSlice`、`StorageBookUsage`、`StorageBookSort`、`StorageBookFilter`、`StorageByteCountFormatter`、`StorageDateFormatter`、`StorageExportPayload`
   - 选择原因：这些类型位于文件尾部，主要是 scanner、model、sort/filter、formatter 和 export payload，不依赖 `StorageManagementPage` 的私有状态。
   - 访问级别影响：上述类型从 private 放宽为默认 internal，供 `StorageManagementPage.swift` 和后续组件文件使用。

2. `StorageManagementComponents.swift`
   - 原文件：`Yomink/Presentation/Library/StorageManagementPage.swift`
   - 搬出：`StorageUsageChartCard`、`StorageDonutChart`、`StorageLegendRow`、`StorageDashboardCard`、`StorageMetricTile`、`StorageBookManagementCard`、`StorageSortMenu`、`StorageFilterMenu`、`StorageSelectorLabel`、`StorageBookUsageRow`、`StorageBookDetailPage`、`StorageBookDetailRow`、`StorageBookTagsDisplayRow`、`StorageBookActionRow`、`StorageLoadingCard`
   - 选择原因：这些是页面内部视图组件，已经是连续顶层类型；建议在 support types 拆出并稳定后执行。
   - 访问级别影响：被 `StorageManagementPage.swift` 直接引用的入口组件需要默认 internal，其余仅组件文件内部使用的类型可继续 private。

3. `RandomBookPickerComponents.swift`
   - 原文件：`Yomink/Presentation/Library/RandomBookPickerPage.swift`
   - 搬出：`RandomPickerStatsPage`、`RandomPickerCountedBook`、`RandomPickerRankedBook`、`RandomPickerStatsRow`、`RandomPickerScopeChip`、`RandomPickerBookCard`、`RandomPickerPlaceholderCard`、`RandomPickerHistoryCard`、`RandomPickerCoverView`、`RandomPickerCoverStyle`
   - 选择原因：这些类型位于主页面之后，边界清晰；主页面只保留抽书状态、动画和数据加载。
   - 访问级别影响：主页面直接引用的组件需默认 internal；只在新组件文件内部互相使用的类型可继续 private。

4. `LibraryTagsComponents.swift`
   - 原文件：`Yomink/Presentation/Library/LibraryTagsPage.swift`
   - 搬出：`LibraryTagListRow`、`TaggedBooksPage`、`TagWordCloudView`、`TagWordCloudUIKitView`、`TagWordCloudPalette`
   - 选择原因：tag 列表、tagged books 子页面和 word cloud 组件都已是顶层声明，可按组件组搬运。
   - 访问级别影响：`LibraryTagsPage.swift` 直接引用的入口类型需默认 internal；`TagWordCloudUIKitView` 和 palette 可按组件文件内部依赖尽量保持 private。

#### 批次 B：小收益但可控的辅助声明搬运

5. `ReaderSettingsPresentationHelpers.swift`
   - 原文件：`Yomink/Presentation/Reader/CollectionReaderViewController.swift`
   - 搬出：底部 `ReaderSettings.LayoutPreset`、`ReaderSettings`、`ReaderSettings.Theme` layout/theme extension。
   - 选择原因：这些已经是顶层 extension，不是主控制器方法；可减少 Reader 主控制器尾部杂项。
   - 风险点：`effectiveLayoutValues` 和 `userInterfaceStyle` 当前被 `CollectionReaderViewController.swift` 调用，搬走后需从 fileprivate 放宽为默认 internal；执行前必须再次用 `rg` 确认引用。

6. `GRDBLibraryRepositoryHelpers.swift`
   - 原文件：`Yomink/Data/Database/GRDBLibraryRepository.swift`
   - 搬出：`normalizedGroupName`、`normalizedTagName`、`normalizedBookTitle`、`normalizedOptionalText`、`likePattern(for:)`、`fetchTag(_:, name:)`、`bookNotFoundError()`、`normalizedImportedChapter(_:fallbackSortOrder:)`
   - 选择原因：这些是静态 helper，不访问 `database` 实例属性；比拆 repository 方法组更稳。
   - 风险点：多个仓库方法通过 `Self.` 调用，搬到 extension 后 helper 需从 private 放宽为默认 internal。

7. `ImportModels.swift`
   - 原文件：`Yomink/Domain/Services/ImportService.swift`
   - 搬出：`ImportBookMetadata`、`ImportBookPreview`、`ImportBatchProgressPhase`、`ImportBatchProgress`、`ImportBatchFailure`、`ImportBatchSummary`
   - 选择原因：这些模型位于文件顶部，已经是顶层声明，且不依赖 `ImportService` 私有状态。
   - 风险点：收益较小，只能略微压缩 `ImportService.swift`；主导入流程暂不拆。

#### 批次 C：暂缓或需单独确认的高风险拆分

- `CollectionReaderViewController+*.swift` 主控制器 extension 化：会让大量 private 属性、状态和方法跨文件可见，风险高；除非先有 macOS + Xcode/CI 编译绿灯，否则不建议作为下一批。
- `GRDBLibraryRepository+SettingsHistory.swift`、`+TagsGroups.swift`、`+ProgressBookmarks.swift`：会迫使 `database`、`settingsLogger` 或多个 repository helper 放宽访问级别，需在 helper 拆分稳定后重新评估。
- `AppDatabase+Migrations.swift` / `AppDatabase+LegacyChapterRepair.swift`：迁移顺序、修复计划和 `fileStore` 访问敏感，继续暂缓。
- `ReaderContentsViewController.swift`、`ReaderContentSearchViewController.swift`：虽然超过 700 行，但职责仍比较单一，近期不为行数硬拆。
- `LibraryView.swift`：剩余主要是主页面组合、drawer 和 preview；不建议为了压缩行数拆 body 逻辑。

### 当前推荐下一刀

批次 A 和批次 B 阶段 A/B/C 已完成，当前低风险拆分阶段收尾。

当前不建议继续直接拆代码；下一步建议：

- 先在 macOS + Xcode/CI 环境运行 build/test，确认第 8 至第 11 步的跨文件访问级别无遗漏。
- 若 CI 通过，再单独开启高风险拆分阶段，只读评估以下候选，不直接动手：
  - `CollectionReaderViewController+*.swift` 主控制器 extension 化
  - `GRDBLibraryRepository+SettingsHistory.swift` / `+TagsGroups.swift` / `+ProgressBookmarks.swift`
  - `AppDatabase+Migrations.swift` / `AppDatabase+LegacyChapterRepair.swift`
- `ReaderContentsViewController.swift`、`ReaderContentSearchViewController.swift` 和 `LibraryView.swift` 暂不为行数硬拆。

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
| 2026-06-05 | 第 2 步：拆 `LibraryDedicatedPages.swift` | `Yomink/Presentation/Library/LibraryDedicatedPages.swift` | 删除原聚合文件；新增 `LibraryGroupsPage.swift`、`LibraryTagsPage.swift`、`BookTagPickerPage.swift`、`ReadingHistoryPage.swift`、`RandomBookPickerPage.swift`、`LibrarySettingsPages.swift`、`StorageManagementPage.swift`、`BookExportService.swift`、`ImportBookEditPage.swift`、`DedicatedPageComponents.swift`；同步更新 `Yomink.xcodeproj/project.pbxproj` source entries | `View.storageCardStyle`、`DedicatedPromptOverlay`、`DedicatedConfirmationOverlay`、`DedicatedGroupListRow`、`DedicatedPageStyle`、`String.dedicatedFirstBookCoverCharacter`、`SettingsPageStyle`、`BookTagBubble`、`NonBlockingLongPressRecognizer` 从 file-private/private 放宽为默认 internal，供拆分后的多个文件共享 | 已逐块对比新文件正文与 Git 中原文件对应行段，除上述访问级别调整外全部一致；已根据 Debug simulator 构建日志修复 `BookTagBubble` 和 `NonBlockingLongPressRecognizer` 跨文件不可见问题；已确认旧工程引用移除、新文件 sources 登记完成；`git diff --check` 通过；`xcodebuild` 在当前 Windows 环境不可用，未运行 Xcode 构建 | 需在 macOS + Xcode 环境运行 build/test 做最终编译确认 |
| 2026-06-05 | 第 3 步阶段 A：拆 `ReaderHostView.swift` host/目录/导航 | `Yomink/Presentation/Reader/ReaderHostView.swift` | 将原文件压缩为仅保留 `ReaderHostView`；新增 `CollectionReaderViewController.swift`、`ReaderNavigationHelpers.swift`、`ReaderContentTarget.swift`、`ReaderContentsViewController.swift`；同步更新 `Yomink.xcodeproj/project.pbxproj` source entries | 无 | 已用 Git 原文件原始文本逐块对比新增文件，除 `ReaderHostView.swift` 去除尾部多余空白行外均与原对应片段一致；`git diff --check` 通过；`xcodebuild` 在当前 Windows 环境不可用，未运行 Xcode 构建 | 主阅读器控制器仍在 `CollectionReaderViewController.swift` 中较大；后续需继续拆设置面板、分页、渲染和 widget helper，并在 macOS + Xcode 环境运行 build/test |
| 2026-06-05 | 第 3 步阶段 B：拆 `ReaderHostView.swift` 分页/渲染/widget helper | `Yomink/Presentation/Reader/ReaderHostView.swift` | 继续压缩 `CollectionReaderViewController.swift`；新增 `ReaderPageWidgets.swift`、`ReaderPageRendering.swift`、`ReaderPagination.swift`；同步更新 `Yomink.xcodeproj/project.pbxproj` source entries | `readerLogger`、`ReaderSettings.LayoutPreset.layoutConfiguration` extension、`ReaderProgressSlider`、`ReaderWidgetLayoutConfiguration`、`ReaderPageWidgetSnapshot`、`ReaderPageWidgetOverlayView`、`ReaderLayoutConfiguration`、`ReaderTypography`、`CollectionReaderPageCell`、`ReaderLayoutConfiguration` extension、`CollectionReaderPage`、`CollectionReaderPaginator` 从 private 放宽为默认 internal；`ReaderBatteryIconView`、`ChapterPaginator`、`CollectionReaderError` 继续保持 private | 已用 Git 原文件原始文本逐块对比 8 个 Reader 拆分文件，除上述访问级别调整和文件末尾空白归一化外正文一致；已确认新增 helper 文件 sources 登记完成；已用 `rg` 检查关键跨文件符号并修复 `readerLogger` 可见性；`git diff --check` 通过；`xcodebuild` 在当前 Windows 环境不可用，未运行 Xcode 构建 | 需在 macOS + Xcode 环境运行 build/test 做最终编译确认；`CollectionReaderViewController.swift` 仍较大，下一阶段若拆 extension 会涉及更多 private 成员访问边界 |
| 2026-06-06 | 修复第 3 步阶段 B CI 编译错误 | `Yomink/Presentation/Reader/CollectionReaderViewController.swift` | 根据 Debug simulator 日志修复 `ReaderPageRendering.swift` 访问 `ReaderSettings.default.layoutPreset.layoutConfiguration` 时不可见的问题；仅将第一个 `ReaderSettings.LayoutPreset` layout extension 从 private 放宽为默认 internal | `ReaderSettings.LayoutPreset.layoutConfiguration` extension 从 private 放宽为默认 internal | 已从 `logs_72578348690/Build unsigned IPA/6_Build Debug simulator.txt` 定位错误：`layoutConfiguration` 因 `fileprivate` 保护级别不可访问；已用 `rg` 确认 layout extension 可见性和引用位置；`git diff --check` 通过；行尾空白检查通过；`xcodebuild` 在当前 Windows 环境不可用，未运行本地 Xcode 构建 | 需重新运行 macOS + Xcode/CI build 确认无下一处 Swift 编译错误 |
| 2026-06-06 | 继续修复第 3 步阶段 B CI 编译错误 | `Yomink/Presentation/Reader/CollectionReaderViewController.swift`、`Yomink/Presentation/Reader/ReaderPageRendering.swift` | 根据新 Debug simulator 日志修复 `readerFontWeight`、`ReaderSettings.effectiveLayoutConfiguration` 和 `ReaderSettings.Theme` 颜色 helper 跨文件不可见问题；只调整访问级别，不改逻辑 | `readerFontWeight`、`ReaderSettings.effectiveLayoutConfiguration`、`ReaderSettings.Theme.backgroundColor`、`ReaderSettings.Theme.textColor`、`ReaderSettings.Theme.secondaryTextColor` 从 private/fileprivate 放宽为默认 internal；`layoutConfiguration(customValues:)`、`layoutValues`、`effectiveLayoutValues`、`userInterfaceStyle` 保持 fileprivate | 已从 `logs_72648676678/Build unsigned IPA/6_Build Debug simulator.txt` 定位错误：`readerFontWeight` 不在作用域，多个 layout/theme helper 因 `fileprivate` 保护级别不可访问；已用 `rg` 确认声明和引用位置；`git diff --check` 通过；行尾空白检查通过；`xcodebuild` 在当前 Windows 环境不可用，未运行本地 Xcode 构建 | 需重新运行 macOS + Xcode/CI build 确认无下一处 Swift 编译错误 |
| 2026-06-06 | 第 3 步阶段 C：拆 `ReaderHostView.swift` 设置控制器 | `Yomink/Presentation/Reader/CollectionReaderViewController.swift` | 新增 `ReaderSettingsViewController.swift`，搬出 `ReaderSettingsViewController` 和设置页使用的 `ReaderSettings.PageMode`、`ReaderSettings.LayoutPreset`、`ReaderSettings.Theme` 显示文案/索引 helper；同步更新 `Yomink.xcodeproj/project.pbxproj` source entries | `ReaderSettings.PageMode`、`ReaderSettings.LayoutPreset`、`ReaderSettings.Theme` 的设置页 helper extension 从 private 放宽为默认 internal，供 `CollectionReaderViewController.swift` 继续使用；`ReaderSettingsViewController` 仍保持 private | 已用 Git 原文件原始文本逐块对比 `CollectionReaderViewController.swift` 和 `ReaderSettingsViewController.swift`，除上述访问级别调整外正文一致；已确认新增设置控制器文件 sources 登记完成；`git diff --check` 通过；行尾空白检查通过；`xcodebuild` 在当前 Windows 环境不可用，未运行本地 Xcode 构建 | 需在 macOS + Xcode/CI build 确认编译；`CollectionReaderViewController.swift` 仍较大，下一阶段若拆主控制器 extension 会涉及更多 private 成员访问边界 |
| 2026-06-06 | 第 4 步阶段 A：拆 `LibraryView.swift` ViewModel | `Yomink/Presentation/Library/LibraryView.swift` | 新增 `LibraryViewModel.swift`，搬出 `LibraryViewModel` 和其私有使用的 `ImportBatchResultMessage`；同步更新 `Yomink.xcodeproj/project.pbxproj` source entries | `LibraryViewModel` 从 private 放宽为默认 internal，供 `LibraryView.swift` 的 `@StateObject` 使用；`ImportBatchResultMessage` 继续保持 private | 已用 Git 原文件原始文本逐块对比 `LibraryView.swift` 和 `LibraryViewModel.swift`，除上述访问级别调整和相邻空白行归一化外正文一致；已确认新增 ViewModel 文件 sources 登记完成；`git diff --check` 通过；行尾空白检查通过；`xcodebuild` 在当前 Windows 环境不可用，未运行本地 Xcode 构建 | 需在 macOS + Xcode/CI build 确认编译；后续继续拆 route、presenter、书架组件和搜索组件时需逐步处理 private 类型跨文件可见性 |
| 2026-06-06 | 第 4 步阶段 B：拆 `LibraryView.swift` routes/transient models | `Yomink/Presentation/Library/LibraryView.swift` | 新增 `LibraryRoutes.swift`，搬出 `LibraryRoute`、`ExportPayload`、`PendingBookDeletion`；同步更新 `Yomink.xcodeproj/project.pbxproj` source entries | `LibraryRoute`、`ExportPayload`、`PendingBookDeletion` 从 private 放宽为默认 internal；`ExportPayload` 的 memberwise init 和 `urls`、`directoryURL`，以及 `PendingBookDeletion.init(ids:)`、`message` 随拆分后跨文件使用保持默认 internal | 已用 `rg` 确认三个类型声明只保留在 `LibraryRoutes.swift`，并确认 `LibraryRoutes.swift` 已登记到 Xcode project group 和 Sources；`git diff --check` 通过；`xcodebuild` 在当前 Windows 环境不可用，未运行本地 Xcode 构建 | 需在 macOS + Xcode/CI build 确认编译；下一步拆 `LibraryPresenters.swift` 时仍需处理 `private` presenter 跨文件可见性 |
| 2026-06-06 | 第 4 步阶段 C：拆 `LibraryView.swift` presenters | `Yomink/Presentation/Library/LibraryView.swift` | 新增 `LibraryPresenters.swift`，搬出 `DocumentPickerPresenter`、`ActivityPresenter` 及 `DocumentPickerPresenter.Coordinator`；同步更新 `Yomink.xcodeproj/project.pbxproj` source entries | `DocumentPickerPresenter` 从 private 放宽为默认 internal，供 `LibraryView.swift` 跨文件使用；`ActivityPresenter` 原本已是默认 internal；为避免不必要暴露，两个 presenter 改用显式 init，并将 stored properties 收窄为 fileprivate | 已用 `rg` 确认两个 presenter 声明只保留在 `LibraryPresenters.swift`，并确认 `LibraryPresenters.swift` 已登记到 Xcode project group 和 Sources；`git diff --check` 通过；`xcodebuild` 在当前 Windows 环境不可用，未运行本地 Xcode 构建 | 需在 macOS + Xcode/CI build 确认编译；下一步拆 `BookShelfViews.swift` 时会涉及多个 private SwiftUI 组件跨文件可见性 |
| 2026-06-06 | 第 4 步阶段 D：拆 `LibraryView.swift` bookshelf views | `Yomink/Presentation/Library/LibraryView.swift` | 新增 `BookShelfViews.swift`，搬出 `BookShelfItemButton`、`BookRowView`、`BookGridItemView`、`BookCoverPlaceholder`、`PreciseProgressBar`、`BookListStyle`、`BookGridStyle`、`BookCoverStyle`、`FixedWidthImportBatchCountText` 和 `String.firstBookCoverCharacter`；显式补充 `Foundation`/`SwiftUI`/`UIKit` imports；同步更新 `Yomink.xcodeproj/project.pbxproj` source entries | `BookShelfItemButton`、`BookGridItemView`、`FixedWidthImportBatchCountText`、`BookGridStyle` 从 private 放宽为默认 internal，供 `LibraryView.swift` 跨文件使用；`BookGridStyle.coverHorizontalInset`、`BookGridStyle.coverInitialFontSize` 收窄为 fileprivate；`BookRowView` 原本已是默认 internal；其余内部样式/封面/进度 helper 继续保持 private；外部入口改用显式 init 并收窄 stored properties | 已用 `rg` 确认书架组件声明已移至 `BookShelfViews.swift`，并确认 `BookShelfViews.swift` 已登记到 Xcode project group 和 Sources；`git diff --check` 通过；行尾空白检查通过；`xcodebuild` 在当前 Windows 环境不可用，未运行本地 Xcode 构建 | 需在 macOS + Xcode/CI build 确认编译；下一步拆 `GlobalBookSearchView.swift` 时需处理搜索页 private 类型跨文件可见性 |
| 2026-06-06 | 第 4 步阶段 E：拆 `LibraryView.swift` global search | `Yomink/Presentation/Library/LibraryView.swift` | 新增 `GlobalBookSearchView.swift`，搬出 `GlobalBookSearchView`、`FocusableSearchTextField` 和 `SearchBarStyle`；显式补充 `Foundation`/`SwiftUI`/`UIKit` imports；同步更新 `Yomink.xcodeproj/project.pbxproj` source entries | `GlobalBookSearchView` 从 private 放宽为默认 internal，供 `LibraryView.swift` 跨文件使用；`FocusableSearchTextField`、`SearchBarStyle` 继续保持 private；`GlobalBookSearchView` 改用显式 init 并收窄 stored properties | 已用 `rg` 确认搜索页声明已移至 `GlobalBookSearchView.swift`，并确认 `GlobalBookSearchView.swift` 已登记到 Xcode project group 和 Sources；`git diff --check` 通过；行尾空白检查通过；`xcodebuild` 在当前 Windows 环境不可用，未运行本地 Xcode 构建 | 需在 macOS + Xcode/CI build 确认编译；下一步拆 `ReadingProgressFormatter.swift` 后需做一次 `LibraryView.swift` 剩余结构复查 |
| 2026-06-06 | 第 4 步阶段 F：拆 `LibraryView.swift` reading progress formatter | `Yomink/Presentation/Library/LibraryView.swift` | 新增 `ReadingProgressFormatter.swift`，搬出 `ReadingProgressFormatter`；同步更新 `Yomink.xcodeproj/project.pbxproj` source entries | 无；`ReadingProgressFormatter` 原本已是默认 internal，供多个 Library 页面使用 | 已用 `rg` 确认 `ReadingProgressFormatter` 声明只保留在 `ReadingProgressFormatter.swift`，并确认 `ReadingProgressFormatter.swift` 已登记到 Xcode project group 和 Sources；`git diff --check` 通过；`xcodebuild` 在当前 Windows 环境不可用，未运行本地 Xcode 构建 | 需在 macOS + Xcode/CI build 确认编译；`LibraryView.swift` 剩余为主页面组合、drawer 状态和 preview，如需进一步压缩应单独规划 extension 化 |
| 2026-06-06 | 第 6 步只读评估：数据层拆分计划 | `Yomink/Data/Database/GRDBLibraryRepository.swift`、`Yomink/Data/Database/AppDatabase.swift`、`Yomink/Domain/Services/ImportService.swift` | 未改代码；补充第 6 步只读评估结果，记录用户跳过第 5 步测试拆分，并建议第一刀拆 `GRDBRecordMappings.swift` | 无 | 已用 `rg` 和行数统计扫描三个候选文件的顶层类型、private helper 和引用；`git diff --check` 通过 | 尚未执行数据层代码拆分；需等待前序 Library 拆分在 macOS + Xcode/CI build 确认后再动第一刀 |
| 2026-06-06 | 第 6 步阶段 A：拆 GRDB record mappings | `Yomink/Data/Database/GRDBLibraryRepository.swift` | 新增 `Yomink/Data/Database/GRDBRecordMappings.swift`；搬出 `Book.init(row:)`、`BookGroup.init(record:)`、`BookTag.init(row:)`、`BookTagUsage.init(row:)`、`Chapter.init(row:)`、`ReadingProgress.init(row:)`、`Bookmark.init(row:)`、`TextFilterRule.init(row:)`、`SearchHistoryItem.init(row:)`、`ReadingHistoryItem.init(row:)`；同步更新 `Yomink.xcodeproj/project.pbxproj` source entries | 映射 extensions 从 `private extension` 放宽为默认 internal，供 `GRDBLibraryRepository.swift` 跨文件调用；`Book.rowLogger` 继续保持 private | 已用 `rg` 确认 `GRDBRecordMappings.swift` 已登记到 Xcode project group 和 Sources，并确认映射 init 已移至新文件；`git diff --check` 通过；行尾空白检查通过；`xcodebuild` 在当前 Windows 环境不可用，未运行本地 Xcode 构建 | 需在 macOS + Xcode/CI build 确认编译；后续若继续拆 repository 方法，会涉及 `database`、SQL helper、settings logger 等 private 成员访问边界，风险高于本轮映射搬运 |
| 2026-06-06 | 第 6 步阶段 B 只读评估：下一刀 query helper | `Yomink/Data/Database/GRDBLibraryRepository.swift` | 未改代码；评估映射拆出后的下一刀，建议新增 `GRDBLibraryRepositoryQuery.swift` 并只搬 `BookQuery` 与 `fetchBook(_:, contentHash:)` | 无 | 已用 `rg` 和局部文件读取确认 `BookQuery` / `fetchBook` 的引用范围；确认 settings/history 拆分会更早触碰 `database`、`settingsLogger` 和 JSON 编解码兜底；本轮未改 Swift 代码 | 尚未执行 query helper 拆分；执行时仍需登记 Xcode Sources，并在 macOS + Xcode/CI 编译确认 |
| 2026-06-06 | 第 6 步阶段 C：拆 GRDB query helper | `Yomink/Data/Database/GRDBLibraryRepository.swift` | 新增 `Yomink/Data/Database/GRDBLibraryRepositoryQuery.swift`；搬出 `BookQuery` 和 `GRDBLibraryRepository.fetchBook(_:, contentHash:)`；同步更新 `Yomink.xcodeproj/project.pbxproj` source entries | `BookQuery` 从嵌套 `private enum` 放宽为默认 internal；`fetchBook(_:, contentHash:)` 从 `private static` 放宽为默认 internal static，供 `GRDBLibraryRepository.swift` 继续调用；`BookQuery.orderClause(for:)` 保持 private | 已用 `rg` 确认 `GRDBLibraryRepositoryQuery.swift` 已登记到 Xcode project group 和 Sources，并确认 `BookQuery` / `fetchBook` 已移至新文件；`git diff --check` 通过；行尾空白检查通过；`xcodebuild` 在当前 Windows 环境不可用，未运行本地 Xcode 构建 | 需在 macOS + Xcode/CI build 确认编译；后续拆 settings/history 或 repository 方法前需重新评估 `database`、`settingsLogger` 与 normalization helper 的访问边界 |
| 2026-06-06 | 第 7 步只读评估：剩余大文件全量路线图 | 多个剩余大文件 | 未改 Swift 代码；补充“剩余大文件全量路线图”，按低风险顶层类型搬运、可控辅助声明搬运、高风险暂缓三批规划后续拆分；明确下一刀优先拆 `StorageUsageSupport.swift` | 无 | 已用行数统计扫描当前 Swift 文件体量；已用 `rg` 扫描 `CollectionReaderViewController.swift`、`StorageManagementPage.swift`、`RandomBookPickerPage.swift`、`LibraryTagsPage.swift`、`GRDBLibraryRepository.swift`、`AppDatabase.swift`、`ImportService.swift` 的顶层声明和关键引用 | 尚未执行后续代码拆分；每轮仍需先读本文档、只拆一个原始文件，并在 macOS + Xcode/CI 做最终编译确认 |
| 2026-06-06 | 第 8 步：批次 A 低风险顶层类型拆分 | `Yomink/Presentation/Library/StorageManagementPage.swift`、`Yomink/Presentation/Library/RandomBookPickerPage.swift`、`Yomink/Presentation/Library/LibraryTagsPage.swift` | 新增 `StorageUsageSupport.swift`、`StorageManagementComponents.swift`、`RandomBookPickerComponents.swift`、`LibraryTagsComponents.swift`；分别搬出 Storage support types、Storage 页面组件、Random picker stats/components、Library tags 子组件；同步更新 `Yomink.xcodeproj/project.pbxproj` source entries | Storage support types 从 private 放宽为默认 internal；`StorageUsageChartCard`、`StorageDashboardCard`、`StorageBookManagementCard`、`StorageLoadingCard` 放宽为默认 internal；`RandomPickerStatsPage`、`RandomPickerScopeChip`、`RandomPickerBookCard`、`RandomPickerPlaceholderCard`、`RandomPickerHistoryCard` 放宽为默认 internal；`LibraryTagListRow`、`TaggedBooksPage`、`TagWordCloudView`、`TagWordCloudUIKitView` 放宽为默认 internal；组件内部细节类型尽量保持 private | 已用 `rg` 确认新文件已登记到 Xcode project group 和 Sources；已用 `rg` 确认主要入口类型只在新文件声明、原页面仅保留引用；`git diff --check` 通过；行尾空白检查通过；`xcodebuild` 在当前 Windows 环境不可用，未运行本地 Xcode 构建 | 需在 macOS + Xcode/CI build 确认编译；本轮一次性移动多个低风险顶层类型，若 CI 报访问级别错误，应按日志只补必要的 internal/fileprivate 调整 |
| 2026-06-06 | 第 9 步：批次 B 阶段 A，拆 ReaderSettings presentation helpers | `Yomink/Presentation/Reader/CollectionReaderViewController.swift` | 新增 `Yomink/Presentation/Reader/ReaderSettingsPresentationHelpers.swift`；搬出底部 `ReaderSettings.LayoutPreset`、`ReaderSettings`、`ReaderSettings.Theme` layout/theme extension；同步更新 `Yomink.xcodeproj/project.pbxproj` source entries | `ReaderSettings.effectiveLayoutValues` 和 `ReaderSettings.Theme.userInterfaceStyle` 从 `fileprivate` 放宽为默认 internal，供 `CollectionReaderViewController.swift` 跨文件继续调用；`layoutConfiguration(customValues:)` 和 `layoutValues` 继续保持 fileprivate | 已用 `rg` 确认 `ReaderSettingsPresentationHelpers.swift` 已登记到 Xcode project group 和 Sources，并确认 moved extensions 已离开 `CollectionReaderViewController.swift`；`git diff --check` 通过；行尾空白检查通过；`xcodebuild` 在当前 Windows 环境不可用，未运行本地 Xcode 构建 | 需在 macOS + Xcode/CI build 确认编译；若 CI 报访问级别错误，应按日志只补必要的 internal/fileprivate 调整 |
| 2026-06-06 | 第 10 步：批次 B 阶段 B，拆 GRDB repository helpers | `Yomink/Data/Database/GRDBLibraryRepository.swift` | 新增 `Yomink/Data/Database/GRDBLibraryRepositoryHelpers.swift`；搬出 `normalizedGroupName`、`normalizedTagName`、`normalizedBookTitle`、`normalizedOptionalText`、`likePattern(for:)`、`fetchTag(_:, name:)`、`bookNotFoundError()`、`normalizedImportedChapter(_:fallbackSortOrder:)`；同步更新 `Yomink.xcodeproj/project.pbxproj` source entries | 8 个 helper 从 `private static` 放宽为默认 internal static，供 `GRDBLibraryRepository.swift` 跨文件继续通过 `Self.` 调用 | 已用 `rg` 确认 `GRDBLibraryRepositoryHelpers.swift` 已登记到 Xcode project group 和 Sources，并确认 helper 声明已移至新文件；`git diff --check` 通过；行尾空白检查通过；`xcodebuild` 在当前 Windows 环境不可用，未运行本地 Xcode 构建 | 需在 macOS + Xcode/CI build 确认编译；后续拆 repository 方法组前仍需重新评估 `database`、`settingsLogger` 等私有成员访问边界 |
| 2026-06-06 | 第 11 步：批次 B 阶段 C，拆 Import models 并收尾低风险阶段 | `Yomink/Domain/Services/ImportService.swift` | 新增 `Yomink/Domain/Services/ImportModels.swift`；搬出 `ImportBookMetadata`、`ImportBookPreview`、`ImportBatchProgressPhase`、`ImportBatchProgress`、`ImportBatchFailure`、`ImportBatchSummary`；同步更新 `Yomink.xcodeproj/project.pbxproj` source entries | 无；这些模型原本已是默认 internal，搬出后继续供 ImportService、Library 页面/ViewModel 和测试使用 | 已用 `rg` 确认 `ImportModels.swift` 已登记到 Xcode project group 和 Sources，并确认 6 个模型声明已移至新文件；`git diff --check` 通过；行尾空白检查通过；`xcodebuild` 在当前 Windows 环境不可用，未运行本地 Xcode 构建 | 需在 macOS + Xcode/CI build 确认编译；当前低风险拆分阶段已收尾，后续高风险拆分需另起只读规划 |

## 后续记录模板

复制以下模板追加到“执行记录”表格中：

```markdown
| YYYY-MM-DD | 第 N 步：拆 xxx | `原始文件路径` | 新增 `...`；移动 `...`；删除/保留 `...` | 无 / `TypeName` 从 private 改为 internal | 已运行 `...`，通过 / 未运行，原因：... | 无 / ... |
```
