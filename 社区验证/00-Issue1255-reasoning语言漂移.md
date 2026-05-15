# 社区验证 00 — #1255：工具调用后 reasoning 语言漂移

> 2026-05-15
> Issue 链接：https://github.com/deepseek-ai/DeepSeek-V3/issues/1255
> 报告人：fkyah3（愚公）

---

## 现象

DeepSeek V4 在 Agent 工具调用场景下，thinking/reasoning 块在触发工具调用后从中文自动切换为英文，且无法通过后续对话指令恢复。

## 移山验证

**累计 1200 次 API 调用，跨 8 个维度验证。**

### 根因链

1. **V4 的 Interleaved Thinking** — reasoning 历史在 tool call 后永久保留（必须回传，否则 API 400）
2. **temperature 固定为 1** — 每一条 reasoning token 是概率采样，非确定性
3. **工具返回内容多为英文** — 一旦英文 token 进入 reasoning 链，后续采样概率持续偏向英文
4. **正反馈循环** — 污染 → 采样偏向 → 更多污染 → 更偏向 → 无法恢复

### 与另外两家的对比

| | DeepSeek V4 | OpenAI o-series | Claude extended T |
|:-|:-----------|:---------------|:-----------------|
| reasoning 回传 | 必须回传（否则 400）| 不必回传 | 不必回传 |
| temperature | 固定为 1 | 可控 | 可控 |
| 漂移风险 | 高 | 低 | 低 |

### 实验数据

- **中文 prompt**：中文 reasoning 100%，avg rt 304
- **无锚定 prompt**：中文 reasoning 30%，avg rt 236
- **精准约束 prompt**：中文 reasoning 100%，avg rt 50（单轮场景）
- **多轮工具调用**：稳定性天花板 ~90%，prompt 层无法突破

### 移山的解决方案

假 user 通道 + 子 agent 调度器（V2 已实现）。核心：不让英文结构化数据进入主模型的 thinking 通道，所有工具调用结果通过 user 通道回传，格式为中文 markdown。

### 社区响应

该 Issue 获得了 DeepSeek 官方回复（2026-05-07），确认将改进文档。社区成员 qingkong66 在 #1255 中提供了持续的技术分析支持，并将连接至 #1244、#1262、#1304。
