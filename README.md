# Yomink

<p align="center">
  <img src="Yomink/App/Assets.xcassets/AppIcon.appiconset/AppIcon-180.png" width="96" alt="Yomink 图标">
</p>

Yomink 是一款 iOS 纯本地 TXT 阅读器，目标是提供安静、顺手、可离线保存数据的个人阅读体验。项目借鉴了香色闺阁的部分阅读 UI 与交互习惯，但不包含其联网能力，也不接入书源、广告、统计或云同步服务。

当前正式版：`v1.0.0`

> [!NOTE]
> 本项目主要面向个人学习与自用场景。香色闺阁的名称、产品与相关权益归其原作者或权利方所有。

## 功能概览

- 纯本地 TXT 导入、整理、阅读、搜索、导出和删除。
- 支持从文件导入 TXT，也支持从文件夹批量导入 TXT。
- 支持 UTF-8、GBK、GB2312 等常见中文 TXT 编码识别与转换。
- 导入后自动识别章节；章节识别失败时会回落为伪章节，保证文本仍可阅读。
- 书架支持列表/网格视图、分组、标签、收藏、排序、全局书名搜索和搜索历史。
- 支持多选、反选、移动到分组、删除、批量导出 TXT。
- 阅读器支持目录、书签、内容搜索、内容过滤、阅读进度保存和章节跳转。
- 阅读设置支持字号、字重、描边、行距、段距、页边距、首行缩进、主题、翻页区域、屏幕常亮、状态栏/小横条隐藏、阅读小部件显示。
- 翻页方式支持左右平移、仿真翻页和上下连续阅读。
- 支持自动阅读、速度调整、暗黑主题快捷切换。
- 支持阅读足迹、随机抽书、标签管理、分组管理和存储管理。

## 纯本地说明

Yomink 当前没有业务网络请求入口，也没有集成广告、统计、追踪或崩溃上报 SDK。

书籍文件通过系统文件选择器导入。导入后，App 会把正文转换为 UTF-8 文本并复制到 App 私有目录；阅读进度、书签、过滤规则、标签、分组和设置保存在本地 SQLite 数据库中。导出时，Yomink 会通过系统分享面板把本地 TXT 副本交给用户选择的目标 App。

## 技术栈

- iOS 15.5+
- Swift 5
- SwiftUI
- UIKit
- CoreText
- GRDB / SQLite
- XCTest
- GitHub Actions unsigned IPA 构建流程

## 项目结构

```text
Yomink/
  App/              App 入口、环境装配、资源和 Info.plist
  Data/             SQLite、文件存储、TXT 解码、章节索引
  Domain/           业务模型、仓储协议、导入服务
  Presentation/
    Library/        书架、导入、标签、分组、足迹、存储管理
    ReaderV2/       阅读器、分页、翻页、目录、书签、搜索、过滤、自动阅读
    Sidebars/       侧边栏入口
YominkTests/        单元测试
.github/workflows/  unsigned IPA 构建与测试工作流
docs/               开发计划与重构记录
```

## 构建

1. 使用 Xcode 16 或更新版本打开 `Yomink.xcodeproj`。
2. 选择 `Yomink` scheme。
3. 选择 iOS 15.5+ 模拟器或真机。
4. 运行测试或构建 App。

本地命令行构建示例：

```bash
xcodebuild build \
  -project Yomink.xcodeproj \
  -scheme Yomink \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

运行单元测试示例：

```bash
xcodebuild test \
  -project Yomink.xcodeproj \
  -scheme Yomink \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## CI

仓库提供 GitHub Actions 工作流 `.github/workflows/build-unsigned-ipa.yml`：

- push 到 `main` 或 `codex/**` 时自动运行。
- 在 macOS runner 上解析 Swift Package、构建 unsigned IPA。
- 运行单元测试。
- 上传 `Yomink-unsigned.ipa` artifact，artifact 默认保留 14 天。

## 使用方式

1. 在书架侧边栏选择“从文件导入”或“从文件夹批量导入”。
2. 确认书名、作者、简介、分组和标签。
3. 导入完成后从书架打开书籍。
4. 阅读器内可打开目录、书签、搜索、过滤规则和阅读设置。
5. 需要备份或转移文本时，可从书架或存储管理中导出 TXT。

## 数据与隐私

- 书籍正文、数据库和导出临时文件都存放在本机。
- 不上传书籍、阅读记录、书签、搜索历史或设置。
- 删除书籍时会同步清理本地数据库记录和正文副本。
- 导出文件由系统分享面板交给用户选择的目标 App。

## Contributors

- 1048632280
- Codex

## TODO

- 分享功能：从其他 App 分享 TXT 到 Yomink，并进入导入流程。
