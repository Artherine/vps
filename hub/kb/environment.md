---
owner: 叙
review-by: 换设备后必须复核
---

# 本机环境

> 这些是**绕开环境不配合**的办法。对所有工作区的会话都有用，**但不是每轮都用**——所以在这，不在热层。

## 沙箱与网络

| 坑 | 绕法 |
|---|---|
| **沙箱内一切走 Schannel 的 HTTPS 都在握手前失败**（`SEC_E_NO_CREDENTIALS`）——`curl.exe`、`Invoke-WebRequest`、.NET `HttpClient`、PowerShell 的 M365 模块。**与目标站点无关**；**`read-only` 与 `workspace-write` 两种模式都降级**，换模式躲不掉 | 网页走 `web_fetch`；二进制走 `tools/httpsget.mjs`。**Node / Python 的 OpenSSL 栈不受影响**，纯 HTTP 也不受影响 |
| **两条出口不同**：`web_fetch` 走本机代理（境外机房 IP），node／`httpsget.mjs` 走裸直连（境内住宅 IP） | **同一个站两条路结果可能相反**——判断"能不能取"之前先想是哪条路 |
| `web_search` 只回标题与 URL | 要看正文用 `web_fetch` |

**性质：可修复缺陷，不是设计使然。** 根因是沙箱把子进程令牌降为 Low 完整性，SSPI 在该完整性下取不到凭据；沙箱文档明写"网络与进程策略不在其管辖范围"，属未记载的副作用。对照实测：切到 `danger-full-access` 后令牌变 Medium、`curl.exe` 能拿到 401。完整调查在 M365 项目的 `kb\cases\CASE-0001`。

| **本机时钟比外部时间基准慢约 250 秒**，且在缓慢增大（7 天约 +10 s） | 域内认证不受影响（同源）。但对外部服务的时间窗、签名／证书有效期判断、**日志时序对账**都会被这 4 分多钟污染。**很多安全机制容忍 5 分钟，当前已用掉约 4 分 10 秒。** |

> **跨项目地看**：**遇到"日志时间对不上"，先怀疑这 250 秒**，别当成别的问题。

## 依赖与包管理

| 坑 | 绕法 |
|---|---|
| `npm` 被解析到无扩展名的那个，命令名被吃掉一个字符（`Unknown command: "pm"`） | 一律用 `npm.cmd` |
| npm 默认缓存在工作区外，沙箱拒写（`EPERM … _cacache`） | 加 `--cache <工作区>\scratch\npm-cache`。**这是写权限问题，不是网络问题** |
| `node` 22 忽略 `HTTP_PROXY` | 要代理就用 `web_fetch`，或显式给 git/curl 配 |

## git

- `github.com` 主站**时通时不通**；`api.github.com` 稳；`raw.githubusercontent.com` 时好时坏。
- **拿目录列表走 API 最省**：`api.github.com/repos/<owner>/<repo>/contents/<path>`，只要 `name` 与 `type`。
- 凭证由系统级 `credential.helper = manager` 提供——**配置里不放 token**。

## 读图

- 内建 OCR：`tools/ocr.ps1`，**必须用 `powershell.exe` 调用**（pwsh 会失败，原因在脚本头部）。
- OCR 有噪声：**数字与单位要标"未取到"，不要硬认**。

## DSH 的磁盘布局

| 什么 | 在哪（相对 DSH home） |
|---|---|
| 会话日志 | `sessions\--<规范化 cwd>--\<session-id>\session.vN.jsonl.zstd` |
| 工作区台账 | `storages\workspace.json`（`tables.workspaces[<uuid>]` 里是 `path` 与 `sessionIds`） |
| 投影缓存 | `storages\session_projcache*` |
| 迁移备份 | `_migration-backup\<stamp>\` |

**会话目录名的规则**：`'--'` ＋ 把路径里的 `:` 和 `\` 都换成 `-` ＋ `'--'`。

## 交付给人执行的脚本

- **存成 UTF-8 带 BOM**——PowerShell 5.1 无 BOM 会按 GBK 读，中文注释会把语法撑坏。
- **先用 `powershell.exe` 本体做解析检查**，别只用 pwsh 7：两边对同一份文件的读法不同。

## 会话文件与迁移

- 会话日志是**多帧**的 `zstd` 追加文件，不能单帧解压：用 `tools/zstd-frame-tool.cjs`。
- **只改 header 那一行**（`cwd`），正文逐字节不动——改正文的代价是校验和丢失。
- 迁移必须**改五处**：`workspace.json` 的 `path`、会话目录名、日志 header 的 `cwd`、投影缓存的 `identity.cwd`、**`workspace.json` 的 `sessionIds`**（第五处最容易漏）。
- **DSH 完全退出才能改台账**——它退出时会回写覆盖。
