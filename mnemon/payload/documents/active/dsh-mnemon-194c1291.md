---
id: "194c1291-956e-42a1-b6f8-4b5b84d37ae0"
title: "本机 DSH / Mnemon 环境运维记录"
description: "本机 DSH/Mnemon 环境运维记录（修订 3）：新增 §七 网络与 TLS 真相——本机 HTTPS 正常，故障面是 DSH Windows 沙箱的低完整性级别导致 Schannel 无法获取凭据（SEC_E_NO_CREDENTIALS），web_fetch 实为完全可用；含沙箱内抓取走法 tools/httpsget.mjs 与可达性矩阵。另含身份/权限拓扑、npm prefix 机制、Mnemon CLI 安装、三层记忆状态与文档生命周期政策。"
status: "active"
created_at: "2026-09-30T07:30:01.172Z"
updated_at: "2026-10-15T03:43:04.242Z"
content_hash: "a62ec3e019c839ca6b236b38938e29973e34f8794f3486cccd9c8735d15b7b4f"
source_paths:
  - "tools/httpsget.mjs"
  - "netprobe.mjs"
session_ids:
  - "session-1a212fb6-8418-4172-9eea-4d9f45f9d3c2"
  - "session-0017733d-4c64-4fd4-86e4-386c9c893bca"
memory_body_ids:
  []
---

# 本机 DSH / Mnemon 环境运维记录

记录时间：2026-09-30（修订 3：2026-10-16 追加 §七 网络与 TLS 真相，**推翻** 10-15 的"HTTPS 不通 / web_fetch 不可用"结论）。适用范围：这台机器（用户 `s-wang.well`）上的 DSH Desktop 与 dsh-mnemon 环境。

## 一、身份与权限拓扑
- **DSH 以普通用户运行**（`IsInRole(Administrator)` = False）。用户其它开发工具多以管理员打开——这是本机多数"权限类怪现象"的根因。
- **harness 的 `danger-full-access` 只解除 DSH 自身文件沙箱，不等同于 Windows 管理员令牌**；写 `C:\Program Files\...` 仍被 ACL 拒（EPERM）。
- 补充（修订 3）：该开关同时会**解除沙箱的受限令牌**，把子进程从 Low 完整性提到 Medium 完整性——这正是 §七 中恢复 Schannel 的唯一手段。

## 二、Node / npm / nvm
| 项 | 值 |
|---|---|
| NVM_HOME / SYMLINK | `C:\Programs\nvm`（已装 v10/v11/v16/v20/v22.13/v22.19）／`C:\nvm4w\nodejs` → `v22.19.0` |
| 用户 store | `C:\Programs\npm_store\npm_global`（机器 PATH、普通用户可写；含 dsh/pnpm/yarn/cnpm/mdye-cli 及 npm 11.1.0） |
| 活动 Node 自带 npm | 10.9.3 |

### 关键机制：npm 启动器"就 prefix 取材"
`npm.cmd` 先算 prefix；若 `%PREFIX%\node_modules\npm\bin\npm-cli.js` 存在就用它，否则回退到当前 Node 自带的那份。
→ **不要把 prefix 指向任何含 `node_modules\npm` 的目录**（如 store），否则 npm 版本被钉死、跨版本切换会崩。
→ **教训**：原先那个"僵尸 prefix"（指向并不存在的 `C:\Program Files\nodejs\npm_global`）反而每次都回退到版本自带的 npm，**那个 bug 是承重的**。

### 现行配置（M1，保留 nvm 镜像语义）
```
prefix=C:\nvm4w\nodejs                              # 写符号链接 → 随 nvm use 指向活动版本
cache=%LOCALAPPDATA%\npm-cache
```
验证（v22.19.0）：`npm -v`=10.9.3、`npm prefix -g`=`C:\nvm4w\nodejs`、`npm view @mnemon-dev/mnemon version`=0.2.9（无 EPERM）。
代价：新全局包按版本隔离（切版本需重装或 `--reinstall-packages-from`）；store 工具仍在机器 PATH 上、不受影响（混合态）。备选 M2＝`npm config delete prefix`（回落到 `%APPDATA%\npm`）。还原点：`.npmrc.bak-20260930-153456`。

### 遗留隐患
- 机器 PATH 垃圾条目：`C:\nvm4w\nodejs\node.exe`（文件路径）、相对条目 `npm_global`；清理需管理员。
- store 内原生二进制仅 `@deepseek-ai/dsh`(11) 与 `pnpm`(4)；跨大版本切 Node 有 ABI 风险，建议 dsh/pnpm 常驻 v22。

## 三、Mnemon CLI
- **为何找不到**：`dsh-mnemon` 的 npm Starter **按设计不含**后端二进制；`mnemon` 属独立 npm 包 `@mnemon-dev/mnemon`（已装 **0.2.9**，含 win32-x64 平台包）。
- **位置**：`%LOCALAPPDATA%\Programs\mnemon\`，`mnemon.exe` 必须在**该目录根下**（插件据此搜索）。
- **命令**：`npm install --global @mnemon-dev/mnemon@latest --prefix "%LOCALAPPDATA%\Programs\mnemon" --cache "%LOCALAPPDATA%\npm-cache"`，随后把 `node_modules\...\mnemon-win32-x64\bin\mnemon.exe` 复制到该目录根。
- **验证**：`mnemon version 0.2.9`；插件 `mnemon_status` → `healthy=true, commandFound=true, writeEnabled=true`。
- **查找顺序**（`native-cli.js`）：`config.cliPath` → `MNEMON_CLI_PATH` → PATH → `%LOCALAPPDATA%\Programs\mnemon` → `%ProgramFiles%\mnemon` → `$GOBIN`/`$GOPATH\bin`。
- **卸载**：删除该目录即可，不影响 runtime 与 documents。

## 四、三层记忆的可用状态（已实测）
| 能力 | 状态 | 备注 |
|---|---|---|
| runtime（USER.md / MEMORY.md） | ✅ | 每轮注入 |
| documents 新建 / 检索 | ✅ | |
| documents **就地更新（update）** | ✅ | revision 递增、contentHash 变更；**小改动不必再造新版本** |
| documents **归档（archive）** | ✅ | 先向记忆空间落一份**冷参考**（lineage 可见），再把文件移入 `documents/archived/`；默认检索不含，可用 `includeArchived` 取回 |
| documents 删除 | ✖ 无入口 | 只能手工清理索引（见 §五） |
| memory spaces（`default`，provider `mnemon-native`） | ✅ | `writeMode=exact`、`deletionMode=soft`；`recall` 已实测可召回 |

早先 `update`/`archive` 报 ReadGrant 拒绝，是因为当时空间尚未存在；空间激活后同一 View 已放行。

## 五、文档生命周期政策（修订）
1. **默认就地更新**：知识有变化就 `update` 同一份，revision 会递增。不再需要"新建取代旧"来绕过权限。
2. **归档用于整份被取代或不再需要**：归档会自动留下冷参考（进记忆空间）＋搬进 `documents/archived/`，因此**归档之前不必也不该手工删除**。
3. **删除只作偶发人工清理**（内容确实作废且用户明确要求）：备份 `.mnemon/documents/index.json` → 删 `.md` → 删 `documents[]` 条目；只在有工作区外写权限的会话里做。
4. **铁律：绝不只手删 `.md` 而不管索引**——会留下 `healthy=false`、`excerpt` 空的幽灵条目（本机已发生：索引 6 条 vs 磁盘 3 文件）。
5. 容量不是理由：上限 10 MB，当前活跃仅约 14 KB。

## 六、待办
- [x] 修正 npm prefix（M1，已实施并验证）
- [x] 验证并启用 `update` / `archive`（已解锁，已归档两份过时文档）
- [x] 定位并更正 10-15 的网络误诊（2026-10-16，见 §七）
- [ ] 可选：清理机器 PATH 垃圾条目（需管理员）
- [ ] 可选：把 `mnemon` 装进 store 使其在 PATH 上通用

## 七、网络与 TLS 真相（2026-10-16 复验）

### 结论
**本机 HTTPS 完全正常，不存在"HTTPS 不通"。** 2026-10-15 记录的两条结论——"本机 HTTPS 不通"与"harness 的 `web_fetch` 基本不可用"——**均为误诊，已作废**。

### 真实故障面：DSH Windows 沙箱的完整性级别
沙箱内执行的 pwsh 运行在**受限令牌 + 低完整性级别**下：

```
whoami /groups  →  Mandatory Label\Low Mandatory Level   S-1-16-4096
```

Schannel（Windows 原生 TLS 栈）在低完整性下无法获取凭据，于是**一切依赖 Windows 原生 TLS 的客户端全部失败**：

| 客户端 | TLS 栈 | 沙箱内（Low IL） | 沙箱外（Medium IL） |
|---|---|---|---|
| `curl.exe`（系统版 8.13 与 Git 自带 8.7） | Schannel | ✗ `schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS (0x8009030E)` | ✅ 200 |
| `Invoke-WebRequest` | Schannel（.NET 10） | ✗ `The SSL connection could not be established` | ✅ 200 |
| `System.Net.Security.SslStream` | Schannel | ✗ `Win32Exception: 安全包中没有可用的凭证` | — |
| Node `fetch` / `https` | **自带 OpenSSL** | ✅ 200 | ✅ 200 |
| Python `urllib` | **自带 OpenSSL 3.0.16** | ✅ 200 | ✅ 200 |

**对照实验（决定性）**：同一条 `curl.exe https://example.com`，沙箱内返回 `000`，以 `danger-full-access` 提到沙箱外立刻 `200`；两次 `whoami /groups` 分别显示 Low / Medium 完整性级别。故**根因是沙箱的完整性级别，与网络、代理、证书、DNS、防火墙均无关**。

补充证据：沙箱内进程 token 用户为 `SYNERGYCMT\s-wang.well`、`IsSystem=False`、组成员仅 9 项（Everyone / Users / INTERACTIVE / CONSOLE LOGON / Authenticated Users / This Organization / LOCAL / NTLM Authentication + 完整性标签），另见 `ProxyEnable=0`、WinHTTP 为 `Direct access`、进程内无 `*proxy*` 环境变量——**根本不存在代理层干扰**。

### 由此确认
- **`web_fetch` 工具完全可用**：它走 Node 自带 OpenSSL，不经过 Schannel。实测 `https://example.com`、`https://www.baidu.com`、`https://www.sdo.com` 均 HTTP 200 且取回正文（含中文站点正文与图片链接）。
- **`web_search` 可用**，但**只返回标题 + URL、不给摘要**；这是该工具的正常表现，不是故障。需要正文时对返回的 URL 再调 `web_fetch`。
- 10-15 误判的成因：当时只在 pwsh 里测了 `curl` / `Invoke-WebRequest`，就把"沙箱内 Schannel 失败"外推成了"整机 HTTPS 不通"，进而外推成"`web_fetch` 不可用"。**教训：诊断 TLS 问题必须先分清 TLS 栈（Schannel vs 自带 OpenSSL），并做沙箱内/外对照。**

### 沙箱内抓取的固定走法
工作区工具 `tools/httpsget.mjs`（Node/OpenSSL，沙箱内直接可用，已实测）：

```powershell
node tools/httpsget.mjs <url> [--json] [-o <file>] [-H "K: V"] [-X VERB] [-d BODY] [--timeout ms] [--max n] [--head] [-q]
```

- `-o` 为二进制安全落盘；实测下载 PNG 魔数 `89 50 4E 47 0D 0A 1A 0A` 正确，可径直接入 Windows 内置 OCR（zh-Hans-CN）流程。
- 等价替代：`node -e "..."` 或 Python `urllib`；**唯独不要用 `curl.exe` / `Invoke-WebRequest`**。
- 若某条命令非 Schannel 不可，只能对该条命令单独申请 `danger-full-access` 一次性提升到 Medium 完整性。
- 诊断脚本：`netprobe.mjs`（逐主机输出 DNS 与 TLS 结果）。

### 可达性矩阵（2026-10-16 实测，Node/OpenSSL）
| 主机 | DNS | TLS / HTTP |
|---|---|---|
| `raw.githubusercontent.com` | ✅ | ✅ 200（42 KB README） |
| `api.github.com` | ✅ | ✅ 200 |
| `registry.npmjs.org` | ✅ | ✅ 200 |
| `example.com` / `www.baidu.com` / `www.sdo.com` | ✅ | ✅ 200 |
| `github.com` | ✅ 解析到 20.205.243.166 | ✗ TCP 超时 |
| `www.google.com` | ✅ | ✗ TCP 超时 |

- **10-15 记的"raw 直连当前不可达"作废**：`raw.githubusercontent.com` 现可直连（200）。
- `github.com` 主站与 `google.com` 仍不可达（DNS 正常解析但 TCP 超时）。因此 `web_fetch` 抓 GitHub 讨论页会报 `fetch failed`——**那是网络层不可达，不是工具故障**；此类内容改走 `web_search` 返回的标题，或 `api.github.com`。

### 上游状态
这是 DSH 的已知问题、非本机独有，参见 deepseek-harness discussions：
- [#997](https://github.com/deepseek-ai/deepseek-harness/discussions/997) —— 中文报告：受限令牌限制 SID 列表使 Schannel 凭据获取被拒
- [#4163](https://github.com/deepseek-ai/deepseek-harness/discussions/4163) —— Windows restricted-token sandbox: Schannel TLS fails with SEC_E_NO_CREDENTIALS
- [#1789](https://github.com/deepseek-ai/deepseek-harness/discussions/1789) —— 受限模式下 dsh 的 pwsh 工具在 Windows 上的问题

结论：在沙箱完整性级别问题被上游修复前，本机一律**用 Node/OpenSSL 通道做 HTTPS**，把 Schannel 客户端视为沙箱内不可用。
