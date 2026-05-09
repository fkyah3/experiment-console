# Experiment Console

**DeepSeek API 消息积木实验台——逐条控制 messages/reasoning/tool_calls**

把 AI 的 messages 拆成一块块积木，手动组装每条 system/user/assistant/tool 消息。reasoning_content 和 content 分开显示，tool_calls 完整支持。

## 核心功能

- 逐条增删改 system/user/assistant/tool 消息（支持 reasoning_content + tool_calls）
- 展开 assistant 查看 🟠 reasoning 和 🔵 content 两个区域
- 参数全控制：模型/thinking/effort/max_tokens/temperature/top_p/freq_penalty
- 支持真实 tool calling（list_dir / read 双工具，自动轮转上限可调）
- 发送前 sanitizer 自动补 reasoning_content 兜底
- 批量实验模式：一键跑 N 轮，自动生成统计报告
- 原始 JSON 日志：完整请求体 + 响应体 + usage 统计

## 下载

- **Windows 免安装版**：[Releases v1.0.0](https://github.com/fkyah3/experiment-console/releases/tag/v1.0.0)
- **蓝奏云备用**：https://wwbst.lanzoul.com/iasDd3ovm1gd

## 文档

| 文件 | 内容 |
|:-----|:------|
| `使用手册.md` | 完整操作指南 |
| `使用说明.md` | 快速上手说明 |
| `docs/deepseek-api/` | DeepSeek 官方 API 文档（参考用） |

## 实验数据与调研报告

| 文件 | 内容 |
|:-----|:------|
| `实验报告/` | 320+ 次批量验证全部数据 |
| `分析报告/01-工具调用reasoning语言漂移溯源.md` | **数据库溯源：工具调用后 reasoning 从中文切英文的根因分析** |
| `分析报告/02-繁体字泄漏分析.md` | **额外发现：训练数据导致的简体→繁体字符泄漏** |
| `分析报告/04-推理语言漂移复现分析-成功复现与根因确认.md` | **基于真实案发现场成功复现漂移，确认 API 行为差异** |

## 关键技术实现

- Godot 4.6 + GDScript
- HTTPClient 非阻塞 SSE 流式接收（完全自写，无第三方依赖）
- tool_calls 检测基于 `_tool_call_buf` 数据存在性而非 `finish_reason`（DeepSeek SSE 不发 finish_reason）
- 消息构建：reasoning_content 独立发送（不合并到 content），保留多轮推理链

## 相关讨论

[DeepSeek-V3 Issue #1255](https://github.com/deepseek-ai/DeepSeek-V3/issues/1255) — 中文 vs 英文 reasoning 控制实验
