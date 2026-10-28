# 新设备引导（bootstrap）

> **这一页解决的问题**：把会话搬过去，不等于把"读会话的那套机制"搬过去。
> **顺序是"配置先于内容"**——机制不同构的时候迁过去，第一件事就是被旧机器处理一遍。

## 零、为什么需要这一页

**仓库里同步的是"内容"（`hub\` / `tools\` / `AGENTS.md` / 作品 / 会话快照），不是"装置"。**
装置有四样，**每样都要在新设备上单独做**，做漏一样，跃迁就会退化成"格式对、语义错"。

## 一、装置清单

| # | 东西 | 在哪 | 怎么过去 |
|---|---|---|---|
| **1** | **DSH 本体** | `C:\Program Files\DSH Desktop\` | 装。**版本至少不低于来源设备** |
| **2** | **压缩参数**（`contextWindow` / `thresholdRatio` / reserve） | `~\.dsh\profiles\desktop\cordis.patch.yml` | **不在仓库里**。仓库里存了一份参考副本：`tools\reference\cordis.patch.yml`，照它改 |
| **3** | **压缩提示词**（v4：第三人称、过去时、计数带 as-of、禁止盘点外部状态） | `…\dsh-compaction-basic\lib\` 里的文件 | **跑 `tools\patch-compaction-prompt.mjs`**（需管理员；DSH 更新会覆盖，重跑） |
| **4** | **mnemon 与记忆层** | `~\.mnemon\` | **它自己走 git**（`mnemon-sync` 分支），配好 `sync-git.json` 后拉 |

> **2 和 3 是最容易漏的**——因为它们在 `~\.dsh\` 和 `Program Files\`，**都不在工作区里，git 看不见。**

## 二、工作区形状（必须和来源设备一致）

```
C:\Artherine\DSH\            ← 必须是这个路径。会话 header 里的 cwd 是它
  hub\                       仓库
  tools\                     仓库
  AGENTS.md                  仓库
  projects\                  那台若在别的盘，用 junction 指过去
  sessions\                  仓库（会话快照，session-sync.ps1 用）
```

**`projects\` 做 junction 是允许的**——DSH 不特殊处理它。
**但 `~\.dsh\sessions\` 不能做 junction**——2026-10-27 实测：DSH 认不出，会话会从根上消失（见 `T06` 第九节）。

**盘预算**：C 盘放工作区壳（约 40 MB ＋ `.git`）；工程放 `projects\` 的 junction 后面。

## 三、顺序

```
1. 装 DSH（版本 ≥ 来源设备）
2. 建 C:\Artherine\DSH
3. 装 mnemon，配 sync-git.json 指向 Artherine/vps，拉 mnemon-sync 分支
4. clone 仓库到 C:\Artherine\DSH（或用现有目录 pull）
5. 按 tools\reference\cordis.patch.yml 改本机的 cordis.patch.yml
6. 管理员运行 tools\patch-compaction-prompt.mjs
7. projects\ 建 junction 指向工程所在盘
8. 验：开一个空会话，确认压缩参数与提示词生效
9. 才轮到 session-sync.ps1 -Action take
```

**第 8 步是验收门**——**没过就别做第 9 步**。机制没验就搬会话，等于让旧机器读新账。

## 四、验收：怎么知道"机制同构"了

| 验什么 | 怎么验 | 期望 |
|---|---|---|
| 压缩参数 | 开一个会话，让它涨到接近阈值，或查 `cordis.patch.yml` 实际生效值 | 阈值 ≈ 727,616（不是 678,464） |
| 压缩提示词 | 读 `…dsh-compaction-basic\lib\` 那份文件的开头几行 | 第三人称、过去时、"计数必须带 as of" |
| 路径契约 | 新会话的 `session/title` 与项目归属 | cwd 是 `C:\Artherine\DSH`，归属在 `sessionIds` 里 |

## 五、还没自动化的部分

- **第 5 步要手工**：`cordis.patch.yml` 没有 patch 脚本，目前只能照参考副本改。
- **第 3 步凭据**：`sync-git.json` 里不含 token（认证走系统凭据管理器），那台要单独配一次。
- **`.git` 体积**：publish 前几次是完整对象，定期 `git gc`。