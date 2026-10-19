# 迭代记录

当前状态：v0.1 开发中，尚未发布完整版本。应用中的版本号仍为 `0.1.0+1`，下列开发阶段不代表已经发布了几个独立版本。

本文回答“什么时候改变了什么、为什么改、怎样验证”。最新项目概况和运行方法见 [README.md](README.md)，当前代码结构见 [ARCHITECTURE.md](docs/ARCHITECTURE.md)，目标产品行为见 [PRODUCT.md](docs/PRODUCT.md)，长期取舍见 [DECISIONS.md](docs/DECISIONS.md)。

## 记录约定

- 按开发／验收日期倒序维护，每次有意义的迭代记录目标、行为变化、涉及文件、数据流、存储与依赖影响、验证结果和剩余边界。
- 有对应 Git 提交时附上链接；开发日期和提交日期可能不同。同一个提交可能包含多个早期开发阶段，不为没有独立提交的阶段编造提交编号。
- 自动化测试、原生构建和用户手动验收分别记录。编译通过不能替代设备交互，数据库文件重新打开不能等同于实际应用进程重启。
- 历史结果只表示当次验证；不把本次文档整理写成重新执行了历史测试。没有记录的验证标为未验证或待验收。
- 需求和待办保持在 PRODUCT 中，当前结构保持在 ARCHITECTURE 中；本文件记录发生过的变化，不维护第二份完整需求或架构。
- 重大选择的理由引用 DECISIONS；这里解释本次具体改动，不复制整份长期决策。

## 2026-10-19：整理 GitHub 汇总提交

- 汇总自上次 GitHub 提交后的任务管理、日记显式改期、软删除和完整回收站，以及功能开发 skill、项目说明和详细迭代记录。
- 当前工作目录已不含 Git 元数据；从主仓库历史创建独立检出，保留主目录未提交的源码，再覆盖并逐项校验当前最新源码。缺少的 Android 工程和项目配置沿用主仓库现有文件，没有将目录缺失当作删除操作。
- 使用 `codex/v0.1-diary-tasks` 分支整理，供 GitHub Pull Request 查看。构建产物、SDK／依赖缓存和真实数据库不纳入提交，主目录工作内容不重置、不切换。
- 验证沿用 2026-10-17 的最终结果：84 项测试、静态分析、格式化及双平台 debug 构建通过；本次没有修改应用逻辑或重新执行构建，提交前检查源码快照一致性与 Git 差异空白。
- 完整设备操作和发行验收仍待完成，上传源码不代表已经发布正式 v0.1。

## 2026-10-17：日记软删除与回收站完整流程

### 用户确认与本次范围

用户确认前次日记改期验收无问题，并采用方案 2 实现软删除与回收站。复用既有 SQLite 字段、仓库和查询，接通编辑页删除、已删除详情、恢复、日期冲突、手动复制和打开现有日记。没有增加永久删除、批量恢复、自动合并、任务回收站或界面重设计。

### 操作前后变化

| 场景 | 修改前 | 修改后 |
| --- | --- | --- |
| 日记删除 | 只有仓库接口，无用户入口 | 已保存日记显示删除图标，确认后先保存最新内容再软删除 |
| 删除失败 | 无对应页面流程 | 保存失败不删除；删除失败保留已保存内容，可继续编辑或重试 |
| 保存与删除竞争 | 数据层拒绝复活，但缺少编辑协调 | 等待旧快照及最新输入后删除；删除期间冻结操作，成功后原会话终止写入 |
| 回收站列表 | 只能浏览摘要，记录不能打开 | 显示删除时间，可进入只读详情，返回后重新加载 |
| 已删除日记详情 | 没有独立页面 | 显示标题、原日期、删除时间及可选择的完整正文，无编辑输入框 |
| 恢复 | 只有数据层接口 | 成功返回并刷新回收站，回到主列表可见原记录 |
| 恢复冲突 | 数据层可拒绝，但无 UI | 提示保留双方，不自动改期／复制／覆盖，提供复制及打开现有日记 |
| 剪贴板 | 无按钮 | 用户主动复制后才写入，成功／失败均提示，可重试，不修改数据库 |

### 文件与职责

| 文件 | 本次变化 |
| --- | --- |
| [diary_editor_model.dart](lib/features/diary/diary_editor_model.dart) | 增加注入的删除回调、deleteEntry、删除与改期互斥、删除失败状态及终止写入标记；不管理弹窗或导航 |
| [diary_editor_page.dart](lib/features/diary/diary_editor_page.dart) | 删除按钮、确认、等待期间的输入／返回保护和重试入口；成功直接返回列表，不再触发已删除记录保存 |
| [diary_page.dart](lib/features/diary/diary_page.dart) | 回收站记录跳转、删除时间展示及详情返回后重读；普通日记展示保持 |
| [diary_trash_detail_page.dart](lib/features/diary/diary_trash_detail_page.dart) | 新增只读详情、恢复和冲突提示、用户主动复制、打开现有编辑页及导航保护 |
| [diary_trash_detail_model.dart](lib/features/diary/diary_trash_detail_model.dart) | 新增仓库恢复／查询调用、错误／冲突／忙碌和释放保护；不调用 Clipboard 或 Navigator |
| [diary_editor_model_test.dart](test/features/diary_editor_model_test.dart) | 新增 7 项删除协调测试 |
| [diary_trash_detail_model_test.dart](test/features/diary_trash_detail_model_test.dart) | 新增 5 项恢复／查找／故障／文件重开测试 |
| [diary_trash_widget_test.dart](test/features/diary_trash_widget_test.dart) | 新增 8 项删除、详情、恢复、冲突、剪贴板和操作保护测试 |
| PRODUCT／ARCHITECTURE／DECISIONS／README | 更新落地状态、真实调用链、ADR-010 实现补充、人工验收和验证结果 |

没有修改 DiaryRepository、DiaryQueries、模型、数据库 schema 或版本、任务模块、依赖与锁文件。现有未提交修改保留，没有提交或推送。

### 实际调用链

删除：`DiaryEditorPage._delete` 弹窗确认 → `DiaryEditorModel.deleteEntry` → `_flushContent` 等待并保存当前内容 → 注入的 `DiaryRepository.softDelete` → `DiaryQueries.setDeleted`／SQLite 事务 → 写入 deleted_at 和 updated_at → 编辑状态进入 deleted → Navigator 返回 → 日记列表重新读取。

恢复：回收站记录 → `DiaryPage._openDeleted` → `DiaryTrashDetailPage._restore` → `DiaryTrashDetailModel.restore` → `DiaryRepository.restore`／日期可用性检查／SQLite 唯一约束及事务 → 成功后返回回收站并重读；返回主列表时再次重读。

冲突整理：恢复失败 → 显示冲突并保留详情 → 用户点击复制，页面调用 `Clipboard.setData` → 用户点击打开现有日记 → `DiaryTrashDetailModel.findExisting`／`DiaryRepository.findByDate` → 既有 `DiaryEditorPage` → 用户自行粘贴编辑；不主动粘贴时不修改现有记录。

### 重要边界与理由

- 正文提交与软删除是有顺序的两次操作：保存失败不删除，删除失败时正文可能已经落库。删除标记和修改时间在同一事务内更新；不宣称正文提交与删除是跨步骤原子操作。
- 只取消计时器不足以阻止迟到快照；删除前先等待保存，成功后旧会话拒绝输入、改期、保存和再次删除。即使记录被恢复，旧编辑会话也不能覆盖它。
- 回收站状态对象集中处理异步结果，页面处理复制与导航，沿用现有 ChangeNotifier 和构造传参，未添加新框架或通用服务层。取舍补充见 ADR-010。
- 恢复失败只提示，不写用户剪贴板。测试使用模拟平台通道，既验证主动复制与失败重试，也避免改动用户真实剪贴板。

### 验证结果

| 检查 | 结果 |
| --- | --- |
| 格式化 | 37 个文件，8 个本次功能文件格式化；最终只读复查无变化 |
| 静态分析 | 通过：No issues found |
| 完整自动化测试 | 84 项通过；原 64 项加 20 项新增测试 |
| Windows debug 构建 | 通过，构建后更新 F:\project\dairy 的测试副本 |
| Android debug 构建 | Windows 结束后串行执行，通过 |
| 测试副本与 Git 忽略 | EXE、运行库和完整 data 共 13 个文件 SHA-256 一致，构建产物仍被 Git 忽略 |
| Git 差异空白检查 | 通过 |
| 实际设备／发行构建 | 本次未执行，按 README 人工验收 |

首次相关测试有一处对 tooltip 包装组件的查找类型错误，已改为定位实际 IconButton；静态分析的五处花括号提示也已修复。所有问题在交付前解决。数据库拒绝降级测试中的错误输出为预期保护行为，最终测试集通过。

新增覆盖包括：删除取消、删除前最后输入、慢保存与删除先后、重复操作／返回保护、正文失败阻止删除、删除失败重试、恢复后旧会话不能写入、删除及恢复后的文件重开、原 UUID／创建时间保留、冲突保留双方、查找不存在、恢复失败、主动复制／复制失败及无数据库副作用。

### 人工验收与交付边界

运行 `F:\project\dairy\dairy.exe`，按 README“手动验收日记软删除和回收站”检查取消与确认、最新内容、重启、恢复、日期冲突和手动整理；两个平台分别验证。此前改期验收反馈仅记为用户确认，不扩大为本次回收站已通过人工验收。v0.1 约定业务功能现已接通，完整设备验收及发行验证仍待完成。

## 2026-10-16：修正 Windows 测试副本的目标目录

- 用户明确“根目录”指 `F:\project\dairy`，此前放在 Codex 工作树目录属于理解错误。
- 已将最新日记改期版本的 EXE、DLL 和完整 data 资源复制到指定目录，13 个文件逐项 SHA-256 校验一致，入口为 `F:\project\dairy\dairy.exe`。
- 当前工作树和主目录的 AGENTS 均记录固定的测试副本位置；目标目录增加构建产物 Git 忽略规则，README 更新入口路径。
- 本次没有重新构建或修改应用代码；运行前确认目标程序未在运行，未覆盖用户数据库。

## 2026-10-16：已保存日记显式修改日期，成功后继续编辑

### 需求、方案与范围

用户确认方案 2：在已保存日记中提供明确的“修改日期”操作。用户补充要求改期成功后仍停留在编辑页，继续写作，最后由用户点击“保存并返回”结束编辑。沿用一天一篇、冲突不覆盖、UUID 和创建时间不变的规则；日记删除、回收站操作和界面美化不在本次范围。

### 操作前后变化

| 场景 | 修改前 | 修改后 |
| --- | --- | --- |
| 已保存日记日期 | 只展示，不能改期 | 点击“修改日期”，日历中“确认修改”后立即提交 |
| 改期前有待保存内容 | 无对应操作 | 等待旧快照和最新内容保存到原日期，再提交新日期 |
| 改期成功 | 无对应操作 | 页面显示已持久化的新日期，提示可继续编辑，不自动返回 |
| 改期后继续写 | 无对应操作 | 后续自动保存使用新日期；保存返回后列表按新日期排序 |
| 目标日期已有正常日记 | 数据层已能拒绝 | 弹窗提醒，原日期不变，两篇内容均保留，可重试或另选日期 |
| 日期写入失败 | 无对应操作 | 原日期保持，显示“重试修改日期”；正文已先保存到原日期 |
| 正文预提交失败 | 无对应操作 | 不尝试改期，保留输入，沿用“重试保存” |
| 改期正在提交 | 无对应操作 | 暂时阻止输入、重复改期和离页；后台 flush 等待同一操作 |
| 取消日历／选择原日期 | 草稿选择已支持 | 已保存记录同样不产生额外日期写入或修改时间变化 |
| 新建空白草稿选择日期 | 只改内存 | 保持；首次保存前不单独创建记录 |

### 文件与职责

| 文件 | 本次变化与职责 |
| --- | --- |
| [diary_editor_model.dart](lib/features/diary/diary_editor_model.dart) | 新增 changeDate、独占操作状态和失败目标；抽出已有内容提交逻辑为 _flushContent；协调串行保存，成功才更新日期；不负责导航和 SQL |
| [diary_editor_page.dart](lib/features/diary/diary_editor_page.dart) | 日期按钮、确认与反馈、输入／返回保护、区分正文和改期重试；成功只提示，不调用返回；不决定数据库规则 |
| [diary_editor_model_test.dart](test/features/diary_editor_model_test.dart) | 新增 7 项状态／数据测试，扩展既有文件重开测试覆盖显式改期；普通编辑保持日期的断言继续保留 |
| [diary_editor_widget_test.dart](test/features/diary_editor_widget_test.dart) | 新增 5 项页面测试，实际操作日历、失败触发器、数据库事务等待和返回 |
| [PRODUCT.md](docs/PRODUCT.md) | 明确确认后立即改期、成功留在编辑页、失败保留原日期 |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | 更新改期真实调用链与保存协调，去除过时实现边界 |
| [DECISIONS.md](docs/DECISIONS.md) | ADR-017 记录显式改期与先保存内容的理由；ADR-015 关联后续演进 |
| [README.md](README.md) | 更新当前功能、改期人工验收、检查结果和根目录测试副本来源 |

未修改 DiaryRepository、DiaryQueries、数据模型、SQLite schema、任务模块或导航结构；没有新增 package、表或迁移。现有未提交修改保持原样，本次没有提交或推送。

### 完整数据流和失败边界

日历确认 → `DiaryEditorPage._chooseDate / _changeDate` → `DiaryEditorModel.changeDate` → `_flushContent` 等待并提交原日期下的最新内容 → 既有 `DiaryRepository.save` → `DiaryQueries.updateContent`／SQLite 事务与唯一约束 → 返回 DiaryEntry → 更新 `_entry`、`_date` 并通知页面 → 继续编辑。

离页由用户另行触发：“保存并返回”或正常返回 → 既有 `flush` → 等待最新内容 → Navigator 返回 → 日记列表重读和排序。

正文预提交与日期修改是有顺序的两次操作，并非一个跨步骤事务；前者成功、后者失败时，最新正文安全保存在原日期。日期写入失败不伪装为成功；失败目标仅保存在内存供重试。旧快照完成后才写新日期，避免后续旧保存把日期改回去。

### 验证覆盖与结果

- 新增 7 项状态／数据测试：正文预提交与元数据保留、冲突保留双方、慢快照顺序和重复操作保护、正文失败阻止改期、日期失败重试同一 ID、同日期／草稿不写库、释放后不晚通知。
- 新增 5 项 Widget 测试：成功后留在编辑页及后续自动保存／列表排序；取消与同日期；冲突提示及再次选择；日期写入故障与重试；提交等待时阻止离页和重复操作。
- 相关日记测试 28 项通过；完整回归由原 52 项增加到 64 项，全部通过。数据库拒绝降级的错误输出为预期保护行为。
- 格式化、静态分析、Git 差异空白检查通过。Windows debug 构建通过，根目录 EXE、DLL 和 data 已同步，13 个文件 SHA-256 与构建目录逐项一致。
- Android 首次与其他验证并行运行时，在 compileFlutterBuildDebug 报 Java File.parent 空值；随后独立执行 Gradle assembleDebug 成功，正式 `flutter build apk --debug --no-pub` 再次运行也通过。没有修改业务代码、依赖或全局工具配置来规避该错误；首轮错误确切根因尚未确认。
- 使用已有工具链和临时 ASCII 路径，验证后移除映射，不修改永久 PATH 或 SDK 源码。实际设备上的输入、日历、返回、进程重启和发行构建仍待人工验收。

### 人工验收与剩余边界

按 README“手动验收日记改期”检查：打开已有日记 → 输入正文 → 修改到空日期 → 确认留在编辑页 → 继续写 → 保存返回 → 重启检查；再验证已有日期冲突和取消操作。日记删除、完整回收站及界面优化仍未在本次实现。

## 2026-10-16：增加项目根目录 Windows 测试副本

- 用户试用反馈：功能上未发现明显问题，界面美观度留待后续优化。本次反馈未明确平台与逐项步骤，不等同于双平台完整人工验收。
- 按要求，将 2026-10-14 已验证的 Windows debug 构建复制到当前项目根目录；本次没有重新构建，也没有修改应用业务代码。
- 根目录测试副本包含 `dairy.exe`、`flutter_windows.dll`、`dartjni.dll`、`sqlite3.dll` 和完整 `data/` 资源目录。DLL 与资源必须随 EXE 一起使用；没有复制调试符号 dairy.pdb。
- 对复制的 13 个文件逐个比较 SHA-256，均与原构建一致；Git 忽略检查和差异空白检查通过。未重新运行应用或自动化测试。
- `.gitignore` 排除根目录 EXE、DLL 与资源；AGENTS 记录以后 Windows 构建成功后同步更新此副本；README 说明启动方法和更新前关闭应用。
- 该副本只用于本机测试，不提交至 Git。`data/` 为 Flutter 资源，用户数据库仍在原应用数据目录。

## 2026-10-14：在新工作区重新完成任务功能验证

### 本次范围

按项目所有者要求，重新运行此前受环境阻塞的格式化、静态分析、测试和双平台调试构建。工作区为 `C:/Users/葵/.codex/worktrees/b825/dairy`，沿用已确认的任务方案 2 和之前的 Hero 标识修复。没有新增功能、依赖、数据库字段或迁移。

### 环境恢复与排查

- 默认 PowerShell 已能正常执行命令，不再出现此前的启动路径解析失败。
- 新工作区没有携带被 Git 忽略的 `.tools/flutter`、包缓存与 `.dart_tool`。验证进程复用 `F:/project/dairy/.tools/flutter` 和现有 pub-cache；`pub get --offline` 成功，未升级锁定依赖。
- Git 提示工作区属于 Administrators；通过单次命令／进程的 safe.directory 配置处理，没有写入全局 Git 配置。
- 普通沙箱下 Dart 格式化仍在 `_Platform.resolvedExecutable` 失败；获准使用提升权限入口后，格式化与测试可运行。此前所有失败不能统一归因于缺少已安装的工具。
- 静态分析在原中文路径启动后，分析服务报 JSON `Unexpected end of input`。本机 Flutter 工具的 `analysis.dart` 使用 `message.length` 写入 Content-Length；中文字符的字符数与 UTF-8 字节数不同。为同一项目建立临时 ASCII 盘符路径后，未修改 SDK 源码，分析通过。
- 初次 Windows 构建使用盘符根目录 `Z:/`，CMake 将目录末尾反斜线与下一项环境变量拼接，后端错误尝试进入 `Z:;FLUTTER_TARGET=lib/main.dart`。改用 `Y:/dairy` 并清理本工作区生成的 Windows 构建缓存后，构建通过。
- Android 构建使用现有 SDK、JDK 和 Gradle 缓存，通过。日志出现 Java 原生访问与 SDK XML 版本提示，没有阻止本次构建；未调整工具版本或共享代理配置。
- 以上环境变量只作用于本次进程；验证结束移除临时盘符映射，不移动源码、不改变永久 PATH 或系统执行策略。

### 实际验证结果

| 检查 | 本次结果 |
| --- | --- |
| 离线依赖解析 | 通过：Got dependencies，锁定依赖不变 |
| Dart 格式化 | 检查 lib 与 test 共 33 个文件，7 个文件格式化；后续只读检查无变化 |
| Flutter 静态分析 | 通过：No issues found，临时 ASCII 路径下运行 |
| 完整自动化测试 | 52 项全部通过，包含 19 项任务测试及已有日记／数据库／导航回归 |
| Windows 调试构建 | 通过：`build/windows/x64/runner/Debug/dairy.exe` |
| Android 调试构建 | 通过：`build/app/outputs/flutter-apk/app-debug.apk` |
| Git 差异空白检查 | 通过：git diff --check |
| 双平台人工交互与实际进程重启 | 未执行，仍按 README 清单验收 |
| 发行构建 | 未执行，本次只验证 debug |

数据库拒绝降级测试输出 `Database downgrade is not supported: 2 → 1` 是预期保护行为，完整测试最终以 `All tests passed!` 结束。

### 文件变化与交接

- 格式化 `task_editor_model.dart`、`task_editor_page.dart`、`task_list_model.dart`、`task_period_controls.dart`、`tasks_page.dart` 和两个任务测试文件，未改变业务行为。
- README 更新最新验证摘要；ARCHITECTURE 仅去除过时的“格式化待完成”说明；本记录保留初次失败、原因、处理方式与最终结果。
- 原有未提交的功能、文档和 skill 修改保留，本次没有提交或推送。产品需求、数据库结构和长期架构决策不变。

## 2026-10-12：重启后复查命令执行环境

- 用户反馈：重启电脑后自己的终端能运行 Flutter 命令。后续提供输出确认：修复前静态分析通过（No issues found!），测试 35 项通过、17 项失败。修复后的结果待重新运行。
- 默认命令工具：`Get-Location` 仍在启动前报 `Failed to resolve full path of the current executable`，指向 Codex 自带 PowerShell。
- CMD 备用入口：Dart 只读格式检查仍在 `_Platform.resolvedExecutable` 抛出异常；Flutter `analyze --no-pub` 与 `test --no-pub` 均在启动阶段报 `Unable to find git in your PATH`，没有运行到分析或测试。
- 文件检查：`F:/git/Git/cmd/git.exe` 与项目本地 Dart 可执行文件存在，可读取文件元信息；这不等同于原生进程可以正常运行。
- 提升权限复查：Git 直接调用仍受访问限制，Dart 格式检查仍失败。没有据此修改永久 PATH、系统权限、工具安装或执行策略。
- 结论：代理执行环境仍受阻；用户本机能启动命令，使问题范围更集中于 Codex 的执行环境，但确切根因尚未确认。
- 初次复查只更新验证记录；收到真实测试失败后进行了下面的导航修复。当前任务代码仍需修复后的格式化、分析、测试及平台验收，不沿用历史通过结果。

### 根据用户测试输出修复导航冲突

- 问题：AppShell 用 IndexedStack 保留日记和任务页面，两个 FloatingActionButton 原来都使用默认 heroTag。打开编辑页触发 Hero 搜索时，同一主页面路由内出现重复标识，Flutter 报 multiple heroes that share the same tag。
- 根因属于本次任务按钮加入后的代码问题，与 Codex 命令环境受阻是两件事。多项页面测试可能受同一异常影响，不能仅凭这一段日志断言全部 17 项失败都已解决。
- [diary_page.dart](lib/features/diary/diary_page.dart)：给“写今天”按钮指定 diary-write-today。
- [tasks_page.dart](lib/features/tasks/tasks_page.dart)：给“新建任务”按钮指定 task-create。
- [widget_test.dart](test/widget_test.dart)：扩展既有窄屏导航测试，实际进入日记／任务编辑页并返回，检查无异常且空白打开不创建数据。没有增加测试数量，仍为原 33 项加新 19 项。
- 调用链仍为按钮 → 页面既有导航方法 → Navigator.push → 对应编辑页；只修正路由内动画标识，不修改保存状态、Repository、SQL、schema、主导航结构或依赖。
- 用户日志中“Database downgrade is not supported: 2 → 1”来自既有数据库拒绝降级测试的预期异常；其后计数仍继续推进，不能仅凭该打印认定失败。
- 修复后代理侧实际尝试分析及导航／任务／日记 Widget 测试，仍在 Flutter 启动阶段报找不到 Git，没有取得代码验证结果。已请用户本机重跑完整分析和测试，取得成功结果前不标记验收完成。

### 修复后本机验证结果

- 来源：项目所有者提供 2026-10-12 本机 PowerShell 输出，Flutter 3.47.6／Dart 3.13.5。
- 静态分析：No issues found!，1.5 秒；测试：52 项全部通过，约 5 秒。Hero 标识修复后的导航回归及任务测试包含在此次完整测试中。
- 拒绝数据库 2 → 1 降级的打印是预期异常路径，最终测试通过。
- 验证归属：上述结果来自用户本机，Codex 代理侧仍受工具启动错误影响，没有把用户结果描述为代理自行执行。
- 剩余：未取得本次 Dart 格式化、Windows／Android 构建、双平台交互或发行验证结果。没有新增依赖、改变 schema 或提交／推送代码。

## 2026-10-11：任务基本功能采用独立编辑页与轻量状态

状态：方案 2 已由项目所有者确认；代码与测试已加入，自动化检查和双平台验收待完成。本条尚无对应 Git 提交，不代表已发布或已推送。

### 目标与范围

将只读任务列表变为可操作的任务管理入口：新建、编辑标题和备注、设置四种时间范围、手动保存、标记完成、撤销完成和软删除。保留总体方案 A，既有仓库和 SQLite schema v1 继续使用。任务汇总、重复规则、任务回收站和云同步不在本次范围。

### 操作前后变化

| 场景 | 修改前 | 本次代码行为（待运行验收） |
| --- | --- | --- |
| 新建／编辑任务 | 只有列表读取入口 | 独立表单页，标题必填、备注可选，点击“保存”才提交 |
| 输入或空白打开 | 没有表单 | 输入只改变内存；空白打开和返回不创建记录 |
| 日／月／年任务 | 当前自然周期只读 | 编辑和列表都可以选择日期、年月或年份 |
| 自定义任务 | 只读该类型记录 | 选择开始日期、输入正整数天数；提供 5／10／30 天快捷按钮，首日计入 |
| 保存未来任务／修改类型 | 没有编辑入口 | 保存成功后列表切换到该类型和周期，完成筛选回到“全部” |
| 有未保存修改时返回 | 没有此场景 | 提供继续编辑、放弃修改、保存并返回；写入失败仍保留表单 |
| 完成／撤销 | 只有仓库接口 | 列表复选框立即提交；完成写入时间，撤销清空完成时间 |
| 完成筛选 | 没有 UI | 全部／未完成／已完成，提交成功后重新查询 |
| 删除任务 | 只有仓库接口 | 列表菜单和编辑页提供确认；成功写入 deleted_at 后离页／刷新 |
| 删除时有未保存内容 | 没有此场景 | 明确提示放弃尚未保存修改；不替用户偷偷保存这些内容 |
| 操作失败 | 列表只处理读取失败 | 表单保留输入，列表保留原状态并提示，允许重试 |

### 文件和职责

| 文件 | 新增／修改与职责 |
| --- | --- |
| [task_editor_page.dart](lib/features/tasks/task_editor_page.dart) | 新增：表单、控制器、导航、未保存返回和删除确认；不执行 SQL |
| [task_editor_model.dart](lib/features/tasks/task_editor_model.dart) | 新增：内存表单、初始快照、范围校验、忙碌状态、固定 ID 与保存／删除错误；不管理 Navigator |
| [task_period_controls.dart](lib/features/tasks/task_period_controls.dart) | 新增：范围标签、日历、年月／年份弹窗；不负责持久化 |
| [task_list_model.dart](lib/features/tasks/task_list_model.dart) | 修改：类型／周期／完成筛选、写入后刷新、保存后定位、过期请求保护 |
| [tasks_page.dart](lib/features/tasks/tasks_page.dart) | 修改：编辑入口、筛选 UI、完成复选框、删除菜单及操作反馈 |
| [task_models_test.dart](test/features/task_models_test.dart) | 新增 8 项状态和数据测试，包括文件数据库重新打开 |
| [task_widget_test.dart](test/features/task_widget_test.dart) | 新增 11 项页面测试，包括表单、返回、筛选、故障重试与窄宽屏 |
| [PRODUCT.md](docs/PRODUCT.md) | 明确保存后列表定位、状态入口、未保存返回与删除提示 |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | 更新任务实际组成、调用链和待验证边界 |
| [DECISIONS.md](docs/DECISIONS.md) | 追加 ADR-016，记录方案 2 的选择与代价 |
| [README.md](README.md) | 更新任务入口、职责、人工验收、检查命令和验证限制 |

本次没有修改 Task、TaskPeriod、TaskRepository、TaskQueries、schema、应用初始化或日记页面。沿用其既有规则；未新增 package、数据库字段或迁移，不改变现有日记保存流程。另有前次文档整理和 skill 文件尚未提交，不能混称为本次任务源代码变更。

### 主要调用链与保存规则

输入：`TaskEditorPage` 输入框 → `TaskEditorModel.setTitle / setNotes / setType / setDate / setDays` → 内存表单与校验预览 → 状态通知页面；此时不写 SQLite。

保存：`TaskEditorPage._save` → `TaskEditorModel.saveTask` → `TaskRepository.save` → 事务内 `TaskQueries` 写入 SQLite → 返回已持久化 Task → `Navigator.pop` → `TasksPage._openTask` → `TaskListModel.focusTask / load` → 仓库重新查询 → UI 更新。

完成：列表复选框 → `TaskListModel.setCompleted` → `TaskRepository.setCompleted` → SQLite 同时更新 is_completed、completed_at、updated_at → 列表重新查询。撤销同一路径，完成时间设为 NULL。

删除：确认弹窗 → 编辑状态或列表状态 → `TaskRepository.softDelete` → SQLite 写入 deleted_at 和 updated_at → 成功后离页／刷新。UUID、创建时间、已保存内容和完成信息保留，正常查询排除该记录。

保存期间阻止重复提交和继续修改快照；失败保留当前输入并复用 UUID 重试。内容编辑保留创建时间和完成状态。自定义持续天数在日期运算前检查上限，避免极大数值产生无效范围。没有采用乐观更新或回滚框架，理由见 ADR-016。

### 测试覆盖与实际验证结果

新增 19 项测试代码，**尚未执行通过**：

- 8 项状态／数据测试：输入不写库、标题和天数校验、四类范围及跨年边界、固定 ID 重试、重复保存保护、异步完成后的释放保护、删除失败、周期与完成筛选、文件重开后的内容／状态／删除标记保留。
- 11 项 Widget 测试：空白表单、手动保存、编辑保留身份和完成信息、完成与撤销筛选、返回三选项、自定义快捷天数与无效输入、未来月／年任务、类型变更后的可见性、删除确认、写入失败重试、状态操作失败保留原值、窄宽窗口布局。

| 检查 | 本次实际结果 |
| --- | --- |
| Dart 格式化 | 未完成；CLI 启动后在 `_Platform.resolvedExecutable` 出现 `type 'Null' is not a subtype of type 'String'` |
| Flutter 静态分析 | 未完成；当前命令执行环境无法正常启动工具 |
| 新增测试与完整测试集 | 未完成；实际调用任务测试入口在启动阶段报 `Unable to find git in your PATH`，未执行到测试 |
| Android／Windows 调试构建 | 未执行，本次代码不能沿用上次构建通过结论 |
| 真机／桌面交互与进程重启 | 待项目所有者按 README 验收 |
| 文件引用及相对导入检查 | 使用文件工具检查；不能替代 Dart 分析、编译或测试 |

当前代理运行环境中，Git 的当前目录读取以及部分原生工具路径解析受限。Dart 能输出版本号，但格式化无法启动；尝试普通与提升权限命令均未解除问题。没有调整系统 PATH、永久执行策略或共享代理配置。此现象不能证明用户本机缺少 Git、Flutter 或原生工具链。

### 验收与剩余边界

按 README“手动验收任务功能”逐项验证新建、保存、重新启动、编辑、完成、撤销、四种范围、离页提示和删除，Windows 与 Android 分别验收。先补跑格式化、静态分析与测试，修复本次代码暴露的问题后，再记录构建与人工结果。

- 当前没有任务恢复入口，软删除信息只留在数据库；没有强制退出后的任务草稿恢复。
- completed_at 仅代表当前完成状态，不保存多次完成／撤销的历史。
- 自定义范围是一条任务，不自动拆成每天实例；过期任务不顺延，类型之间不汇总。
- 回收站操作和已保存日记显式改期仍待后续阶段，本次没有宣称完整 v0.1 已完成。

## 2026-10-10：明确结束写作操作，简化日记列表

关联代码提交：[4dfb4db — 日记操作与列表显示调整](https://github.com/suncloudrain/dairy/commit/4dfb4db)，提交日期为 2026-10-10。代码已推送至 `main`。

### 本次目标和反馈来源

用户试用后反馈：编辑页只有返回键，缺少明确的结束写作操作；无标题日记在列表中出现两个相同日期；右下角新增按钮的文字可以省略。用户确认先处理这三项，标题与正文的有框输入样式留待后续优化。

### 操作前后变化

| 操作／场景 | 修改前 | 修改后 |
| --- | --- | --- |
| 写完后离开编辑页 | 通过左上角或系统返回结束编辑 | 增加右上角“保存并返回”，返回键仍可使用 |
| 点击“保存并返回” | 没有此入口 | 立即提交并等待最新输入；成功才返回列表 |
| 保存中结束编辑 | 既有返回路径等待保存 | 新按钮复用同一路径；等待期间冻结输入并防止重复离页 |
| 保存失败 | 既有错误提示、输入保留与重试 | 新按钮同样留在编辑页并保留输入，不把失败当成功 |
| 打开编辑页但未输入 | 不创建数据库记录 | 点击新按钮也不创建空记录 |
| 有标题的列表项 | 标题、日期、正文摘要 | 保持这一显示方式 |
| 无标题的列表项 | 日期代替标题，摘要区域又显示一次日期 | 日期仅显示一次，下方展示正文摘要 |
| 正文为空或只有空白 | 摘要没有有效正文 | 显示“暂无正文”，提示文字不写入数据库 |
| 右下角“写今天” | 铅笔图标加文字 | 只显示铅笔，保留“写今天”提示与无障碍名称；动作不变 |

### 文件和职责

| 文件 | 本次职责／变化 |
| --- | --- |
| [diary_editor_page.dart](lib/features/diary/diary_editor_page.dart) | AppBar 增加 TextButton，调用既有 `_leave`；保存按钮与返回键共用离页保护 |
| [diary_page.dart](lib/features/diary/diary_page.dart) | 使用普通图标 FloatingActionButton；按是否有标题生成列表展示文字和摘要 |
| [diary_editor_widget_test.dart](test/features/diary_editor_widget_test.dart) | 调整入口查找方式，新增三项页面测试，已有写入失败测试改为验证新按钮 |
| [PRODUCT.md](docs/PRODUCT.md) | 明确保存并返回、无标题显示和图标入口的产品行为 |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | 记录按钮复用既有提交路径、展示逻辑属于页面层 |
| [DECISIONS.md](docs/DECISIONS.md) | 在 ADR-009 中解释自动保存与明确结束操作可以同时存在 |
| [README.md](README.md) | 更新当前功能概况、运行后的手动验收步骤 |

### 数据流与兼容性

点击“保存并返回” → 编辑页 `_leave / _prepareToLeave` 冻结输入 → `DiaryEditorModel.flush` 等待最新输入提交 → `DiaryRepository.save` 在事务中写入 SQLite → 成功后 `Navigator.pop` → 列表重新查询。

若已有自动保存正在执行，`flush` 共用其等待结果，保存状态继续按编辑版本处理后续最新输入。按钮不建立另一套保存逻辑，错误路径保留当前输入。

本次没有新增包、修改 schema、执行数据库迁移或改变 UUID 规则；SQLite 仍为 v1。日期替代标题和“暂无正文”都是页面展示，真实标题、正文不因此被改写。普通编辑仍保留创建时间和日记日期。

### 当次自动化与构建结果

| 检查 | 结果／覆盖 |
| --- | --- |
| Dart 格式化 | 通过，格式化涉及的页面与测试 |
| `flutter analyze --no-pub` | 通过，无静态分析问题 |
| `git diff --check` | 通过 |
| `flutter test --no-pub` | 33 项通过：4 项日期／范围、10 项数据层、8 项编辑状态、8 项编辑页面、3 项应用导航 |
| `flutter build windows --debug --no-pub` | 通过，生成 `build/windows/x64/runner/Debug/dairy.exe` |
| `flutter build apk --debug --no-pub` | 通过，生成 `build/app/outputs/flutter-apk/app-debug.apk`；仅本次进程设置 Gradle 代理 |

三项新增页面测试分别验证：

1. 未输入就点击“保存并返回”能返回列表，不创建记录；铅笔入口仅有图标并保留提示。
2. 输入后不等待自动保存计时器，点击按钮仍写入最新内容；再次编辑复用同一 UUID，并保留创建时间和日记日期。
3. 有标题、无标题及空正文的列表展示正确，日期不重复，展示替代文字不改写存储。

已有写入失败测试验证新按钮在失败时留页、保留正文，处理失败后可重试保存并返回。慢写入期间继续输入、串行保存和最新版本判断由已有编辑状态测试覆盖。

### 手动验收与剩余边界

- 代码交付后，用户在本次会话反馈“我验收了一下，基本没问题”。记录为用户试用反馈；没有提供平台及逐项结果，不据此声明双平台完整验收已通过。
- 本次自动化验证未包含实际 Android 真机／模拟器交互及发行构建。实际进程重启、中文输入法和平台交互仍按 README 的手动步骤验证。
- 标题／正文边框没有改动。已保存日记的显式日期修改、回收站操作及任务编辑尚未实现。
- 日记检索和任务汇总属于已讨论的未来方向，不计入本次实现或 v0.1 交付。

### 后续文档整理

根据用户反馈，详细迭代与验证历史从 README 移至本文件；README 保留当前概况和最新验证摘要；ARCHITECTURE 的当前状态按层次和实现边界组织。本次整理只改文档，不改变上述代码、测试数量或验收结果。

## 2026-10-09：打通日记新建、编辑和轻量自动保存

关联基线提交：[64d59f0 — 首次项目基线](https://github.com/suncloudrain/dairy/commit/64d59f0)，提交日期为 2026-10-09。该提交同时包含 10 月 8 日的基础工程与本阶段内容；这两个阶段没有各自独立的 Git 提交。

### 本次目标

用户选用日记方案 2，在已建立的方案 A 架构上实现：可以创建日记、写入 SQLite、重新打开后读取、编辑保留创建时间与日记日期，以及自动保存。选择轻量自动保存，暂不增加独立持久化草稿；取舍见 [ADR-015](docs/DECISIONS.md#adr-015日记使用轻量自动保存暂不增加持久化草稿)。

### 行为和保存规则

- 从日记列表进入今天的记录：已有则继续编辑，没有则打开内存草稿；仅打开不写入数据库。
- 右上角“新建日记”可选择日期补写；遇到已占用日期，提示打开已有记录，不覆盖。新草稿首次保存前可以调整日期，已保存日记暂时固定日期。
- 输入标题或正文后，停顿约 800 毫秒保存；持续输入约 5 秒提交，避免一直输入时永远不保存。
- 同一编辑会话固定 UUID；重试和后续修改使用原记录，不重复创建。
- 同一会话保存串行执行，保存过程中继续编辑时，后续提交最新快照；旧快照写入成功不能把尚未保存的新内容标为“已保存”。
- 显示空白待输入、未保存、保存中、已保存和失败状态；失败保留输入并提供“重试保存”。
- 正常返回等待最新内容写入；进入后台或收到可取消退出请求时尽力提交。
- 已保存记录的创建时间和日记日期保持不变；清空标题、正文后仍保留该记录，不自动删除。

### 文件、数据流与存储影响

| 文件 | 职责 |
| --- | --- |
| [diary_editor_page.dart](lib/features/diary/diary_editor_page.dart) | 文本输入、日期展示、保存反馈、PopScope 返回保护与生命周期观察 |
| [diary_editor_model.dart](lib/features/diary/diary_editor_model.dart) | ChangeNotifier 编辑状态、计时器、内存版本、串行快照提交和错误保留 |
| [diary_page.dart](lib/features/diary/diary_page.dart) | 从列表进入编辑器，查找今天已有日记，处理新建日期冲突，离页后刷新 |
| [diary_repository.dart](lib/data/repositories/diary_repository.dart) | 复用既有保存入口，事务、业务校验与时间赋值 |
| [diary_editor_model_test.dart](test/features/diary_editor_model_test.dart) | 新增 8 项编辑状态测试，控制计时、慢写入、失败和文件重开 |
| [diary_editor_widget_test.dart](test/features/diary_editor_widget_test.dart) | 新增 5 项编辑页面测试，覆盖入口、自动保存、系统返回、后台、冲突与失败 |

数据流：输入框 `onChanged` → 编辑状态记录最新内容与版本 → 定时器／返回触发 `flush` → 仓库事务保存 → 返回已持久化对象 → 编辑状态判断是否仍有更新 → 页面更新反馈。

直接写入已有日记表，schema 仍为 v1；没有添加新依赖、草稿表、历史表或云同步服务。内存版本只协调自动保存，不能当作未来跨设备同步版本。

### 当次验证

- 格式化和 `flutter analyze --no-pub` 通过。
- `flutter test --no-pub`：30 项通过，在原 17 项基础上增加 8 项编辑状态及 5 项编辑页面测试。
- 验证停顿保存、持续输入周期保存、串行保存与最新快照、同 UUID 重试、冲突不覆盖、快速系统返回和后台提交。
- 真实 SQLite 临时文件写入后关闭、重新打开数据库，内容、UUID 和创建时间保留；再次编辑保留日期与创建时间；清空后记录仍存在。
- Windows 和 Android 调试构建均通过；设备交互及发行构建没有因此自动完成验收。

### 本阶段边界

未保存草稿仅在内存，强制结束／断电可能丢失最后输入；日期冲突时也没有独立持久化草稿。编辑器中的普通修改不调整日记日期；显式日期修改仍待实现。

回收站、任务仍只有列表及已验证的数据层入口，没有完整可操作的编辑／删除／恢复界面。

## 2026-10-09：补齐平台环境，解决命令入口与 Android 下载问题

关联基线提交：[64d59f0](https://github.com/suncloudrain/dairy/commit/64d59f0)。工具链安装与 Flutter 本机配置是开发环境变化，不作为共享项目源码或数据库迁移提交。

### 问题与处理

| 问题 | 处理 | 影响范围 |
| --- | --- | --- |
| Android SDK 组件最初不齐 | 用户补齐 Command-line Tools、Android 36 平台、NDK 28.2.13676358 等组件并接受必要许可；配置 Flutter 使用已安装的 SDK／Android Studio | 本机开发环境 |
| Visual Studio C++ 工具链最初缺失 | 补齐桌面 C++ 工作负载，确认 MSVC、CMake 和 Windows SDK 被 Flutter 识别 | Windows 原生编译环境 |
| PowerShell 禁止直接运行 `flutter.ps1` | 增加 [tool/flutter.cmd](tool/flutter.cmd)，用子进程 RemoteSigned 策略执行 helper 并返回原退出码 | 不改变用户／系统永久执行策略 |
| Gradle 下载时报 `Connection refused` | 在当次进程的 `GRADLE_OPTS` 中指定可用 HTTP／HTTPS 代理，构建完成后恢复 | 不把机器代理地址写入共享配置 |

[tool/flutter.ps1](tool/flutter.ps1) 优先使用项目本地 Flutter SDK，管理本次进程的包缓存、Git 本地 SDK 信任与 HTTP／HTTPS 代理环境。Flutter 的 HTTP_PROXY／HTTPS_PROXY 不能替代 Gradle 的 JVM 代理设置。

### 当次确认结果

- Visual Studio Community 2026 被识别，C++、MSVC、CMake、Windows SDK 检查通过。
- Android toolchain 与许可状态检查通过；当时有 Android 37 模拟器，存在模拟器不代表已经运行应用验收。
- 在默认限制脚本执行的 Windows PowerShell 中，通过 `flutter.cmd doctor` 验证命令入口。
- Windows 调试构建通过；Gradle 下载问题解决后，Android 调试构建也通过。
- 构建按依赖需要自动安装 Android SDK Platform 35 和 CMake 3.22.1，项目 compileSdk 仍为 36。
- Flutter／Dart 没有加入全局 PATH，继续使用项目 helper 即可。SDK 与缓存仍被 Git 忽略，不随仓库分发。

## 2026-10-08：建立方案 A 的工程骨架与本地数据层

关联基线提交：[64d59f0](https://github.com/suncloudrain/dairy/commit/64d59f0)，到 2026-10-09 才首次提交。以下是基础工程阶段的结果，不代表当时已完成日记编辑。

### 本次目标与已交付内容

- 采用 Flutter 自带 Material、ChangeNotifier、Navigator 和构造函数注入，建立 Android／Windows 平台工程。
- 应用初始化打开数据库并组装仓库；失败显示重试，不通过删库解决错误。
- 窄屏底部导航、宽屏侧边导航，日记／回收站／四类任务只读列表和基本跳转。
- 建立独立日历日期模型与 DAY／MONTH／YEAR／CUSTOM 范围规则；自定义范围计入首日，内部统一不含结束边界。
- SQLite schema v1 包含日记、任务两张表，UUID、UTC 时间与软删除标记；有效日记日期唯一，任务完成状态与完成时间保持一致。
- 仓库提供保存、查询、软删除、日记恢复、任务完成与撤销等入口。实际内容未变化时不更新时间，保存不能复活软删除记录。
- 保留数据库升级入口；没有历史版本可迁移，未知升／降级明确失败，不删除用户数据。
- iOS 只保留数据库驱动兼容分支，没有生成或验证平台工程；云同步不属于本阶段。

### 关键文件和数据流

| 文件／目录 | 职责 |
| --- | --- |
| [app_dependencies.dart](lib/app/app_dependencies.dart) | 选择平台驱动、获取应用数据目录、打开 SQLite、创建仓库 |
| [dairy_app.dart](lib/app/dairy_app.dart) 与 [app_shell.dart](lib/app/app_shell.dart) | 启动反馈、中文本地化和响应式主导航 |
| [models/](lib/models/) | 不可变对象、日历日期与任务范围 |
| [schema.dart](lib/data/database/schema.dart) 与 [app_database.dart](lib/data/database/app_database.dart) | 表与约束、索引、连接和版本管理 |
| [data/repositories/](lib/data/repositories/) | 业务校验、事务入口、UUID 和时间规则 |
| [diary_queries.dart](lib/data/database/diary_queries.dart) 与 [task_queries.dart](lib/data/database/task_queries.dart) | 参数化 SQL、行映射与查询 |
| [test/](test/) | 日期、仓库、持久化、导航和初始化失败测试 |

启动：`main → DairyApp → AppDependencies.initialize → AppDatabase.open → 两个仓库 → AppShell`。

读取：`页面 → ListModel → Repository → Queries → SQLite → 数据对象 → 页面状态通知 UI`。页面不执行 SQL，仓库不访问 Widget。

### 当次验证与限制

- Dart 格式化、`flutter analyze --no-pub` 通过。
- `flutter test --no-pub`：17 项通过（4 项日期／范围、10 项数据层、3 项应用导航）。
- 日期测试覆盖非法日期、闰年、跨年、自定义天数、自然周期与范围对齐。
- 数据层验证同 UUID 重试、清空不删、日期冲突、软删除过滤、恢复冲突、并发日期唯一、任务状态／时间规则和约束保护。
- 真实 SQLite 文件重新打开保留内容与 UUID；拒绝较新 schema 降级且旧数据保留。测试日志中的预期降级错误不是测试失败。
- 当时缺 Android SDK 和 Visual Studio C++ 工具链，尚未完成 Android／Windows 原生构建和设备运行验证。后续补装与构建结果单列在上面的环境迭代中。
- v1 没有真实旧版迁移样本；未来引入 v2 时需要补迁移及旧数据测试。

## 后续每次迭代的填写格式

1. 日期、主题、关联提交或“尚未提交”，以及是否发布。
2. 目标与用户反馈：解决哪一个具体问题。
3. 行为变化：原来怎样、现在怎样，哪些规则继续生效。
4. 涉及文件和职责、主要数据流；数据库、迁移与依赖是否变化。
5. 实际执行的检查、通过数量、平台构建结果；手动验收单独列出。
6. 已知边界、未完成内容和后续事项；涉及长期取舍时链接对应 ADR。
