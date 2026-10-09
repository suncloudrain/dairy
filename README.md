# 日记与任务（dairy）

Flutter 个人日记与任务管理应用，Android / Windows，本地 SQLite，方案 A（轻量分层）。

当前已实现**日记新建、编辑和自动保存**，完整 v0.1 仍在开发中。产品范围见 [PRODUCT.md](docs/PRODUCT.md)，实际结构见 [ARCHITECTURE.md](docs/ARCHITECTURE.md)，长期取舍见 [DECISIONS.md](docs/DECISIONS.md)。

## 已建立的基础

- 官方 Flutter Android、Windows 平台工程；应用版本 `0.1.0+1`。
- 应用启动、初始化失败重试、中文 Material 本地化、窄屏底部导航和宽屏侧边导航。
- 日记列表、新建与编辑页；日记回收站和任务仍为只读列表，任务提供四类入口。
- “写今天”复用当天已有日记；“新建日记”可以选择日期，重复日期提示打开已有日记，不覆盖。
- 日记输入停顿约 800 毫秒、持续输入约 5 秒时自动保存；返回前等待最新内容写入，保存失败保留输入并支持重试。
- SQLite schema v1：两张表、有效日记日期唯一约束、软删除、任务状态一致性约束、索引和升级入口。
- 不可变日记／任务对象，独立日历日期与任务范围模型。
- 仓库接口：保存、查询、日记恢复、软删除、任务完成和撤销完成。重复保存同一 ID 不会新建第二条记录。
- 日期边界、仓库规则、数据库约束、文件持久化、拒绝降级及基础导航测试。

本阶段编辑已保存日记只改变内容与修改时间，创建时间和日记日期保持不变。新建草稿可在首次保存前选择日期。修改已保存日记日期、回收站详情与删除／复制／恢复按钮、任务编辑和状态操作及完整筛选界面仍待后续实现。

## 开发环境与运行

本次生成工程使用 Flutter **3.47.6 stable**、Dart **3.13.5**。依赖版本记录在 `pubspec.yaml` 和 `pubspec.lock`，应用项目应提交锁文件。

如果 Flutter 已在 PATH 中，可直接执行常规命令。Windows 也可使用项目辅助脚本：

```powershell
.\tool\flutter.cmd --version
.\tool\flutter.cmd pub get
.\tool\flutter.cmd analyze
.\tool\flutter.cmd test
.\tool\flutter.cmd run -d windows
```

脚本优先使用本机项目目录中的 `.tools/flutter`，否则查找 PATH 上的 Flutter；本地 SDK 与包缓存均被 Git 忽略。脚本不会自动安装 SDK，也不会修改系统 PATH 或全局 Git 配置。需要代理时仅在本次进程中复用系统代理，不保存机器特有代理地址。

Windows 的 `flutter.cmd` 可在 PowerShell 或 CMD 中调用。它启动一个单独的 Windows PowerShell 进程，以 `RemoteSigned` 策略运行本项目的 `flutter.ps1`，然后原样返回退出码；不更改用户或系统的永久执行策略。直接运行 `.ps1` 时若出现“此系统上禁止运行脚本”，改用 `.cmd` 入口。

克隆项目到新机器时 `.tools` 不随项目提供，需要自行安装相容的 Flutter SDK。不要提交 SDK、缓存或真实日记数据库。

平台前提：

- **Windows**：Visual Studio 的“使用 C++ 的桌面开发”工作负载及 Windows SDK；使用插件可能需要 Windows 开发者模式以创建符号链接。
- **Android**：Android SDK、相容 JDK、已接受的 SDK 许可，以及模拟器或已连接设备。运行 `flutter devices` 获取设备 ID，再运行 `flutter run -d <设备ID>`。
- **iOS**：仅在数据库驱动选择处保留兼容分支，当前没有生成或验证 iOS 工程；未来需要 macOS / Xcode 和完整适配验证。

使用 `flutter doctor -v` 检查本机环境。静态分析或 Widget 测试通过，不等于真机和发行构建通过。

## 目录与数据流

| 文件／目录 | 作用 |
| --- | --- |
| `lib/main.dart` | Flutter 入口 |
| `lib/app/app_dependencies.dart` | 选择驱动、打开应用数据目录中的数据库、组装仓库 |
| `lib/app/dairy_app.dart` | 中文主题、初始化加载／失败／重试 |
| `lib/app/app_shell.dart` | 主导航、窄宽屏适配 |
| `lib/features/` | 页面及 ChangeNotifier 页面状态；不直接接触 SQL |
| `lib/features/diary/diary_editor_page.dart` | 输入框、日期展示、保存反馈、返回保护与生命周期通知 |
| `lib/features/diary/diary_editor_model.dart` | 草稿内容、停顿／周期定时器、串行保存、版本判断和失败重试 |
| `lib/models/` | 数据对象、日历日期和四类任务范围 |
| `lib/data/repositories/` | 业务校验、UUID、时间赋值和事务操作入口 |
| `lib/data/database/schema.dart` | 表、约束、索引和 schema 版本 |
| `lib/data/database/*_queries.dart` | SQL 与 SQLite 行和数据对象之间的转换 |
| `test/` | 使用独立测试数据库，不访问用户数据库 |

启动：`main → DairyApp → AppDependencies.initialize → AppDatabase.open → 两个仓库 → AppShell`。

读取：`页面 → ListModel → Repository → Queries → SQLite → 数据对象 → ListModel 通知页面`。

日记保存：`输入框 onChanged → 编辑状态捕获快照 → Repository.save → 事务与约束 → 返回已持久化对象 → 更新保存状态`。同一编辑会话只使用一个 UUID，旧快照成功不等于当前最新输入已保存。

仓库是普通 Dart 对象，不依赖 Widget；数据库工厂和时间函数可在测试中替换。不引入状态管理包、ORM 或通用用例层。

## 数据与接口约定

- 数据库位于 `getApplicationSupportDirectory()` 返回目录下的 `dairy.sqlite`，不存入安装目录或源码中。
- 日记和任务 UUID 用仓库的 `newId()` 分配。在草稿生命周期内只分配一次，保存和重试复用同一 ID；仅分配 ID 不写入数据。
- 日记日期使用 `LocalDate`，任务范围使用 `TaskPeriod`；具体时刻以 UTC 毫秒入库。
- 仓库允许保存空正文；编辑页已实现“只打开不写入、开始输入才保存”的触发规则，已保存日记清空后仍存在。
- 普通保存拒绝修改已经软删除的记录，只有日记的显式 `restore` 可以恢复。
- 日记删除界面尚未实现；后续删除必须复用编辑状态的提交等待能力，并在删除后停止写入。
- 期望业务错误使用 `RepositoryException`，表示日期冲突、记录不可操作和输入无效；数据库错误不会被仓库伪装成成功。
- 页面不调用 `AppDatabase.connection`，只有数据层和数据库测试使用它。
- v1 没有历史版本需要迁移。未来升版需补充迁移与旧库样本测试；未知升级／降级明确失败，不删库。

## 手动验收基础工程

1. 运行 `.\tool\flutter.cmd run -d windows`，点击“写今天”；不输入就返回，列表不会新增空记录。
2. 再次进入，输入可选标题和多行中文正文，停顿后应显示“已保存”；持续输入时也会周期提交。
3. 输入最后一句后立即返回，再打开该日记，内容应包含最后一句。
4. 关闭并重新启动应用，日记仍在，正文与标题保持原样。只有显示“已保存”的内容才能视为已持久化。
5. 编辑内容，确认日记日期不变；清空标题与正文，保存后返回，日记仍存在。创建时间保留由数据库测试验证。
6. 点击右上角“新建日记”，选择其他日期补写；选择已有日记的日期时，提示打开已有日记，不创建第二篇。
7. 调整 Windows 窗口宽度、测试中文输入和滚动；回收站及任务入口仍可访问。

遇到保存失败时页面显示错误与“重试保存”，返回不会丢弃当前输入。进入后台或收到可取消退出通知时尽力提交；强制结束／断电不保证尚未写入的最后输入能够恢复。编辑页返回统一经过提交等待，因此 Android 系统返回使用此路径，预测性返回动画目前不是验收目标。

## 验证记录

2026-10-08 已执行：

- Dart 格式化：通过。
- `flutter analyze --no-pub`：通过，No issues found。
- `flutter test --no-pub`：17 项全部通过（4 项日期模型、10 项数据层、3 项 Widget 测试）。
- SQLite 真实文件写入／关闭／重新打开后保留内容及 UUID：通过。
- 拒绝较新 schema 降级且不删除旧数据：通过；测试日志中的预期降级错误不代表测试失败。
- 当日 `flutter doctor`：Flutter 可用；当时本机缺少 Android SDK 和 Visual Studio C++ 工具链，Android／Windows 真机运行及发行构建尚未验证。未配置全局 PATH，可使用上述脚本。

2026-10-09 环境复查：

- 已将用户安装的 Android SDK 和 Android Studio 路径记录到 Flutter 本机配置；这类机器路径不写入共享构建配置。
- Visual Studio Community 2026：Flutter 检查通过，C++ 桌面工作负载、MSVC、CMake 和 Windows SDK 均已识别。
- `flutter build windows --debug --no-pub`：通过，生成 `build/windows/x64/runner/Debug/dairy.exe`。此次验证了原生编译，尚未进行窗口交互或发行构建验收。
- Android SDK 已识别，Build-Tools 36.0.0 和 Platform-Tools 已安装；已有一个 Android 37 模拟器。首次复查仍缺少 Command-line Tools、项目使用的 Android 36 平台以及 NDK 28.2.13676358；之后用户已补齐这些组件，Android toolchain 与许可状态检查通过。
- Windows PowerShell 默认禁止脚本执行的问题通过新增 `.cmd` 命令入口处理；无需修改永久执行策略。
- 已在 `Restricted` 策略的 Windows PowerShell 中运行 `.\tool\flutter.cmd doctor`，入口验证通过。Android 调试构建首次尝试在 Gradle 下载阶段遇到 `Connection refused`；随后通过临时 Gradle 代理配置解决，见下方构建记录。网络下载问题与脚本执行策略错误不同。
- Flutter / Dart 未加入全局 PATH；继续使用项目脚本即可。代理检查的 NO_PROXY 提示不影响此次 Windows 构建。

Android 组件可在 Android Studio 的 `Tools > SDK Manager`（欢迎页为 `More Actions > SDK Manager`）安装：在 SDK Platforms 选择 API 36，在 SDK Tools 选择 Command-line Tools，并通过 Show Package Details 选择 NDK 28.2.13676358；CMake 也可按 Flutter 官方环境指南安装。组件位置应使用同一个 Android SDK 目录。许可检查使用 `.\tool\flutter.cmd doctor --android-licenses`，阅读并接受必要许可；之后可执行 `.\tool\flutter.cmd build apk --debug` 验证编译，再启动模拟器或连接真机验证运行。

数据库测试采用 Windows SQLite FFI，不代替 Android sqflite 驱动的真机测试。真实旧版本升级测试在引入 v2 迁移时增加。完整产品验收仍按 PRODUCT.md 的阶段推进。

2026-10-09 日记新建与自动保存验收：

- 格式化及 `flutter analyze --no-pub`：通过。
- `flutter test --no-pub`：30 项全部通过，包含新增的 8 项编辑状态测试和 5 项编辑页面测试。
- 自动保存的停顿／持续输入、写入中继续编辑、保存失败与同 UUID 重试、快速系统返回、后台提交、日期冲突不覆盖：通过自动化验证。
- 使用真实 SQLite 临时文件，经编辑状态保存后关闭并重新打开数据库，内容、UUID 和创建时间保留；再次修改不改变日记日期或创建时间；清空后记录仍存在：通过。
- `flutter build windows --debug --no-pub`：通过。真实窗口中文输入、进程关闭后重启等手动流程按上方步骤验收，本次未将 Widget／文件测试等同于实际窗口操作。
- `flutter build apk --debug --no-pub`：首次尝试在下载 Gradle 时遇到 `Connection refused`；随后在本次构建进程的 `GRADLE_OPTS` 中指定本机 HTTP／HTTPS 代理，Gradle 9.3.1 下载与 Android 调试构建均通过，生成 `build/app/outputs/flutter-apk/app-debug.apk`。
- 本次构建按依赖需要自动安装 Android SDK Platform 35 和 CMake 3.22.1，应用的 compileSdk 仍为 36。代理选项只在本次调用中设置并恢复，不将机器代理地址写入共享项目配置；Flutter 的 HTTP_PROXY／HTTPS_PROXY 不能替代 Gradle 的 JVM 代理配置。
- Android APK 编译已验证，模拟器／真机的中文输入、实际重启持久化等操作仍需单独验收。下载新构建依赖时仍需可用网络与相应代理配置。
