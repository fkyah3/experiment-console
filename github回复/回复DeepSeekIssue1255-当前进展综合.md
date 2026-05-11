# 回复 Issue #1255：当前进展综合

> 双语 / Bilingual
> 2026-05-10

---

## 中文

追一下最新进展。

我们跑了多轮研讨（分析层、工程层、语言层、调研层四层协作），加上 opencode 真实 session 数据溯源和社区方法验证。

### 当前观察

1. **三层锚定效果有限。** system / assistant.content / tool.content 三路注入语言提醒，在多轮工具调用场景下逐轮衰减。目前还不清楚这到底是工程问题还是模型本身的特性，但从已有数据来看，对模型侧的解释似乎更合理一些。

2. **任务框架似乎有影响。** 从 opencode 真实 session（ses_2338）溯源发现：一个"翻译注释"任务，在无 system prompt、无中文锚定词的情况下，模型自愿保持中文 reasoning 42 轮。而同期"分析代码"任务在第 4-10 轮漂移。差异在于指令的任务框架——但这是关联性，不是因果性。

3. **52KB 英文代码一次性注入不漂移，但几轮工具调用会漂移。** 这个现象和"英文 token 占比阈值"的解释不太吻合——模型的 reasoning 语言选择似乎不是按全文占比来的，但具体机制还不清楚。

### 已尝试的方案

- 三层锚定（system / assistant.content / tool.content）→ 多轮场景下衰减
- 社区 `【思维模式要求】` 注入法（victorchen96/roleplay_instruct）→ 复现效果不理想
- B 站 `【中文思维启动】` 强制标记法（源于 [B 站视频](https://www.bilibili.com/video/BV1pERRBcEKG/) 评论区）→ 10 轮中 9 轮保持中文，但第 4 轮仍出现漂移
- 两阶段调用（think→推理，non-think→工具调用）→ 待验证

**当前来看，各种方法都有一定效果，但都不彻底。结果有些扑朔迷离，目前来看对模型侧不太有利。**

### 不确定的问题

从目前的实验来看，有几个现象始终没有好的解释，这里列出来供大家一起探讨：

1. **一次性把代码文件全给，全程中文；多次 tool call 逐步读，几轮就漂。** 同样一份代码，一次性注入不触发漂移，分批读取反而触发——这是最让我困惑的一点。

2. **评论区有人的提示词达到了 90% 的压制率。** 这说明在某些条件下 reasoning 语言是可以被稳定控制的——只是我们还没找到那个条件。

3. **曾经让 AI 完成"翻译代码中的注释为中文"的任务，结果思维链全程中文。** 同一个模型、同一份代码、同一个人操作，只是换了一个任务描述，效果完全不同。

这些现象对我来说都还是疑点。我不能通过推测来下定论，需要一个更严谨、可复现的实验过程来逐个验证。

| 问题 | 当前理解 |
|:-----|:---------|
| 为什么一次性给代码不漂，多次 tool call 漂？ | 推测是任务框架差异，但机制层未确认 |
| 为什么 non-think 模式下 reasoning 可以被完全控制？ | 推测是 attention 权重分配不同，但无代码证据 |
| `【】` 包裹的指令是否确实有更高遵循度？ | 社区有相关反馈，但机制未知 |
| 工程手段能不能彻底解决？ | 目前看到的方案都只能缓解，不能根除 |

### 移山的后续方向

```
近期：继续验证【中文思维启动】的稳定性边界 + 两阶段调用方案
中期：探索任务框架措辞是否能稳定复现 ses_2338 的效果
长期：持续关注模型侧更新
```

所有实验数据、分析报告、复现工具全部开源：
- Experiment Console: https://github.com/fkyah3/experiment-console
- 分析报告：同上仓库 `分析报告/` 目录

欢迎有兴趣的人自己跑一遍，把你的发现告诉我们。

---

## English

Following up with our latest progress on the reasoning language drift issue.

We've run a multi-layer discussion combined with real opencode session data tracing and community method validation.

### Current observations

1. **Three-layer anchoring has limited effectiveness.** Injecting language reminders into system / assistant.content / tool.content degrades over multiple tool-call rounds. It's still unclear whether this is an engineering issue or a model-level characteristic, but the evidence so far leans more toward the model side.

2. **Task framing seems to matter.** Tracing a real opencode session (ses_2338): a "translate comments" task maintained Chinese reasoning for 42 rounds with no system prompt, no anchoring. In contrast, an "analyze code" task drifts at round 4-10. The difference appears to be in the task framing of the instruction—but this is correlation, not causation.

3. **52KB of English code in one shot = no drift. A few tool-call rounds = drift.** This doesn't quite fit the "English token ratio threshold" explanation. The model's reasoning language selection doesn't seem to be based on total token distribution, but the exact mechanism remains unclear.

### What we've tried

- Three-layer anchoring (system / assistant.content / tool.content) → degrades over multiple rounds
- Community `【思维模式要求】` injection method (victorchen96/roleplay_instruct) → didn't reproduce well
- Bilibili `【中文思维启动】` forced marker method (from [Bilibili video](https://www.bilibili.com/video/BV1pERRBcEKG/) comments) → 9/10 Chinese reasoning in batch test, but round 4 still drifted
- Two-phase calling (think→reasoning, non-think→tool calling) → pending verification

**Current picture: various methods show partial effectiveness, but none are conclusive. The picture is somewhat mixed, but the evidence so far leans toward the model side.**

### Open questions

A few observations from our experiments that we don't have good explanations for yet:

1. **Feeding all code files in one shot = Chinese reasoning throughout. Reading them via multiple tool calls = drift within a few rounds.** Same code, same model, different delivery method — completely different reasoning language behavior.

2. **Some users report 90%+ Chinese reasoning suppression with their prompts.** This suggests there IS a way to stabilize reasoning language under certain conditions — we just haven't found the exact condition yet.

3. **A "translate comments to Chinese" task kept reasoning Chinese throughout the entire session.** Same model, same codebase, same operator — just a different task description, and the result flipped completely.

These remain open questions. We're not comfortable drawing conclusions from inference alone — they need rigorous, reproducible experiments to verify.

| Question | Current understanding |
|:---------|:----------------------|
| Why does one-shot code injection not trigger drift, but multi-round tool calls do? | Possibly task framing difference, mechanism unconfirmed |
| Why can non-think mode fully control reasoning? | Possibly different attention weight distribution, no code evidence |
| Does `【】`-wrapped instructions actually have higher compliance? | Community observations suggest so, mechanism unknown |
| Can engineering solve this completely? | Current methods only mitigate, not eliminate |

### MountainShift's next steps

```
Near-term: Validate stability boundaries of 【中文思维启动】 + two-phase calling
Mid-term: Explore whether task-framing phrasing can reliably reproduce ses_2338's results
Long-term: Monitor model-side updates
```

All data, analysis, and tools are open source:
- Experiment Console: https://github.com/fkyah3/experiment-console
- Analysis reports: same repo, `分析报告/` directory

Anyone interested is welcome to run it themselves and share your findings.

---

**References:**
- Experiment Console: https://github.com/fkyah3/experiment-console
- Windows release: https://github.com/fkyah3/experiment-console/releases/tag/v1.0.0
- Bilibili video (method source): https://www.bilibili.com/video/BV1pERRBcEKG/
- Bilibili demo (earlier): https://www.bilibili.com/video/BV1S7orB3E5z/
- victorchen96/roleplay_instruct: https://github.com/victorchen96/deepseek_v4_rolepaly_instruct
