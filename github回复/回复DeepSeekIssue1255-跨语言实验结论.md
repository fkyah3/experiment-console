# 跨语言实验结论

---

## 双语总结

我们做了 7 组跨语言对照实验（中文、日语、世界语、昆雅语 × Flash/Pro），同一份 52KB 英文论文，零 tool call，一次性注入。结果如下：

| 实验 | system 语言 | 模型 | reasoning 语言 | content 语言 |
|:-----|:-----------|:----|:--------------|:------------|
| 中文 | 中文 | Flash | ✅ 中文 | 中文 |
| 日语 | 日语 | Flash | ✅ 日语 | 日语 |
| 世界语 | 世界语 | Flash | ✅ 世界语 | 世界语 |
| 世界语 Pro | 世界语 | Pro | ✅ 世界语 | 世界语 |
| 昆雅语 | 昆雅语（精灵语） | Flash | ✅ 中文（回退） | 昆雅语 |
| 昆雅语 Pro | 昆雅语 | Pro | ❌ 英文 | 昆雅语 |
| 日语 Pro | 日语 | Pro | ❌ 英文 | 日语 |

### 规律

**Flash 模型：** system prompt 是什么语言，reasoning 就跟着走。即使碰到昆雅语这种训练数据中几乎不存在的语言，reasoning 也会回退到中文。

**Pro 模型：** system prompt 如果是"边缘语言"（训练数据稀少），reasoning 回退到英文。世界语因为有完整的语言学结构和语法体系，保持住了。但日语和昆雅语都没有。

### 推论

Flash 和 Pro 的内部语言机制可能不同：
- Flash 的"身份语言"似乎是**中文**
- Pro 的"身份语言"似乎是**英文**

这也意味着：*两阶段调用方案（子 agent 探索 → 主 agent 决策）在两种模型上都有效，只是根因不同。*

### 对 AI IDE 行业的启示

我们一直怀疑一条自己验证过的事：**OpenAI 的 function calling 规则可能把整个 AI IDE 和应用层带偏了。** 当大家默认遵循一个规则时，很少有人会质疑它。我们质疑了，发现代价比想象中大得多——不限于语言漂移，还包括注意力稀释、推理链断裂、token 浪费。

但移山（我们自研的 Agent 架构体系）已经从架构层面解决了这个问题。具体实现细节在项目完成前不公开。实验数据、分析报告、复现工具全部开源。

另外补充一句：**Godot 不仅有做游戏的潜力，也有做 Agent 客户端的潜力。** Experiment Console 本身就是一个 Godot 4.6 写的完整 API 实验台——支持 SSE 流式接收、tool calling、消息积木式拼接、批量实验。Godot 的 GDScript + HTTPClient + 信号系统足以支撑一个功能完整的 Agent 客户端。如果你还在纠结"用什么框架写 Agent"，Godot 是一个被严重低估的选项。

所有公开数据、分析报告见 [experiment-console](https://github.com/fkyah3/experiment-console)。

移山还在继续。

---

## English Summary

We ran 7 cross-language experiments (Chinese, Japanese, Esperanto, Quenya × Flash/Pro) — same 52KB English paper, zero tool calls, one-shot injection. Results:

| Experiment | System Lang | Model | Reasoning Lang | Content Lang |
|:-----------|:-----------|:------|:--------------|:------------|
| Chinese | zh | Flash | ✅ zh | zh |
| Japanese | ja | Flash | ✅ ja | ja |
| Esperanto | eo | Flash | ✅ eo | eo |
| Esperanto Pro | eo | Pro | ✅ eo | eo |
| Quenya (Elvish) | qya | Flash | ✅ zh (fallback) | qya |
| Quenya Pro | qya | Pro | ❌ en | qya |
| Japanese Pro | ja | Pro | ❌ en | ja |

**Pattern:**

- **Flash**: reasoning follows the system prompt language. Even for Quenya (near-zero training data), reasoning falls back to Chinese.
- **Pro**: "edge" languages fall back to English. Esperanto (has complete linguistic structure) held. Japanese and Quenya didn't.

**Implication:** Flash's "identity language" appears to be Chinese, while Pro's is English. This suggests different internal mechanisms.

Our architecture-level solution (MountainShift) has resolved this issue from the ground up. Implementation details remain private until project completion. All experimental data and analysis tools are open source.

Also worth noting: **Godot is underrated as an Agent framework.** Experiment Console itself is built entirely in Godot 4.6 — it supports SSE streaming, tool calling, message assembly, and batch experiments. GDScript + HTTPClient + signal system is more than capable for a full-featured Agent client. If you're deciding on a framework, Godot deserves a look.

All public data: [experiment-console](https://github.com/fkyah3/experiment-console)

MountainShift continues.
