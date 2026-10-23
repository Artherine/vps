# 工作区布局（`C:\Artherine\DSH\Temp`）

> **接手会话前先读 [`HANDOFF.md`](HANDOFF.md)** —— 给下一个上下文的交接文档（含上一班的翻车清单与磁盘索引）。

多会话共用。总规则：**生成物放工作区，不进 Mnemon 档案层**（见 MEMORY.md 工作约定 ⑤）。

| 位置 | 用途 | 可否删 |
| --- | --- | --- |
| `dnd\` | 用户的 D&D 素材：规则书 PDF / CHM、官方人物卡模板（可填 PDF）、Excel 计算表、角色卡生成工具 V2 | ❌ 用户的，别动 |
| `roscoe-halfside\` | 罗斯科·半边人物卡项目：底稿三份＋立绘＋提示词＋两张交付 PDF＋流水线脚本＋`README.md` | ❌ 项目 |
| `tools\` | 长期脚本 | ❌ 工具 |
| `scratch\` | 临时物：抓下来的图、一次性 OCR 脚本与输出、拉回来的外部 README | ✅ 随时可清 |
| `archive\` | 过时但可能仍有用：旧插件脚本、`pnpm-lock` 备份 | ⚠️ 归档，别删 |

## 操作记录

### 2026-10-16：dsh-mnemon 0.5.17 → 0.5.29（desktop profile）

- 命令：`dsh plugin --profile desktop add dsh-mnemon@0.5.29`。profile 在工作区外，沙箱会拒绝 `package.json.lock`，须按原命令重试并申请 `danger-full-access`。
- 本机 profile 的直接依赖只有 Starter 一个，组件随 Starter 锁定，**不必逐个 add**；升级后 `dsh-mnemon` 0.5.29、`-source-memory-spaces` 0.5.19、`-provider-openviking` 0.5.8、`-provider-hindsight` 0.5.6 到位，其余 14 个组件按发布说明保持不变。宿主锚 0.1.7-rc.2，落在 0.5.29 的 peer 范围 `^0.1.7-rc.2 || ^0.2.0-rc.1` 内。
- 升级前备份 `.dsh\profiles\desktop`（排除 node_modules）＋ `.mnemon`，写到 `%USERPROFILE%\.dsh-backups\<时间戳>\`。用户确认插件状态正常并把 `.mnemon` 同步到 git 后，该备份连同 `Temp\scratch\` 内容一并删除——**本机现在没有本地回滚点**，需要回滚请走 git 历史。
- 遗留清理：根目录 `debug.log`（`dsh plugin` 的 crashpad 报错残留）与一个 robocopy 失败留下的空备份目录已删。`archive\profile-backup-20260928-110301\` 是同类操作的旧备份，保留。
- 下次升级的检查点：重启 DSH 后在**记忆系统 → 状态 → 检查版本**核对版本与两个记忆空间是否都激活可召回（检查版本／更新按钮自 0.5.22 起提供，0.5.17 上还没有）。

目录约定照旧（`dnd\` 用户素材、`roscoe-halfside\` 项目、`tools\` 长期脚本、`scratch\` 可清、`archive\` 归档）。打招呼：这条记录是 2026-10-16 那次升级会话留的——**scratch 是给你用的，用完记得清；要动 dnd 或 roscoe 请先问用户**。

## `tools\` 里有什么

| 脚本 | 用途 |
| --- | --- |
| `mnem-cipher.ps1` | 用户画像密文的编解码器（规格见档案《mnem-cipher 规格 v2》） |
| `httpsget.mjs` | 沙箱内 HTTPS 抓取（见下方"环境坑"） |
| `zstd-frame-tool.cjs` | 会话日志 `session.v4.jsonl.zstd` 的解压（多帧） |
| `ctx-analyze.cjs` / `ctx-precede.cjs` / `probe-time.cjs` | 上下文与会话时序分析 |
| `market-scan.mjs` / `market-pick.mjs` / `market-detail.mjs` | 插件市场检索（npm registry） |
| `netprobe.mjs` | 网络可达性探测 |

## 根目录

用户放的两张梗图（DeepSeek 鲸鱼娘，豆包 AI 生成）：

- `chat_img1.png`：她抱着一块**泥土**，气泡写"这个工作台怎么打不开？"——笑点是**她认不出泥土和工作台**。
- `chat_img2.png`：她叉腰自信地说"let me合成一个木镐。"，合成格里木板位置不对，**本该放木棍的位置摆了两个木按钮**——笑点是自信十足＋配方全错。

⚠️ **我首次描述这两张图时两处都读错了**（把泥土说成工作台、把木按钮说成木棍）。错法一致：**按"气泡文字／配方 schema 的预期"补全，而不是按像素**。
规则：图像描述里的**关键细节必须由第二观察者（用户）复核**；描述时要区分"我看到的"与"我推断的"。

⚠️ 文件格式坑：它们原本叫 `.jpg`，实际字节是 PNG——前端按"声明的 MIME"校验，格式不符就**拒绝上传**（模型能不能看图是另一回事）。
遇到"图片不让上传"，先核对扩展名与真实魔数（`89 50 4E 47`=PNG、`FF D8 FF`=JPEG、`GIF8`、`RIFF....WEBP`）；`read_image` 同样会按扩展名校验，名字不对会报"bytes use a different image format"。

## 环境坑（摘要；简版在 MEMORY.md 的「本机环境要点」，详版见档案《本机 DSH / Mnemon 环境运维记录》）

1. **沙箱内 HTTPS 走不通 Schannel**（低完整性令牌拿不到凭据）→ `curl.exe`、`Invoke-WebRequest` 全灭；用 `tools\httpsget.mjs` 或 Node 自带 `fetch`（OpenSSL，不受影响）。`web_fetch` 工具本身是好的。
2. **`raw.githubusercontent.com` 时好时坏** → 优先 `api.github.com`，返回的 base64 在本地解。
3. **整图渲染的公告页**（如盛趣官网）→ 下载其公开 CDN 图片，用 Windows 内建 OCR（`zh-Hans-CN`）读字；OCR 有噪声，数字与单位要标"未取到"而不是硬认。
4. **插件目录是 desktop profile**：本机 profile 名 `desktop`（`%USERPROFILE%\.dsh\profiles\desktop`），不是官方文档常见的 `web`——照抄文档里的 `--profile web` 会写到另一个 profile 上。
5. **`npm` 不能直接叫**：PowerShell 会解析到 `C:\nvm4w\nodejs\npm`（**无扩展名**那个），命令名被吃掉一个字符，报 `Unknown command: "pm"`。**一律用 `npm.cmd`**（或 `node <node 安装目录>\node_modules\npm\bin\npm-cli.js`）。
6. **npm 默认缓存写不进去**：缓存在 `%LOCALAPPDATA%\npm-cache`（工作区外），`workspace-write` 下报 `EPERM ... _cacache\tmp\...`。**加 `--cache <工作区>\scratch\npm-cache`**。这是**写**权限问题，**不是网络问题**——网络是通的。
