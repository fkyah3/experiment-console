@qingkong66 更新一下最新进展。

语言层实验刚收口。累计 ~1200 次调用，跨八个维度（prompt 措辞迭代、推理强度对比、多轮工具调用漂移、多语言跨五语系）。完整报告和文言文 50 批次数据已推到 experiment-console。

**核心结论：省 token 不是目标，精准描述需求才是。**

最精简的 prompt（"你是一个 AI 工程助手"）中文 reasoning 只有 30%。精准约束 prompt（"你的 reasoning 和 content 都必须使用中文，代码、路径、工具名、文件名、错误信息不翻译"）拉到 100%，虽然更长。

**文言文数据的实际解读：**

avg rt 229，比中文 304 还低——但这个"低"不是因为文言文高效，是模型没有做深度推理。文言文 prompt 下的 reasoning 实际是现代中文 92 rt（只是简单规划了"抓住核心、用文言文表述"），content 层做了一个表面的文言文包装，但信息量掉了 10 倍（482 字 vs 中文 4743 字）。低 rt 不是效率高，是交付标准低。

**多轮工具调用的天花板：**

三组 prompt 对比（基准、身份锚定、机械标记）的结果一致——稳定性的天花板在 90% 左右，再往上推不动了。根因是 V4 的 Interleaved Thinking 将 reasoning 历史改为永久保留，一旦漂移就形成正反馈。这意味着提升稳定性要靠工程层解决。

移山的工程层方案（假 user 通道 + 子 agent 调度器）已在 V2 实现。所有数据在 experiment-console 仓库。

---

Latest language layer experiments wrapped up. ~1200 API calls across 8 dimensions. Full report in experiment-console.

**Key finding: precision over brevity.** The shortest prompt achieved only 30% Chinese reasoning. A precise constraint prompt hit 100% — despite being longer.

**Classical Chinese data note:** 229 avg rt looks impressive until you check content — 482 chars vs 4743 chars in Chinese. Low rt is not efficiency, it's low delivery standard.

Multi-turn tool calling has hit a ceiling (~90% stability) that prompts can't break through. Root cause confirmed: V4's Interleaved Thinking creates a positive feedback loop once drift starts. Fix needs to come from the engineering layer.

MountainShift's engineering solution (fake user channel + sub-agent scheduler) is in V2 implementation.
