# API 端点与接入

> 来源：https://opencode.ai/docs/zh-cn/go/

---

## API 端点

所有 Go 模型通过统一的 API 端点访问：

| 端点类型 | URL | 说明 |
|:---------|:-----|:------|
| Chat Completions | `https://opencode.ai/zen/go/v1/chat/completions` | OpenAI 兼容格式 |
| Models 列表 | `https://opencode.ai/zen/go/v1/models` | 获取可用模型元数据 |

### 模型 ID 与对应端点

| 模型 | 模型 ID | 端点 | AI SDK 包 |
|:-----|:--------|:------|:----------|
| GLM-5.1 | glm-5.1 | `/v1/chat/completions` | `@ai-sdk/openai-compatible` |
| GLM-5 | glm-5 | `/v1/chat/completions` | `@ai-sdk/openai-compatible` |
| Kimi K2.5 | kimi-k2.5 | `/v1/chat/completions` | `@ai-sdk/openai-compatible` |
| Kimi K2.6 | kimi-k2.6 | `/v1/chat/completions` | `@ai-sdk/openai-compatible` |
| DeepSeek V4 Pro | deepseek-v4-pro | `/v1/chat/completions` | `@ai-sdk/openai-compatible` |
| DeepSeek V4 Flash | deepseek-v4-flash | `/v1/chat/completions` | `@ai-sdk/openai-compatible` |
| MiMo-V2.5 | mimo-v2.5 | `/v1/chat/completions` | `@ai-sdk/openai-compatible` |
| MiMo-V2.5-Pro | mimo-v2.5-pro | `/v1/chat/completions` | `@ai-sdk/openai-compatible` |
| MiniMax M2.7 | minimax-m2.7 | `/v1/messages` | `@ai-sdk/anthropic` |
| MiniMax M2.5 | minimax-m2.5 | `/v1/messages` | `@ai-sdk/anthropic` |
| Qwen3.6 Plus | qwen3.6-plus | `/v1/chat/completions` | `@ai-sdk/alibaba` |
| Qwen3.5 Plus | qwen3.5-plus | `/v1/chat/completions` | `@ai-sdk/alibaba` |

## OpenCode 配置中的模型引用

OpenCode 配置中的模型 ID 使用 `opencode-go/<model-id>` 格式：

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "model": "opencode-go/kimi-k2.6"
}
```

## 接入方式

### 方式一：TUI 交互式

1. 打开 OpenCode TUI
2. 运行 `/connect`，选择 `OpenCode Go`
3. 粘贴 API 密钥（从 [OpenCode Zen](https://opencode.ai/auth) 获取）
4. 运行 `/models` 选择模型

### 方式二：通过 API 直接调用

```bash
curl https://opencode.ai/zen/go/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-v4-flash",
    "messages": [{"role": "user", "content": "你好"}]
  }'
```

### 方式三：通过 OpenCode 配置文件

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "opencode-go": {
      "options": {
        "apiKey": "YOUR_API_KEY"
      }
    }
  },
  "model": "opencode-go/deepseek-v4-flash"
}
```

## 获取可用模型列表

```
GET https://opencode.ai/zen/go/v1/models
```

返回所有可用模型及其元数据。

## 使用限制

接入后默认受以下限制约束：
- **5 小时限制**：$12 使用额度
- **每周限制**：$30 使用额度
- **每月限制**：$60 使用额度

可在控制台中跟踪当前使用情况，并启用 **Use balance** 选项在超出限制后回退使用 Zen 余额。
