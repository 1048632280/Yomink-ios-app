# 阅读核心 V2 重构计划

## 1. 目标变化

上一版计划偏向“保留现有 `CollectionReaderViewController`，逐步拆边界”。这个方向已经不适合当前目标。

当前目标是：**阅读核心按原 App 行为完整重构，外层书架、导入、数据库和本地文件体系继续保留 Yomink 的实现。**

也就是说，本次重构不是小修旧阅读器，而是新建一套 `ReaderCoreV2`，并行跑通后替换旧阅读器入口。

## 2. 重构边界

### 2.1 完整重构

这些模块按原 App 行为重写：

- CoreText 分页逻辑。
- 富文本排版。
- 页面绘制。
- 字体和字重。
- 阅读主题。
- 左右平移翻页容器。
- 仿真翻页容器。
- 纵向连续滚动容器。
- 自动阅读。
- 状态栏。
- Home Indicator 小横条。
- 阅读器内的运行态记录和页模型。

### 2.2 保留并适配

这些模块保留现有 Yomink 体系，只给新阅读核心做适配：

- `Book`。
- `Chapter`。
- `ReadingProgress`。
- `ImportService`。
- `ChapterIndexer`。
- `AppFileStore`。
- `GRDBLibraryRepository`。
- 书架、分组、标签、导出、批量导入。
- 搜索页、目录页、书签页的数据模型。

### 2.3 后续废弃

`ReaderCoreV2` 稳定替换入口后，旧阅读器相关代码逐步删除：

- `CollectionReaderViewController.swift`
- `CollectionReaderViewController+Paging.swift`
- `CollectionReaderViewController+CollectionView.swift`
- `CollectionReaderViewController+AutoRead.swift`
- `CollectionReaderViewController+Settings.swift`
- `CollectionReaderViewController+Chrome.swift`
- 旧的 `UICollectionView` 统一阅读容器逻辑。

删除前旧阅读器只作为回滚和行为对照，不再继续扩展。

## 3. 总体架构

建议新增目录：

```text
Yomink/Presentation/ReaderV2/
├─ Bridge
│  ├─ ReaderBookAdapter.swift
│  ├─ ReaderChapterProvider.swift
│  └─ ReaderProgressBridge.swift
├─ Core
│  ├─ ReaderPageModel.swift
│  ├─ ReaderRecord.swift
│  ├─ ReaderTurnPageType.swift
│  ├─ ReaderLayout.swift
│  ├─ ReaderPageCalculator.swift
│  └─ PaibanManager.swift
├─ Theme
│  ├─ ReaderTheme.swift
│  └─ ReaderThemeManager.swift
├─ Rendering
│  ├─ TextReadViewBase.swift
│  ├─ TextReadView.swift
│  ├─ ReaderPageViewController.swift
│  └─ ReaderPageBackgroundView.swift
├─ Containers
│  ├─ ReaderContainerProtocol.swift
│  ├─ ReaderPageContainer.swift
│  ├─ ReaderScrollContainer.swift
│  ├─ ReaderPageCurlContainer.swift
│  └─ ReaderScrollPageCell.swift
├─ Chrome
│  ├─ ReaderV2ViewController.swift
│  ├─ ReaderMenuController.swift
│  ├─ ReaderSettingsPanel.swift
│  ├─ ReaderAutoReadController.swift
│  └─ ReaderSystemAppearanceController.swift
└─ Integration
   ├─ ReaderV2HostView.swift
   ├─ ReaderV2Navigator.swift
   └─ ReaderV2Localizable.swift
```

命名可以后续微调，但职责必须清晰：分页不碰 UI 容器，容器不碰数据库，状态栏不散落在多个控制器里。

## 4. 数据适配层

新阅读器内部使用原 App 风格模型，外部仍接 Yomink 当前模型。

### 4.1 内部页模型

```swift
struct ReaderPageModel {
    var chapterCount: Int
    var chapterIndex: Int
    var pageCount: Int
    var pageIndex: Int
    var chapterProgress: Double
    var usesPageIndex: Bool
    var pageStatus: ReaderPageStatus
}
```

作用：

- 对齐原 App 的 `ReadPageModel` 行为。
- 容器、菜单、自动阅读、保存记录都读这个模型。
- 不直接暴露 Yomink 的 `ReadingProgress`。

### 4.2 内部阅读记录

```swift
struct ReaderRecord {
    var chapterIndex: Int
    var progress: Double
    var chapterTitle: String
    var timestamp: Date
}
```

作用：

- 阅读器内部跳转和恢复使用。
- 搜索结果、目录结果、书签结果先转成 `ReaderRecord`。
- 保存时再通过 `ReaderProgressBridge` 转回 `ReadingProgress`。

### 4.3 与现有进度的桥接

Yomink 持久化继续使用：

```swift
ReadingProgress(
    bookID: book.id,
    chapterID: chapter.id,
    chapterOffset: offset,
    globalProgress: progress
)
```

桥接规则：

- 打开阅读器时：`ReadingProgress -> ReaderRecord`。
- 阅读器运行时：`ReaderRecord -> ReaderPageModel`。
- 保存进度时：`ReaderPageModel -> ReaderRecord -> ReadingProgress`。
- `chapterID` 不存在或章节被重建时，按 `chapterIndex/progress` 兜底。

页码公式按原 App：

```swift
func pageIndex(pageCount: Int, pageIndex: Int, progress: Double, usesPageIndex: Bool) -> Int {
    guard pageCount > 0 else { return 0 }
    let index = usesPageIndex ? pageIndex : Int(progress * Double(pageCount))
    return min(max(index, 0), pageCount - 1)
}

func pageProgress(pageCount: Int, pageIndex: Int, progress: Double, usesPageIndex: Bool) -> Double {
    guard pageCount > 0, usesPageIndex else {
        return min(max(progress, 0), 1)
    }
    let last = pageCount - 1
    if pageIndex < 1 { return 0 }
    if pageIndex >= last { return 1 }
    return Double(pageIndex) / Double(last)
}
```

## 5. CoreText 分页和富文本排版

### 5.1 `PaibanManager`

新建 Swift 版 `PaibanManager`，职责对齐原 App：

- 持有当前排版配置。
- 生成正文和标题富文本属性。
- 对章节正文做规范化。
- 执行 CoreText 分页。
- 提供页码和 progress 互转。
- 给纵向滚动返回页面块高度。

核心入口：

```swift
func divideText(
    _ text: String,
    chapterTitle: String,
    chapterIndex: Int,
    pageSize: CGSize,
    doubleColumn: Bool,
    returnsHeights: Bool
) -> ReaderDivisionResult
```

第一版只做单栏。双栏接口先保留，避免后续 API 再变。

### 5.2 文本规范化

按原 App 逻辑：

- 章节正文为空时，使用“当前章节无内容”。
- 正文 trim 首尾空白和换行。
- 用正则规范化多余换行：

```regex
\s*[\r\n]+\s*
```

- 标题在正文前。
- 首行缩进由 `headIndent` 控制。
- 标题和正文使用不同属性。

### 5.3 排版配置

默认值对齐原 App：

| 场景 | 上边距 | 下边距 | 左右边距 | 行距 | 段距 | 字距 | 首行缩进 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 普通 iPhone | 50 | 30 | 20 | 10 | 14 | 0 | 2 |
| 刘海屏 | 72 | 46 | 20 | 10 | 14 | 0 | 2 |
| iPad | 87 | 60 | 44 | 10 | 14 | 0 | 2 |

字号和字重：

- 默认字号：`20`。
- 正文字重：`0`。
- 标题字重：`3`。
- 标题字号偏移：`1`。
- 标题行距：`10`。
- 标题段距：`14`。
- 标题字距：`0`。

### 5.4 字体和字重

当前 Yomink 使用 `UIFont.Weight`。新阅读核心改成更接近原 App：

- 字体选择交给 `ReaderFontManager`。
- 默认使用系统字体。
- 支持导入字体时再接现有字体导入能力。
- 字重优先使用 `NSStrokeWidthAttributeName` 表达。
- `fontWeight/titleFontWeight` 范围按原 App 保留 `-10...10`。

富文本属性核心形态：

```swift
[
    .font: font,
    .paragraphStyle: paragraphStyle,
    .kern: wordSpacing,
    .strokeWidth: fontWeight,
    .foregroundColor: contentColor
]
```

## 6. 页面绘制

新建 `TextReadViewBase` 和 `TextReadView`，替代旧 `CollectionCoreTextPageView`。

### 6.1 `TextReadViewBase`

职责：

- 保存 `NSAttributedString`。
- 叠加当前主题正文色。
- 创建和释放 `CTFrame`。
- 在 bounds 或主题变化时重建 frame。
- 触发 `setNeedsDisplay()`。

### 6.2 `TextReadView`

职责：

- 翻转 Core Graphics 坐标系。
- 绘制选中文本背景。
- 绘制朗读或搜索高亮背景。
- 调用 `CTFrameDraw`。

绘制流程固定：

```swift
context.textMatrix = .identity
context.translateBy(x: 0, y: bounds.height)
context.scaleBy(x: 1, y: -1)
CTFrameDraw(frame, context)
```

## 7. 翻页容器

新阅读核心不再以 `UICollectionView` 作为统一容器目标。三个模式按原 App 拆开。

### 7.1 翻页类型

只保留三种：

```swift
enum ReaderTurnPageType: Int {
    case horizontalScroll = 0
    case pageCurl = 1
    case verticalContinuous = 3
}
```

不实现原 App 中的“上下平移 page view”模式。

### 7.2 左右平移

使用 `UIPageViewController`：

- `transitionStyle = .scroll`
- `navigationOrientation = .horizontal`
- `doubleSided = false`
- spine location 使用 `.min`

职责：

- 提供上一页和下一页。
- 预取相邻页。
- 翻页完成后保存阅读记录。
- 切换章节时通过 `PaibanManager` 重新分页。

### 7.3 仿真翻页

使用 `UIPageViewController`：

- `transitionStyle = .pageCurl`
- `navigationOrientation = .horizontal`
- `doubleSided = true`

必须处理：

- 背页背景不能露白。
- 背面使用当前主题背景镜像或同色图层。
- 工具栏显示时暂停交互冲突。
- 进度保存只在翻页完成后触发。

这是当前旧阅读器和原 App 差异最大的地方，必须重写。

### 7.4 纵向连续滚动

使用 `UITableView`：

- 一个 section 对应一个章节。
- 一个 row 对应章节分页后的一个页面块。
- `heightForRow` 使用 `PaibanManager` 返回的高度。
- 缺失高度时回退到屏幕高度。

数据结构：

```swift
struct ReaderScrollSection {
    var chapterIndex: Int
    var title: String
    var timestamp: Date
    var items: [NSAttributedString]
    var heights: [CGFloat]
}
```

滚动结束保存进度：

- `scrollViewDidEndDragging`
- `scrollViewDidEndDecelerating`

上拉/下拉章节加载第一版可先用原生触底逻辑，后续再评估是否引入类似 `MJRefresh` 的体验。

## 8. 主题系统

新建 `ReaderThemeManager`。

职责：

- 管理当前主题。
- 管理暗黑模式。
- 提供背景色、正文色、页眉色。
- 加载背景图。
- 主题变化时通知页面、容器、菜单刷新。

默认暗黑主题：

```json
{
  "content": "147,151,158",
  "header": "109,113,121",
  "bg": "22"
}
```

默认普通纹理主题：

```json
{
  "themeId": "200",
  "content": "62",
  "bg": "249",
  "header": "176",
  "img": "theme_bg5",
  "imgStyle": "2"
}
```

颜色解析支持：

- `"249"` 灰度值。
- `"147,151,158"` RGB 值。

主题变化后必须刷新：

- 页面背景。
- 背景图。
- 正文富文本颜色。
- 页眉页脚 widget 颜色。
- 状态栏样式。

## 9. 自动阅读

自动阅读按原 App 逻辑绑定纵向连续滚动容器。

### 9.1 范围

第一版只在 `verticalContinuous` 模式开放自动阅读。

如果当前是左右平移或仿真翻页：

- 默认建议提示用户切换到上下滑动后再自动阅读。
- 不做“定时翻页”版本，因为这不是原 App 的主实现路径。

### 9.2 驱动

使用 `CADisplayLink`：

- 开始自动阅读时创建。
- 暂停、退出、后台、离开阅读器时释放。
- 滚动视图正在拖拽、追踪、减速时不推进。
- 每帧根据速度和屏幕 scale 增加 `contentOffset.y`。

速度来自 `ReaderSettings` 或新 V2 设置：

- `autoReadRateMin`
- `autoReadRateMax`
- `autoReadRate`

### 9.3 保存进度

- 自动阅读过程中节流保存。
- 停止自动阅读时立即保存。
- 到章节底部时触发下一章加载。
- 到全书末尾时退出自动阅读。

当前旧自动阅读逻辑可以作为参考，但不直接复用。

## 10. 状态栏和小横条

这一块必须重构，不沿用旧实现。

### 10.1 状态栏

设置语义：

- `0`：隐藏状态栏。
- `1`：白色状态栏。
- `3`：黑色状态栏。

规则：

```swift
override var preferredStatusBarStyle: UIStatusBarStyle {
    if statusBarStatus == 1 {
        return .lightContent
    }
    return .default
}
```

```swift
override var prefersStatusBarHidden: Bool {
    if !viewVisible { return false }
    if UIDevice.current.userInterfaceIdiom == .pad { return false }
    if view.window?.bounds != UIScreen.main.bounds { return false }
    return statusBarStatus == 0
}
```

状态栏更新动画：

```swift
override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
    .slide
}
```

菜单显示、隐藏时统一调用：

```swift
setNeedsStatusBarAppearanceUpdate()
```

### 10.2 Home Indicator

按原 App 规则：

```swift
override var prefersHomeIndicatorAutoHidden: Bool {
    settings.autoHideHomeIndicator
}
```

```swift
override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
    settings.autoHideHomeIndicator ? .bottom : []
}
```

设置变化、工具栏变化、阅读页重新显示时调用：

```swift
setNeedsUpdateOfHomeIndicatorAutoHidden()
setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
```

### 10.3 屏幕常亮

进入阅读页：

```swift
UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwake
```

离开阅读页：

```swift
UIApplication.shared.isIdleTimerDisabled = false
```

## 11. 设置面板

设置面板按新阅读核心重新接线。

第一版必须支持：

- 字号。
- 主题。
- 翻页方式。
- 排版。
- 屏幕常亮。
- 自动隐藏 Home Indicator。
- 状态栏显示。
- 页眉页脚显示项。

设置变更流程：

1. 更新 V2 设置模型。
2. 持久化到现有 repository。
3. 通知 `PaibanManager` 和 `ReaderThemeManager`。
4. 当前容器按当前阅读记录重开。
5. 状态栏和 Home Indicator 刷新。

## 12. 接入目录、搜索、书签

这些功能不重写页面，但要适配新阅读器。

### 12.1 目录

目录点击：

```text
Chapter -> ReaderRecord(chapterIndex, progress: 0)
```

然后交给当前容器跳转。

### 12.2 搜索

搜索结果当前是：

```swift
ReaderContentTarget(chapterID: chapterID, offset: offset)
```

适配流程：

1. 找到 chapterID 对应 chapterIndex。
2. 将 offset 转成章节内 progress。
3. 生成 `ReaderRecord`。
4. 交给 `ReaderCoreV2` 重新分页并跳转。

### 12.3 书签

书签继续保存：

- `chapterID`
- `offset`
- `preview`

打开时同搜索结果一样转成 `ReaderRecord`。

## 13. 实施阶段

### 阶段进度总表

最后更新：2026-06-09

| 阶段 | 状态 | 已完成进度 | 下一步计划 | 备注 |
| --- | --- | --- | --- | --- |
| Phase 0：准备和冻结旧阅读器 | 已收尾 | `ReaderV2` 目录已建立；旧入口默认保留；`ReaderV2HostView` 已新增；`usesReaderV2 = false` 开关已接入；固定测试 TXT 已准备 | 进入 Phase 1 验收和补强 | 30MB 压测书用确定性脚本生成，生成物不入库 |
| Phase 1：模型和数据桥接 | 已完成 | `ReaderPageModel`、`ReaderRecord`、`ReaderBookAdapter`、`ReaderChapterProvider`、`ReaderProgressBridge`、`ReaderRecordBridge` 已落地；章节正文读取、进度恢复、目录/搜索/书签目标转换已有测试 | 进入 Phase 2 收尾和验收 | 当前 Windows 环境没有 `swift` / `xcodebuild`，需在 Xcode 环境补跑 |
| Phase 2：排版和分页核心 | 已完成 | `ReaderFontManager`、`ReaderLayout`、`ReaderPageCalculator`、`PaibanManager` 已完成本阶段目标；单章 CoreText 分页、富文本属性、纵向高度、双栏 API 单栏降级、极小页面边界和进度换算均有单测覆盖 | 进入 Phase 3 收尾和验收：补 `ReaderPageBackgroundView`、选中/高亮绘制、主题背景图刷新 | 当前 Windows 环境没有 `swift` / `xcodebuild`；已完成 `git diff --check` 和 pbxproj 重复对象检查 |
| Phase 3：页面绘制 | 进行中 | `TextReadViewBase`、`TextReadView`、`ReaderPageViewController` 已落地，可绘制 attributed page | 补 `ReaderPageBackgroundView`、选中/高亮绘制、主题背景图 | 页面背景图尚未接入 |
| Phase 4：三种容器 | 未开始 | 最小 `UIPageViewController` 宿主已能承载左右/仿真翻页雏形 | 拆出 `ReaderPageContainer`、`ReaderPageCurlContainer`、`ReaderScrollContainer` | 纵向滚动未开始 |
| Phase 5：主题、菜单和设置 | 未开始 | V2 已能从现有 `ReaderSettings` 映射布局和主题 | 新建 `ReaderThemeManager`、菜单、设置面板 | 暂不复用旧菜单 |
| Phase 6：自动阅读和系统外观 | 未开始 | V2 控制器已集中处理基础状态栏、Home Indicator、常亮 | 新建 `ReaderAutoReadController`、`ReaderSystemAppearanceController` | 自动阅读绑定纵向滚动容器 |
| Phase 7：替换入口和删除旧核心 | 未开始 | 旧入口仍作为默认回滚路径 | V2 稳定后再把 `usesReaderV2` 切到默认入口 | 不在 Phase 0 替换入口 |

### Phase 0：准备和冻结旧阅读器

目标：

- 旧阅读器不再扩展新能力。
- 新建 `ReaderV2` 目录。
- 保留旧阅读器入口作为回滚开关。

任务：

- 新增 `ReaderV2HostView`，暂时不接默认入口。
- 新增 feature flag 或临时调试入口。
- 准备 3 本固定测试 TXT：短篇、普通长篇、30MB 压测书。

收尾记录：

| 项目 | 状态 | 落点 | 说明 |
| --- | --- | --- | --- |
| 冻结旧阅读器 | 完成 | `Yomink/Presentation/Reader/` | 后续除回滚和阻塞修复外，不继续扩展旧 `CollectionReaderViewController` 体系 |
| 新建 `ReaderV2` 目录 | 完成 | `Yomink/Presentation/ReaderV2/` | 已包含 `Bridge`、`Core`、`Rendering`、`Theme`、`Chrome`、`Integration` |
| 保留旧入口作为回滚 | 完成 | `Yomink/Presentation/Library/LibraryView.swift` | 默认仍走 `ReaderHostView` |
| 新增 `ReaderV2HostView` | 完成 | `Yomink/Presentation/ReaderV2/Integration/ReaderV2HostView.swift` | 已接入但不作为默认入口 |
| 新增 feature flag | 完成 | `LibraryView.usesReaderV2` | 当前值为 `false` |
| 固定短篇 TXT | 完成 | `YominkTests/Fixtures/ReaderV2/short-story.txt` | 用于短章节和小页数冒烟 |
| 固定普通长篇 TXT | 完成 | `YominkTests/Fixtures/ReaderV2/normal-long.txt` | 用于多章节、分页和进度恢复冒烟 |
| 30MB 压测 TXT | 完成 | `YominkTests/Fixtures/ReaderV2/generate_large_fixture.swift` | 当前工作区已生成 `large-30mb.generated.txt`，大小 30 MiB；生成物被 `.gitignore` 排除 |

### Phase 1：模型和数据桥接

目标：

- 新阅读器能读取当前 `Book/Chapter/content.txt`。
- 能把现有 `ReadingProgress` 转成 `ReaderRecord`。

任务：

- 实现 `ReaderBookAdapter`。
- 实现 `ReaderChapterProvider`。
- 实现 `ReaderProgressBridge`。
- 实现 `ReaderPageModel` 和 `ReaderRecord`。

验收：

- 新阅读器能拿到章节列表和章节正文。
- 能恢复到当前保存位置附近。

收尾记录：

| 项目 | 状态 | 落点 | 说明 |
| --- | --- | --- | --- |
| `ReaderPageModel` | 完成 | `Yomink/Presentation/ReaderV2/Core/ReaderPageModel.swift` | 对齐原 App 页模型字段，负责章节数、当前章、页数、页码、章内进度和页面状态 |
| `ReaderRecord` | 完成 | `Yomink/Presentation/ReaderV2/Core/ReaderRecord.swift` | 作为 V2 内部跳转和恢复记录，不直接暴露 `ReadingProgress` |
| `ReaderBookAdapter` | 完成 | `Yomink/Presentation/ReaderV2/Bridge/ReaderBookAdapter.swift` | 从现有 `Book`、`Chapter`、`AppFileStore` 派生章节读取、进度桥接、记录桥接 |
| `ReaderChapterProvider` | 完成 | `Yomink/Presentation/ReaderV2/Bridge/ReaderChapterProvider.swift` | 支持同步/异步按章节读取 UTF-8 正文；缺章和解码失败有明确错误 |
| `ReaderProgressBridge` | 完成 | `Yomink/Presentation/ReaderV2/Bridge/ReaderProgressBridge.swift` | 支持 `ReadingProgress -> ReaderRecord` 和 `ReaderPageModel -> ReadingProgress`；`chapterID` 缺失时用 `globalProgress` 兜底 |
| `ReaderRecordBridge` | 完成 | `Yomink/Presentation/ReaderV2/Bridge/ReaderRecordBridge.swift` | 支持目录章节、`ReaderContentTarget`、`Bookmark` 转 `ReaderRecord` |
| 验收：章节列表和正文读取 | 完成 | `YominkTests/ReaderV2CoreTests.swift` | 覆盖 `ReaderBookAdapter` 和 `ReaderChapterProvider` 的真实临时文件读取 |
| 验收：恢复到保存位置附近 | 完成 | `YominkTests/ReaderV2CoreTests.swift` | 覆盖已保存进度、`chapterID` 缺失兜底、页模型写回 `ReadingProgress` |

### Phase 2：排版和分页核心

目标：

- 完成 `PaibanManager`。
- 能把单章文本分页成 attributed pages。

任务：

- 实现排版配置。
- 实现富文本属性。
- 实现 CoreText 分页。
- 实现纵向模式高度返回。
- 实现 progress 和 pageIndex 互转。

验收：

- 单章能分页。
- 字号、边距、行距变化后分页结果变化合理。
- 空章节不崩溃。

收尾记录：

| 项目 | 状态 | 落点 | 说明 |
| --- | --- | --- | --- |
| 读取 Phase 2 计划和进度 | 完成 | `docs/READER_REFACTOR_PLAN.md` | 本轮开始前已读取阶段进度总表和 Phase 2 目标、任务、验收项 |
| `ReaderFontManager` | 完成 | `Yomink/Presentation/ReaderV2/Core/ReaderFontManager.swift` | 默认使用系统字体；预留字体名接入；规整字号下限和 `-10...10` 字重范围 |
| 排版配置 | 完成 | `Yomink/Presentation/ReaderV2/Core/ReaderLayout.swift` | 保留普通 iPhone、刘海屏、iPad 默认边距、行距、段距、字距、首行缩进、标题字号偏移 |
| 富文本属性 | 完成 | `Yomink/Presentation/ReaderV2/Core/PaibanManager.swift` | 标题和正文分别生成 `.font`、`.paragraphStyle`、`.kern`、`.strokeWidth`、`.foregroundColor`；标题换行归入标题段落属性 |
| 文本规范化和空章节 | 完成 | `Yomink/Presentation/ReaderV2/Core/PaibanManager.swift` | 正文 trim 后按正则规整多余换行；空章节使用本地化文案并提供中文兜底 |
| CoreText 分页 | 完成 | `Yomink/Presentation/ReaderV2/Core/PaibanManager.swift` | 使用 `CTFramesetter`/`CTFrame` 按页面尺寸切分 attributed pages；极小页面也会逐字符兜底消费文本 |
| 纵向模式高度返回 | 完成 | `Yomink/Presentation/ReaderV2/Core/PaibanManager.swift` | `returnsHeights` 打开时返回 CoreText 实际使用高度，关闭时返回页面高度 |
| 双栏接口行为 | 完成 | `Yomink/Presentation/ReaderV2/Core/PaibanManager.swift` | `doubleColumn` 请求会记录在结果中；第一版明确降级为单栏，`usesDoubleColumn = false`，后续 API 不变 |
| progress 和 pageIndex 互转 | 完成 | `Yomink/Presentation/ReaderV2/Core/ReaderPageCalculator.swift`、`Yomink/Presentation/ReaderV2/Core/PaibanManager.swift` | `PaibanManager` 暴露转换入口并复用 `ReaderPageCalculator` 公式 |
| 验收：单章分页 | 完成 | `YominkTests/ReaderV2CoreTests.swift` | 覆盖多页切分、连续 `displayRange` 和分页后文本拼接一致 |
| 验收：字号、边距、行距重排 | 完成 | `YominkTests/ReaderV2CoreTests.swift` | 覆盖字号/行距增大、左右边距变窄后的页数变化 |
| 验收：空章节和分页边界 | 完成 | `YominkTests/ReaderV2CoreTests.swift` | 覆盖空章节占位、极小页面兜底、纵向高度、双栏接口、富文本属性和字体范围 |
| 静态验证 | 完成 | Windows 本地环境 | `git diff --check` 通过；pbxproj 无重复对象；当前环境缺少 `swift` / `xcodebuild`，需要在 Xcode 环境补跑 XCTest |

### Phase 3：页面绘制

目标：

- 完成 CoreText 自绘页面。

任务：

- 实现 `TextReadViewBase`。
- 实现 `TextReadView`。
- 实现页面背景。
- 接入主题正文色。

验收：

- 页面显示稳定。
- 旋转、尺寸变化后重绘正确。
- 主题切换后正文颜色刷新。

### Phase 4：三种容器

目标：

- 完成左右平移、仿真翻页、纵向滚动。

任务：

- 实现 `ReaderPageContainer`。
- 实现 `ReaderPageCurlContainer`。
- 实现 `ReaderScrollContainer`。
- 实现容器切换。
- 实现翻页完成保存记录。

验收：

- 三种翻页模式可用。
- 切换模式后位置不丢。
- 仿真翻页背面不露白。
- 纵向滚动按章节和页面块加载。

### Phase 5：主题、菜单和设置

目标：

- 阅读器可正常展示菜单和设置。

任务：

- 实现 `ReaderThemeManager`。
- 实现顶部和底部菜单。
- 实现设置面板。
- 接入字号、主题、翻页、排版。

验收：

- 设置变化触发重排。
- 菜单显示隐藏不影响翻页状态。
- 暗黑和普通主题切换稳定。

### Phase 6：自动阅读和系统外观

目标：

- 自动阅读、状态栏、小横条按原 App 规则运行。

任务：

- 实现 `ReaderAutoReadController`。
- 实现 `ReaderSystemAppearanceController`。
- 接入屏幕常亮。
- 接入状态栏设置。
- 接入 Home Indicator 设置。

验收：

- 自动阅读退出后没有残留 display link。
- 后台回来不会重复启动。
- 状态栏规则符合设置。
- 小横条自动隐藏和底部手势延迟符合设置。

### Phase 7：替换入口和删除旧核心

目标：

- `ReaderCoreV2` 替换旧阅读器。

任务：

- 书架打开阅读器走 V2。
- 目录、搜索、书签跳转走 V2。
- 旧阅读器保留一个版本周期作为回滚。
- 稳定后删除旧 `CollectionReaderViewController` 体系。

验收：

- 导入、打开、翻页、搜索、书签、设置、自动阅读全链路可用。
- 1MB、10MB、30MB TXT 真机验证通过。
- 静止阅读无持续 CPU 活动。

## 14. 测试计划

### 单元测试

- `ReaderPageCalculatorTests`
- `ReaderProgressBridgeTests`
- `PaibanManagerPaginationTests`
- `ReaderThemeManagerTests`
- `ReaderLayoutTests`

重点覆盖：

- `progress -> pageIndex`。
- `pageIndex -> progress`。
- 空章节。
- 标题样式。
- 字号和边距变化后的重排。
- 颜色字符串解析。

### 手工真机测试

- 左右平移连续翻 100 页。
- 仿真翻页连续翻 50 页。
- 纵向滚动跨章节。
- 自动阅读 10 分钟。
- 切字号后恢复当前章节位置。
- 切主题后页面不闪白。
- 隐藏状态栏。
- 自动隐藏小横条。
- 进入后台再回来。
- 搜索结果跳转。
- 书签跳转。

### 性能测试

- 30MB TXT 打开耗时。
- 连续翻页内存增长。
- 静止阅读 CPU。
- 自动阅读 Energy。
- 纵向滚动掉帧。

## 15. 风险

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| 新旧阅读器并行时间较长 | 代码量临时增加 | 旧阅读器冻结，只做回滚 |
| `UIPageViewController` 接入现有导航栈有冲突 | 返回手势、状态栏异常 | V2 内部集中处理系统外观 |
| 仿真翻页背页背景处理不好 | 翻页露白 | 单独做 `ReaderPageBackgroundView` |
| `UITableView` 纵向滚动跨章节定位复杂 | 自动阅读和跳转不准 | 先实现单章，再扩到前后章节加载 |
| offset 和 progress 桥接误差 | 搜索/书签跳转偏移 | 单元测试覆盖转换公式 |
| 主题切换重排成本高 | 卡顿 | 只重排当前章节和相邻页面 |

## 16. 第一批任务

第一批只做新核心地基，不替换入口：

1. 新建 `ReaderV2` 目录。
2. 实现 `ReaderPageModel`、`ReaderRecord`、`ReaderTurnPageType`。
3. 实现 `ReaderBookAdapter` 和 `ReaderChapterProvider`。
4. 实现 `ReaderProgressBridge`。
5. 实现 `PaibanManager` 的最小分页能力。
6. 实现 `TextReadView` 显示第一页。

第一批完成后，目标是：**从一本现有书打开 ReaderV2 调试入口，显示当前章节第一页。**
