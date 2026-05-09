# 回复 Issue #1255：工程必要性说明

> 双语 / Bilingual
> 关联讨论：[#1255](https://github.com/deepseek-ai/DeepSeek-V3/issues/1255)
> 关联实验结果：[experiment-console](https://github.com/fkyah3/experiment-console)

---

## 中文

追一下 @qingkong66 之前说的"真正痛的是 reasoning 层"。

我们已经在 Experiment Console 上复现并确认了漂移机制（tool_calls 进入 assistant 消息结构触发），也在 DeepSeek Issue 上公开了根因分析。详情见上一回复。

**但我想跳出技术细节，说一下这件事的工程必要性——为什么这个问题值得专门解决。**

最大的点在于：**AI 会强行思考那些缺乏推理前置条件的问题。如果你能看懂它的思维链，你能第一时间发现它走偏了，打断它，纠正它。如果你看不懂——它会越绕越远，直到 token 烧完。**

我 B 站原话是：

> "经典问题——我表妹叫我奶奶什么。你不给说出来，DeepSeek 能思考 120 秒。而这种问题在 debug、编程的时候，会以多种操蛋的形式出现，会缺乏多个条件前置，导致能把 320 多 K 的输出全吃完。"

**这不是边缘案例。这是编程 Agent 的日常：**

- 它调了一个函数，不知道返回值可能为 null——然后基于"一定不为 null"的假设推了 50 轮
- 它读了一个配置文件，没注意到版本号——然后按照旧版本的 API 生成了全部代码
- 它看到"file not found"，没检查路径——然后假设文件存在继续往下推

这些场景的共同点是：**问题不在 AI 的能力，在它不知道"自己缺了什么条件"。** 而如果你能在它的思维链里看清这一点，你可以在第一轮就打断它，给它补上条件，让它继续。

这就是为什么 reasoning 层的语言稳定如此重要：

| 语言 | 审查方式 | 发现问题所需时间 | 你能容忍的推理浪费 |
|:-----|:---------|:----------------|:-----------------|
| **中文** | 稀疏扫读，O(1) | 看 10 行就能定位 | 极小——发现就打断 |
| **英文** | 逐行理解，O(n) | 需要读 30% 才能确认 | 极大——发现时 token 已经烧完 |

中文思维链保持稳定，你扫一眼就知道"这里它默认了 X 但 X 不一定成立"。英文思维链？你要先翻译、再理解、再判断——三个步骤做完，token 已经跑远了。

**这不是母语偏好问题。这是审查效率问题。审查效率决定了你能承受多大的推理浪费。**

很多人说"让 AI 自己弄就行了"——这成立的前提是 AI 能在缺乏条件时自行识别并停下来。但我们的实验已经证明：它不能。它会在一个错误的前提下推出一篇逻辑自洽的废话。而 320K token 足够它把十层嵌套的推理全部跑完——全错。

**实战复盘印证了这一点。** 在工具调用调试过程中，AI 列出了 5 个可能的原因，但无法区分优先级——把真正的根因和不相关的旁支混在一起列出来，停在原地。人类介入后一秒定位。详见：[无前置条件推理的代价——工具调用调试全记录](https://github.com/fkyah3/experiment-console)

**如果你能让 AI 保持中文思考，你就是那个"在起点就发现问题"的人。如果不行，你只能等它跑到终点，然后看着 320K token 的垃圾告诉它"你错了"——然后重新开始。**

我们的实验数据、根因分析、以及可复现的实验台全部开源了。欢迎有兴趣的人自己跑一遍。

---

## English

Following up on what @qingkong66 said earlier — "the real pain point is the reasoning layer."

We've confirmed the drift mechanism (triggered by tool_calls entering the assistant message structure) and published our root cause analysis in this thread. See my previous reply for the technical details.

**But I want to step back and explain why this problem matters from an engineering standpoint — why it's worth solving.**

The core issue is: **LLMs will forcefully reason about problems that are missing preconditions. If you can read its thinking chain, you can catch it going off track immediately, interrupt it, and correct it. If you can't — it keeps spiraling until the token budget runs dry.**

Classic example from my Bilibili post:

> "My cousin calls my grandmother what? If you don't specify which grandmother, DeepSeek will spend 120 seconds thinking about it. This same pattern shows up in debugging and programming in all kinds of infuriating ways — missing multiple preconditions — and it can eat through 320K+ tokens of output."

**This is not an edge case. This is everyday life with a coding agent:**

- It calls a function without checking if the return value can be null — then spends 50 reasoning steps assuming it can't
- It reads a config file but misses the version number — then generates all code against the old API
- It sees "file not found" without checking the path — then keeps reasoning as if the file exists

The common thread: **the problem isn't the model's capability. It's that the model doesn't know what it's missing.** If you can see this in its reasoning chain, you can interrupt in round 1, provide the missing context, and move on.

This is why reasoning language stability matters:

| Language | Review style | Time to spot errors | Tolerable waste |
|:---------|:-------------|:-------------------|:----------------|
| **Chinese** | Sparse scan, O(1) | ~10 lines | Minimal — you catch and fix immediately |
| **English** | Line-by-line comprehension, O(n) | ~30% of output | High — you notice when tokens are already burned |

A stable Chinese reasoning chain lets you glance at it and immediately spot "it assumed X here, but X may not hold." An English chain? You need to translate, then understand, then evaluate — by the time you're done, the model has already gone deep on the wrong path.

**This isn't about language preference. It's about review efficiency. And review efficiency determines how much reasoning waste you can tolerate.**

A lot of people say "just let the AI figure it out." That works if the AI can actually identify and stop when it's missing preconditions. But our experiments prove it cannot. It will produce beautiful, logically coherent nonsense built on a wrong assumption. And 320K tokens is enough for it to run ten levels deep — all wrong.

**Our engineering post-mortem confirms this.** During a tool-calling debug session, the AI listed 5 possible root causes but couldn't prioritize them — mixing the real cause with irrelevant branches, then stopping. A human stepped in and found it in seconds. See: [The Cost of Reasoning Without Preconditions](https://github.com/fkyah3/experiment-console)

**If you can keep the model thinking in Chinese, you're the person who catches the problem at the starting line. If you can't, you wait for it to reach the finish line, look at 320K tokens of garbage, say "you're wrong," and start over — minus 320K tokens.**

Our experiment data, root cause analysis, and the full reproducible test bench are all open source. Anyone interested can run it themselves.

---

**References:**

- Experiment Console (open-source test bench): https://github.com/fkyah3/experiment-console
- Root cause analysis: https://github.com/fkyah3/experiment-console (see analysis reports)
- Windows release: https://github.com/fkyah3/experiment-console/releases/tag/v1.0.0
- Bilibili demo: https://www.bilibili.com/video/BV1S7orB3E5z/
