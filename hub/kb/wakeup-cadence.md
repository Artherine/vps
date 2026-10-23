---
owner: 叙
review-by: 首次在真实会话里用过之后复核（结论尚未实证）
---

# 唤醒与节拍：单人多会话场景的取舍

先校准一句：机制的复杂度应匹配**等待时长 × 失败代价**，而不是匹配"它叫不叫 agent"。一次 LLM 调用（秒—分钟、无状态）只配拥有 timeout + 幂等键；心跳、工作流引擎、邮箱、调用中途 resume 全是多余的——传输层已经有超时，语义上也无法从中途恢复。

## ① 机制 → 适用条件 → 失败模式

| 机制 | 适用条件 | 失败模式 |
|---|---|---|
| 定时 tick + 状态文件谓词 | 事件源是人或文件；延迟容忍分钟级 | 无谓词过滤则空转烧 token；无锁则重复唤醒 |
| webhook / 消息队列 | 高频外部事件、多消费者、需削峰 | 单人场景无源可接，纯增复杂度；重复与乱序 |
| 长轮询 | 调用方在线等、要秒级反馈 | 按"人数×时长"占连接；人不在线时纯浪费 |
| 引擎 wait / timer / signal | 等待以小时—天计、崩溃不能丢状态 | 引擎成为单点与权威瓶颈；signal 需幂等 |
| Sensor / deferrable | 等待期间资源贵（worker slot 稀缺） | reschedule 只能按时间、不能按条件；triggerer 单点 |
| run 内阻塞等人 | 仅秒级确认 | 不可存档、不可恢复（见坑 1） |
| agent 自调度 / 自省 | 基本无适用条件 | N 个时钟漂移；自判"没事"即永久停摆 |
| Actor 邮箱 | 多 agent 高频互发、需故障隔离 | 队列无界、无背压，堆积至 OOM |
| 心跳看门狗 | 等外部回调、可能无限期 | 只证存活不证进展（见坑 2） |

## ② 一句话结论

**引擎侧放一个免费的非 LLM tick（cron / 轮询，分钟级）读状态文件判谓词，谓词为真才花 token 唤醒会话；人的决策以"写文件"作为事件；agent 永不自调度；等待期间进程退出、状态落盘。**

即：引擎推的是"检查"，不是"干活"；人只管"决策"，不管"节拍"。事件驱动在**延迟**维度上不必要（事件按人的节奏到达，秒级优化无意义），只在**互斥**维度上必要——但那用锁文件就够，不必上消息队列。

## ③ 两个最容易踩的坑

**坑 1：把"等人"做成占用资源。** 在 run 内阻塞等用户，AutoGen 自己警告会把团队置于"无法保存、也无法恢复"的不稳定态；Airflow 恰好反过来做——等人是 scheduler 管理的 `awaiting_input` 状态，连 triggerer 进程都不需要。同一个人离线八小时，前者丢掉全部上下文并占死一个 worker，后者零成本。推论：长周期的"等外部事件"与"等人"都不该持有进程。

**坑 2：把"有心跳"当成"在进展"。** PID 存活、最近心跳时间戳只证明 wrapper 在跑：僵死的会话心跳照样新鲜（由外壳代发），空转的 agent 心跳也新鲜却一个文件没改。行得通的便宜判据是**产物单调递增**——文件 mtime、diff 行数、token 流速；心跳只能定"死"，产物才能定"卡"，两者要对症下药：死→重试，卡→升级给人。附带的变体：不加锁的轮询会让两个会话同改一个文件，而且每次唤醒都计费。

## 引用

- Airflow deferrable / triggerer，及其 HITL 用 `awaiting_input` 而不占 worker：[airflow.apache.org](https://airflow.apache.org/docs/apache-airflow/stable/authoring-and-scheduling/deferring.html)
- Step Functions `Wait` 状态（相对秒 / 绝对时间戳）：[state-wait](https://docs.aws.amazon.com/step-functions/latest/dg/state-wait.html)
- Step Functions回调任务令牌与 `HeartbeatSeconds`（超时即 `States.Timeout`）：[connect-to-resource](https://docs.aws.amazon.com/step-functions/latest/dg/connect-to-resource.html)
- AutoGen HITL：run 内阻塞"不可保存或恢复"：[microsoft.github.io/autogen](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/human-in-the-loop.html)
- Erlang 并发：每进程独立输入队列、无内建背压：[erlang.org](https://www.erlang.org/doc/system/conc_prog.html)

注：temporal.io 与 docs.langchain.com 正文在本环境被墙或只回导航，Temporal / LangGraph 那两行按已知语义写，未取到原文。
