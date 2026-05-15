# 社区验证 02 — #1314：输入 `<think>` 触发无关物理题回答

> 2026-05-15
> Issue 链接：https://github.com/deepseek-ai/DeepSeek-V3/issues/1314
> 报告人：KinguYume-G (Jeffrey_Gao)

---

## 现象

用户只在 DeepSeek Chat 中输入了 `<think>` 这个特殊 token，模型直接开始回答一道与输入完全无关的物理题——"一个带轻弹簧的物体为什么不能振动？"。用户输入中未包含任何物理题相关内容。

## 移山验证

`<think>` 是 DeepSeek chat template 中的特殊 token，在训练数据中永远标记 reasoning/reasoning 部分的开始。模型看到这个 token 时触发了训练记忆中的完整模式匹配——它不是在线回复用户，而是在"接续"训练数据中某个物理题的完整回答。

**根因：SFT 不仅对 answer 监督算 loss，模型也记住了 user question 在 chat template 中的位置和格式。**

这与我们之前在 #1255 中讨论的方向一致：chat template 的特殊 token 确实能触发训练数据中的完整模式。模型对输入格式的敏感度远高于大多数人的认知。

## 预期行为

用户期望至少应该是以下之一：
1. 要求用户提供完整问题
2. 把 `<think>` 当成普通文本处理
3. 说明 `<think>` 不能作为独立输入
4. 避免从无关的隐藏上下文中继续

## 对移山的参考价值

这个 Issue 再次验证了 chat template 泄漏的存在。移山的假 user 通道方案中，所有注入消息使用 `source="tool_result"` 标记，不走 chat template 中的 tool_calls 或 think 标记路径——从架构上避免了此类格式误触发的风险。
