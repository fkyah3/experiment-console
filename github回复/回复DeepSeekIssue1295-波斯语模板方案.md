@FrameworkPython 这个问题我们在 #1255 中遇到过，提供一个已验证的方案。

**第一步：system prompt 里直接注入波斯语模板。**

以下是我们在 50 次批量实验中验证过的波斯语 system prompt（92% 稳定性，46/50 reasoning 保持波斯语）：

`
تو یک دستیار هوش مصنوعی هستی.
reasoning و content تو باید به فارسی باشد
کد، مسیرها، نام ابزارها، نام فایل‌ها و پیام‌های خطا را ترجمه نکن.
`

如果只看输出（content）层，这个模板基本够用——content 语言被锁在波斯语的概率很高。

**第二步：如果同时需要保持 reasoning 语言一致，除了 system prompt，还需要注意 tool call 通道的污染问题。**

多轮 tool call 会让英文 token 通过 tool_calls 字段进入 assistant 消息层，冲刷掉语言锚定。我们的解决方案是将工具调用结果通过假 user 通道注入，而不是直接放在 tool_calls 字段。具体见 #1255 中的讨论。

**总结：**
- 只看 content → system prompt 模板就够，稳定 ~95%
- 同时需要 reasoning → 需要 system prompt + 控制 tool call 通道

完整的波斯语模板和其他语言的模板已在 experiment-console 仓库开源。

---

@FrameworkPython We've run into this same issue in #1255 and have a validated mitigation.

**Step 1: Inject the Persian system prompt template.**

This Persian system prompt achieved 92% stability (46/50 Persian reasoning) in our 50-batch test:

`
تو یک دستیار هوش مصنوعی هستی.
reasoning و content تو باید به فارسی باشد
کد، مسیرها، نام ابزارها، نام فایل‌ها و پیام‌های خطا را ترجمه نکن.
`

For output (content) layer only, this template is sufficient — content language stays Persian ~95% of the time.

**Step 2: If you also need reasoning language consistency, tool call channel contamination needs to be addressed.**

Multi-round tool calls inject English tokens into the assistant layer through tool_calls fields, washing out language anchoring. Our solution routes tool call results through a fake user channel instead. See #1255 for details.

**Summary:**
- Content only → system prompt template is enough, ~95% stable
- Content + reasoning → system prompt + tool call channel control needed

All Persian and multi-language templates are open source in the experiment-console repo.

---

Experiment Console: https://github.com/fkyah3/experiment-console
Multi-language templates: analysis report / multi-language prompt templates
