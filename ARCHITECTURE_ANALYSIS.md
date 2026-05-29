# Yomink iOS 阅读器架构分析

## 项目概览

Yomink 是一款原生 iOS TXT 阅读器，目标系统 iOS 15.5+，采用 SwiftUI + UIKit 混合架构，使用 GRDB 作为数据库，纯本地运行，无网络依赖。

## 核心架构层次

### 1. 数据层 (Data Layer)

#### 文件存储 (`AppFileStore`)
- **位置**: `Documents/Books/{bookId}/content.txt`
- **编码**: 统一转换为 UTF-8 存储
- **数据库**: `Library/Application Support/Database/yomink.sqlite`
- 导入时将原始编码文件转为 UTF-8，避免阅读时反复解码

#### 文本解码 (`TXTTextDecoder`)
- 支持编码: UTF-8, UTF-8 BOM, GBK, GB2312, GB18030
- 导入阶段识别编码并转换为 UTF-8

#### 章节索引 (`ChapterIndexer`)
- **正则匹配规则**:
  - 中文章节: `第X章/回/节/折/卷/部/篇/集`
  - 中文卷号: `卷X`
  - 英文章节: `Chapter X`
  - 数字标题: `1. 标题` (需至少3个候选才保留)
  - 特殊标题: 前言、引子、序、楔子、后记、番外等
  
- **启发式过滤**:
  - 标题长度 < 50 字符
  - 排除以句末标点结尾的行 (。！？及其后的引号)
  - 数字标题与常规章节冲突时需达到最小候选数
  
- **序章处理**: 第一个章节标题之前的内容单独生成"序"章节
- **伪章节回退**: 无章节时按 128KB 固定块切分，标题为"第X章"

#### 数据库 (GRDB)
- **核心表**: books, chapters, reading_progress, bookmarks, filter_rules, groups
- **日期格式**: UTC ISO8601 with fractional seconds
- **章节来源**: `source` 字段标记 `regex` 或 `pseudo`

### 2. 领域层 (Domain Layer)

#### 核心模型
- **Book**: 书籍元数据 (id, title, author, sourcePath, wordCount, etc.)
- **Chapter**: 章节信息 (id, bookID, title, startOffset, endOffset, sortOrder, source)
- **ReadingProgress**: 阅读进度 (bookID, chapterID, chapterOffset, globalProgress)
- **ReaderSettings**: 阅读器设置 (pageMode, theme, fontSize, layoutValues, etc.)

#### 服务
- **ImportService**: 导入流程 - 编码识别 → UTF-8转换 → 章节索引 → 数据库写入
- **LibraryRepository**: 数据库操作抽象层

### 3. 表现层 (Presentation Layer)

#### SwiftUI 部分
- 书架 (`LibraryView`)
- 侧边栏 (左侧分组管理、右侧导入/足迹)
- 设置页面
- 书籍详情

#### UIKit 阅读器核心 (`CollectionReaderViewController`)

这是整个阅读引擎的核心，采用 **UICollectionView + CoreText** 架构。

## 阅读引擎详细架构

### 核心组件

#### 1. CollectionReaderViewController
- 主控制器，管理整个阅读界面
- 使用 `UICollectionView` 作为页面容器
- 支持三种翻页模式: paged (平移), curl (仿真), scroll (滚动)

#### 2. CollectionReaderPage (数据结构)
```swift
struct CollectionReaderPage {
    let id: String
    let bookID: UUID
    let chapterID: UUID
    let chapterTitle: String
    let pageIndex: Int              // 全书页码
    let localPageIndex: Int         // 章节内页码
    let chapterPageCount: Int       // 章节总页数
    let startAbsoluteOffset: Int    // 全书字节偏移
    let endAbsoluteOffset: Int
    let startChapterOffset: Int     // 章节内偏移
    let globalProgress: Double      // 全书进度百分比
    let attributedText: NSAttributedString  // 渲染用富文本
    let text: String                // 原始文本
    let verticalExtent: CGFloat     // 垂直滚动模式高度
}
```

#### 3. CollectionReaderPageCell
- UICollectionViewCell 子类
- 包含 `CollectionCoreTextPageView` (CoreText 渲染视图)
- 包含 `ReaderPageWidgetOverlayView` (状态栏小部件)

#### 4. CollectionCoreTextPageView
- 使用 **CoreText** 进行文本渲染
- 核心渲染流程:
  ```swift
  override func draw(_ rect: CGRect) {
      let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
      let frame = CTFramesetterCreateFrame(framesetter, ...)
      CTFrameDraw(frame, context)
  }
  ```

### 分页引擎流程

#### 1. 初始加载 (`startInitialLoad`)
```
加载书籍数据 → 获取章节列表 → 获取阅读进度 → 获取过滤规则 → 打开页面
```

#### 2. 页面生成 (`openPage` → `CollectionReaderPaginator.makePage`)
```
1. 确定目标章节 (根据 absoluteOffset)
2. 读取章节文本 (从 content.txt)
3. 应用过滤规则 (ReaderTextFilter)
4. 构建 AttributedString (字体、行距、段距、首行缩进等)
5. CoreText 分页 (buildPages)
6. 生成 CollectionReaderPage 数组
```

#### 3. CoreText 分页算法 (`buildPages`)
```swift
private func buildPages(fittingSize: CGSize) {
    let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
    var startIndex = 0
    
    while startIndex < textLength {
        // 创建一页的 CTFrame
        let frame = CTFramesetterCreateFrame(framesetter, 
                                             CFRange(location: startIndex, length: 0),
                                             path, nil)
        // 获取可见范围
        let visibleRange = CTFrameGetVisibleStringRange(frame)
        // 记录页面信息
        pages.append(...)
        startIndex += visibleRange.length
    }
}
```

### 内存管理策略

#### 常驻页面限制
- **最大常驻页数**: 14 页 (`maximumResidentPages`)
- **水平预取距离**: 4 页 (`horizontalPrefetchDistance`)

#### 页面缓存机制
- 只缓存当前页及前后若干页
- 超出范围的页面会被移除 (`trimResidentPagesIfNeeded`)
- 滚动/翻页时动态加载相邻页面

#### 延迟加载策略
- **头部 prepend**: 拖动期间暂存到 `pendingPagePrepends`，静止后批量提交
- **尾部 append**: 直接插入，避免滑动时撞到边界
- 避免在滚动期间修改 contentOffset

### 文本过滤引擎 (`ReaderTextFilter`)

#### FilteredReaderText 结构
```swift
struct FilteredReaderText {
    let displayText: String                      // 过滤后的显示文本
    let originalByteOffsetsByUTF16Index: [Int]  // UTF-16索引到原始字节偏移的映射
}
```

#### 过滤流程
1. **规则应用**: 顺序替换所有过滤规则
2. **空行移除**: 移除只包含空白的行
3. **偏移映射**: 维护显示文本到原始文本的字节偏移映射

#### 偏移映射的重要性
- 用户看到的是过滤后的文本
- 阅读进度保存的是原始文件的字节偏移
- 需要双向转换: `displayUTF16Index ↔ originalByteOffset`

### 排版系统 (`ReaderSettings.LayoutValues`)

#### 可调参数
- **正文**: bodyKern, bodyLineSpacing, bodyParagraphSpacing, bodyMargins, bodyFontWeight, firstLineIndent
- **标题**: titleKern, titleLineSpacing, titleParagraphSpacing, titleFontWeight, titleFontSizeDelta
- **小部件**: widgetMargins

#### 预设档位
- **紧凑** (compact): 行距6, 段距8, 边距16
- **标准** (standard): 行距10, 段距14, 边距20
- **宽松** (relaxed): 行距14, 段距20, 边距24
- **自定义** (custom): 用户精确调节

### 自动阅读模式

#### 实现机制
- 使用 `CADisplayLink` 驱动滚动
- 速度范围: 20-180 (单位待确认)
- 自动阅读时禁用中央点击唤出菜单
- 后台/锁屏时自动暂停

#### 生命周期管理
```swift
// 启动
autoReadDisplayLink = CADisplayLink(target: self, selector: #selector(autoReadTick))
autoReadDisplayLink?.add(to: .main, forMode: .common)

// 停止
autoReadDisplayLink?.invalidate()
autoReadDisplayLink = nil
```

### 性能优化要点

#### 1. 内存控制
- ✅ 不将整本书常驻内存
- ✅ 只持有当前块及相邻块
- ✅ 页面数量限制 (14页)
- ✅ 超出范围自动修剪

#### 2. CPU 优化
- ✅ 静止时无持续计时器 (CADisplayLink 只在自动阅读时启用)
- ✅ 分页计算异步执行 (Task.detached)
- ✅ 避免主线程阻塞

#### 3. 渲染优化
- ✅ CoreText 硬件加速
- ✅ 页面复用 (UICollectionView cell reuse)
- ✅ 按需重绘 (setNeedsDisplay)

### 进度保存策略

#### 保存时机
- App 进入后台
- 阅读器退出 (viewWillDisappear)
- 页面切换稳定后节流保存
- **不在**每帧或每次滚动回调中写库

#### 进度数据
```swift
struct ReadingProgress {
    var bookID: UUID
    var chapterID: UUID?
    var chapterOffset: Int64      // 章节内字节偏移
    var globalProgress: Double    // 全书百分比 (0.0-1.0)
}
```

## 关键技术点总结

### 1. 编码处理
- 导入时统一转 UTF-8
- 避免阅读时反复解码
- 支持常见中文编码

### 2. 章节识别
- 多规则正则匹配
- 启发式过滤误判
- 伪章节兜底

### 3. 分页引擎
- CoreText 精确分页
- 页面缓存与修剪
- 延迟加载优化

### 4. 文本过滤
- 实时过滤显示
- 偏移映射维护
- 进度保存到原始位置

### 5. 内存管理
- 常驻页面限制
- 动态加载卸载
- 目标峰值 ≤ 50MB

### 6. 性能保证
- 静止时 CPU → 0
- 60fps 翻页动画
- 异步分页计算

## 待优化项 (Phase 3 暂缓记录)

1. **滚动模式字体切换**: 当前依赖主线程 UITextView 布局，可能阻塞帧
2. **双文本层翻页过渡**: 当前旧页滑出后切换内容，需补双视图连续进入
3. **滚动预取冷却**: 滚动期间预取检查可能增加主线程压力

## 文件结构

```
Yomink/
├── App/
│   ├── YominkApp.swift           # SwiftUI 入口
│   ├── AppServices.swift         # 依赖注入容器
│   └── AppEnvironment.swift      # 环境配置
├── Data/
│   ├── Database/
│   │   ├── AppDatabase.swift     # GRDB 配置
│   │   ├── GRDBLibraryRepository.swift
│   │   └── Records/              # 数据库记录模型
│   ├── FileStore/
│   │   └── AppFileStore.swift    # 文件系统管理
│   ├── TextDecoder/
│   │   └── TXTTextDecoder.swift  # 编码识别
│   └── ChapterIndexer/
│       └── ChapterIndexer.swift  # 章节识别
├── Domain/
│   ├── Models/                   # 领域模型
│   │   ├── Book.swift
│   │   ├── ReadingProgress.swift
│   │   └── ImportedBookDraft.swift
│   └── Services/
│       ├── ImportService.swift   # 导入服务
│       └── LibraryRepository.swift
└── Presentation/
    ├── Library/
    │   └── LibraryView.swift     # SwiftUI 书架
    ├── Sidebars/                 # SwiftUI 侧边栏
    └── Reader/
        ├── ReaderHostView.swift  # UIKit 阅读器核心 (6000+ 行)
        ├── ReaderTextFilter.swift
        └── ReaderMoreViewControllers.swift
```

## 总结

Yomink 的阅读引擎采用了经典的 **UICollectionView + CoreText** 架构，通过精细的内存管理和页面缓存策略，实现了高性能的文本阅读体验。核心设计思想是：

1. **分离关注点**: 导入时处理编码和章节，阅读时只关注渲染
2. **按需加载**: 只加载可见页面及相邻页面，严格控制内存
3. **异步计算**: 分页计算在后台线程，避免阻塞 UI
4. **原生渲染**: CoreText 提供高性能文本渲染
5. **状态管理**: 清晰的生命周期和任务取消机制

整体架构清晰，职责分明，为后续功能扩展（全文搜索、书签、自动阅读等）提供了良好的基础。
