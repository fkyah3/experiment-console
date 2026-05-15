@weizhang-dotcom 这个问题我们在 #1255 里遇到过，根源是同一个。

V4 的 thinking 模式强制 assistant 消息中必须带 reasoning_content，导致 non-think 和 think 之间切换断裂。这个约束本身的设计逻辑可以理解——但它带来的副作用比想象中大。

我们的解法是：

**不让工具调用结果进入 assistant 层的 tool_calls 字段。** 而是通过 user 通道注入工具返回的内容。这样无论当前是 think 还是 non-think，主 agent 的上下文里都没有 tool_calls 这个字段，自然不受"每轮 tool call 必须带 reasoning_content"的约束。

细节参考 #1255 中关于假 user 通道的讨论。

这个方案需要工程层级的改动，不是换个 prompt 能解决的。可能大多数人没这个行动力去改架构，但路在这里了。

---

@weizhang-dotcom We ran into this same issue in #1255. Same root cause.

V4's thinking mode requires easoning_content in every assistant message with tool_calls, which breaks switching between non-think and think.

**Our solution: don't let tool call results enter the assistant layer's 	ool_calls field at all.** Route them through the user channel instead. The main agent's context never contains tool_calls, so the "every tool call must have reasoning_content" constraint doesn't apply.

Details in #1255 under the "fake user channel" discussion.

This requires engineering-level changes, not a quick prompt fix. Most people won't go that deep, but the path is there.
