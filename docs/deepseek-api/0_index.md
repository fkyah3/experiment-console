# DeepSeek API 文档

> 来源：https://api-docs.deepseek.com/zh-cn/（2026-05-06 抓取）
> 模型：deepseek-v4-flash / deepseek-v4-pro
> base_url (OpenAI)：`https://api.deepseek.com`
> base_url (Anthropic)：`https://api.deepseek.com/anthropic`

## 目录

| 文件 | 内容 |
|:-----|:------|
| `0_index.md` | 本文件——快速开始 + 目录 |
| `1_思考模式.md` | 思考模式开关、强度控制、多轮对话拼接规则 |
| `2_多轮对话.md` | 无状态 API 的多轮对话拼接方式 |
| `3_对话前缀续写(Beta).md` | 指定 assistant 前缀让模型补全 |
| `4_FIM补全(BETA).md` | Fill-In-the-Middle 补全 |
| `5_JSON_Output.md` | 强制模型输出 JSON |
| `6_工具调用.md` | Function Calling 定义与思考模式下的工具调用 |
| `7_错误码.md` | 全部错误码及处理方式 |
| `8_限速.md` | 速率限制、keep-alive、超时 |
| `9_FAQ.md` | 常见问题 |
| `10_模型与价格.md` | 模型参数、价格、计费规则 |

---

## 快速开始

DeepSeek API 使用与 OpenAI/Anthropic 兼容的 API 格式。

### 基本信息

| 参数 | 值 |
|:-----|:----|
| base_url (OpenAI) | `https://api.deepseek.com` |
| base_url (Anthropic) | `https://api.deepseek.com/anthropic` |
| 认证方式 | `Authorization: Bearer sk-...` |
| 端点 | `POST /chat/completions` |

### 可用模型

| 模型名 | 说明 | 弃用时间 |
|:-------|:-----|:---------|
| `deepseek-v4-flash` | 当前推荐，经济快捷 | — |
| `deepseek-v4-pro` | 当前推荐，性能最强 | — |
| `deepseek-chat` | 指向 deepseek-v4-flash 非思考模式 | **2026-07-24 弃用** |
| `deepseek-reasoner` | 指向 deepseek-v4-flash 思考模式 | **2026-07-24 弃用** |

### 调用示例（非流式）

```bash
curl https://api.deepseek.com/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${DEEPSEEK_API_KEY}" \
  -d '{
    "model": "deepseek-v4-pro",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Hello!"}
    ],
    "thinking": {"type": "enabled"},
    "reasoning_effort": "high",
    "stream": false
  }'
```

### 流式调用

设置 `stream: true`，服务端以 SSE 格式逐块返回：

```
data: {"choices":[{"index":0,"delta":{"content":"你好"},"finish_reason":null}]}

data: [DONE]
```

DeepSeek 特有：`delta.reasoning_content`（思考过程文本）

### 关键约束（移山项目）

1. `thinking` 参数需通过 `extra_body` 传入（OpenAI SDK 使用时）
2. 思考模式下不支持 `temperature`、`top_p`、`presence_penalty`、`frequency_penalty`
3. 无工具调用的轮次，`reasoning_content` 无需回传；有工具调用的轮次**必须**完整回传
4. 流式期间处理 `: keep-alive` 注释行（心跳保持）
