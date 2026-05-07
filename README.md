# Experiment Console

**DeepSeek API 消息积木实验台——逐条控制 messages/reasoning/thinking**

把 AI 的 messages 拆成一块块积木，让你手动组装。每条 system/user/assistant/tool 消息独立控制，thinking 开关任意切换，reasoning_content 和 content 分开显示。

## 下载

- **Windows 免安装版**：[Releases v1.0.0](https://github.com/fkyah3/experiment-console/releases/tag/v1.0.0)
- **蓝奏云备用**：https://wwbst.lanzoul.com/iasDd3ovm1gd

## 核心功能

- 逐条增删改 system/user/assistant/tool 消息（支持 reasoning_content + tool_calls）
- 展开 assistant 查看 🟠 reasoning 和 🔵 content 两个区域
- 参数全控制：模型/thinking/effort/max_tokens/temperature
- 批量实验模式：一键跑 40 轮，自动生成统计报告
- 原始 JSON 日志：完整请求体 + 响应体 + usage 统计
- 实验模板：中文锚定测试、前置条件测试，一键加载

## 文档

| 文件 | 内容 |
|:-----|:------|
| `使用说明.md` | 完整操作指南 |
| `docs/deepseek-api/` | DeepSeek 官方 API 文档（参考用） |
| `视频文案.md` | B 站视频文案 |

## 实验数据与调研报告

| 文件 | 内容 |
|:-----|:------|
| `实验报告/` | 320 次批量验证（8 组 × 40 次）全部数据 |
| `分析报告/01-工具调用reasoning语言漂移溯源.md` | **数据库溯源：工具调用后 reasoning 从中文切英文的根因分析** |
| `分析报告/02-繁体字泄漏分析.md` | **额外发现：训练数据导致的简体→繁体字符泄漏** |

## 关键结论

1. **Pro + high + 中文 system prompt = 100% 中文 reasoning**（纯文本场景，320 次验证）
2. **关闭思考模式 + temperature=0 = 确定性输出**（40/40 全一致，0 reasoning token，1.1 秒/轮）
3. **reasoning 语言 ≈ messages 中的语言占比 + system prompt 的初始偏向**（占比的控制力 > prompt）
4. **工具调用后 reasoning 漂移的真实链路**：英文代码注入 → 占比超阈值 → reasoning 切换 → API 强制保留 reasoning → 自锁不可逆

详细分析报告见 `分析报告/` 目录。欢迎复现验证。

## 技术栈

- Godot 4.6
- GDScript + HTTPClient（非阻塞 SSE 流式）
- DeepSeek V4 Flash / Pro

## 相关讨论

[DeepSeek-V3 Issue #1255](https://github.com/deepseek-ai/DeepSeek-V3/issues/1255) — 中文 vs 英文 reasoning 控制实验
