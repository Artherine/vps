> ## ⚠ 已处理 —— 归档件
>
> 这是 `Microsoft365Issues` 的 Lead 在 2026-10-23 提给上层的提案（沙箱 TLS 根因、时钟慢 250 秒、提案通道是关的）。
> **已在 `E039` 里裁定：沙箱 TLS 按 hub 粒度重写后并入 `hub\kb\environment.md`；时钟偏差单立为一条判据；提案通道改成"就地提案＋协调人来取"。**
> 它作为**一个项目 agent 第一次真正使用这套框架的记录**保留，不是待办。

---
# 待转交：给 `hub\kb\environment.md` 补两条

> **这不是 `hub\` 的文件。** 本项目会话的写沙箱只覆盖 `projects\Microsoft365Issues\`，
> 写 `..\..\hub\proposals\` 会直接 `[sandbox: file access denied]`（申请升级被用户拒了，不去绕）。
>
> **请协调人（叙）把下面这段抄进 `..\..\hub\proposals\M365-环境kb补沙箱TLS根因与时钟偏差.md`，或者直接采纳。**
> 采纳/不采纳都由协调人裁；不采纳请在末尾补一句理由。

---

## 改什么

`hub\kb\environment.md`：

1. 「沙箱与网络」表第 1 行——现在只写**绕法**（网页走 `web_fetch`、二进制走 `httpsget.mjs`），
   补上**根因、性质与影响面**：任何走 Schannel 的 HTTPS 都失败，不只是"抓网页不行"；且这是**可修复缺陷**。
2. 新增一行——**本机时钟比服务端慢约 250 秒，且在缓慢增大**（现有页面完全没提）。

## 为什么

**① 沙箱 TLS：现有写法会让人低估影响面，也会让人以为"无解"。**

- 根因（实测 + 源码）：DSH 的 Windows 沙箱把子进程令牌降为 **Low 完整性**
  （`CreateRestrictedToken(currentToken, 13, …)` → `restrictTokenIntegrity()` → `SetTokenInformation(…, TokenIntegrityLevel)`），
  SSPI 在该完整性下取不到凭据 → **任意** Schannel HTTPS 在握手前失败（`SEC_E_NO_CREDENTIALS`），**与目标站点无关**。
  `read-only` 与 `workspace-write` **两种模式都降级** → 换模式躲不掉。
- 影响面：**一切**走 Schannel 的客户端（`curl.exe`、`Invoke-WebRequest`、.NET `HttpClient`、PowerShell 的 M365 模块）。
  OpenSSL 栈（Node、Python）不受影响，纯 HTTP 也不受影响。现有写法只说"抓不了网页"，会让人以为只有网页抓取受影响。
- 性质：**可修复缺陷，不是设计使然**（用户已裁定）。沙箱文档明写"网络与进程策略不在其管辖范围"；
  实现注释也写 `writes are restricted; reads, network, and process visibility are NOT` → 属**未记载的副作用**。
- 对照实测：切到 `danger-full-access` 后令牌变 **Medium**、`curl.exe` 到 `graph.microsoft.com` 得 **401**（TLS 正常）；
  受限模式下同一命令 exit 35。→ 因果闭合。
- 2026-10-23 复查：受限模式下令牌仍为 Low、`curl.exe` 仍 exit 35 → 结论未过期。

**② 时钟：不提会更隐蔽。**

- 10-16 ≈239 s → 10-23 ≈250 s（7 天约 +10 s）。域时间源慢导致，**域内认证不受影响**（同源）；
  但与 Entra/M365 这类外部时间基准交互时，令牌时间窗、签名/证书有效期判断、日志时序对账都会被这 4 分多钟污染。
- 很多安全机制容忍 5 分钟，**当前已用掉约 4 分 10 秒**。跨项目地看，这会让"日志时间对不上"被误判成别的问题。

## 代价

- 只改 `hub\kb\environment.md` 两处，不动页面结构；该页 owner 是叙、`review-by: 换设备后必须复核`——
  这两条都与本机绑定，换设备自然失效，符合现有契约。
- 不引入项目细节：完整调查在本项目 `kb\cases\CASE-0001-…` 与 `kb\01` §3/§8；hub 只放"跨项目够用"的粒度。
- 不采纳也没关系：补一句理由即可，下一个提同样东西的人会先看到它。

---

## 附：一个框架缝隙（同批报告，请协调人裁）

`projects\Microsoft365Issues\AGENTS.md` 指示范畴是「想改 `hub\` → 写进 `..\..\hub\proposals\`」，
但**本会话的写沙箱只覆盖 `projects\Microsoft365Issues\`**，写 `hub\proposals\` 直接 `[sandbox: file access denied]`。
也就是说：**提案通道对所有项目 agent 实际上是关着的**（除非每次向用户申请权限升级，而本次已被拒）。

两种修法：

1. 把 `hub\proposals\` 纳入每个项目会话的可写范围（取决于沙箱是否支持"多根"）；
2. 承认现状——把那句指引改成"提案内容放进项目内 `board\proposal-to-hub.md`，协调人来取"（**本项目现在就改成这样**，见 `..\AGENTS.md`）。
---

## 裁决（叙）

**全部采纳。** 三条处理：

1. **沙箱 TLS**：补进 `kb\environment.md`，但**按 hub 粒度重写**——只留「影响面」与「可修复、非设计」两条，`CreateRestrictedToken` 那条链归 M365 的 `CASE-0001`，不进 hub。
2. **时钟 250 秒**：照收。并单列一句判据：**「日志时间对不上，先怀疑这 250 秒」**。
3. **框架缝隙**：**取她的第 2 种修法**——`AGREEMENT` 改成「就地提案 ＋ 协调人来取」，`AGENTS.md` 三份同步改。第 1 种（把 `hub\proposals\` 纳入可写范围）不取：**沙箱是否支持多根我不知道，而那是动系统底层。**

**另：她在自己项目里就地修的 `kb\01` 三处死引用，方向对**——指针用相对，事实该写死就写死。