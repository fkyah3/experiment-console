# 分析报告：工具调用后 reasoning 语言漂移——污染源溯源

> 分析层 — 数据库专查
> 数据源：`分析/database/opencode.db`
> Session：`ses_217c49491ffeefayLmAfKQwzVt`（工程层背景阅读）
> Agent：Sisyphus - Ultraworker / Model：deepseek-v4-flash
> 分析日期：2026-05-07

---

## 一、对话链摘要

```
轮次数: 3948 messages / 18335 parts / 3103 条 reasoning
用户消息: 全程中文（例如"欢迎加入大家庭"、"我们现在分支master？"等）
Agent 模式: Sisyphus - Ultraworker（opencode 内置 agent）
```

---

## 二、污染事件精确定位

### 漂移点

| 项目 | 值 |
|:-----|:----|
| 发生位置 | 第 10 条 reasoning（共 3103 条） |
| 漂移前最后中文 reasoning | `prt_de83cfa5c001Ag6hvFlS7wPSDR` → `msg_de83cfa5c001Ag6hvFlS7wPSDR` |
| 漂移后第一条英文 reasoning | `prt_de83d117d001G3biw5KGT15jXd` → `msg_de83d117d001G3biw5KGT15jXd` |
| 漂移时间 | 1777717811042（Unix ms） |
| 漂移前 reasoning 语言 | zh（连续 10 条全中文） |
| 漂移后 reasoning 语言 | en（3085/3103 = 99.4% 英文） |
| 漂移前 content 语言 | zh |
| 漂移后 content 语言 | **zh（不变！）** |

### 漂移前后完整 part 序列

```
msg_de83cfa5c001Ag6hvFlS7wPSDR (assistant)   ← 最后中文 reasoning 所在 message
  ├── step-start   1777717805582
  ├── reasoning    1777717805583  ← 中文："好的，现在看到了关键信息：1. 当前分支是 `stable`..."
  ├── tool(read)   1777717808346  ← 读 provider.ts（TypeScript 代码）
  ├── tool(read)   1777717809018  ← 读 index.ts（TypeScript 代码）
  └── step-finish  1777717809515

msg_de83d117d001G3biw5KGT15jXd (assistant)   ← 第一条英文 reasoning 所在 message
  ├── step-start   1777717811041
  ├── reasoning    1777717811042  ← 英文："Now I have a good understanding of the codebase..."
  ├── text         1777717819627  ← 中文："让我进一步了解模型定义和 transform 相关代码。"
  └── tool(read)   1777717819958
```

### 全局统计

| reasoning 语言 | 数量 | 占比 |
|:--------------|:-----|:-----|
| 中文 | 18 | 0.58% |
| 英文 | 3085 | 99.42% |

漂移后仅出现 8 次零星中文 reasoning，均不持久，立即恢复英文。

---

## 三、逐假设排查

### 假设 1：工具返回内容本身是英文 — ✅ **强烈支持（主因）**

**证据链：**

| 阶段 | 读取内容 | 内容语言 | reasoning 语言 |
|:-----|:--------|:--------|:--------------|
| 早期 | 层评价/语言层评价.md、007~023 讨论文档、新建文本文档.txt、迁移通知书.md | **中文** | **中文** |
| 过渡 | opencode-yg 目录列表、packages 目录列表、package.json | 英文文件名 + JSON | **中文**（仍保持） |
| 触发 | provider.ts（TypeScript 源码）、index.ts（TypeScript 源码） | **纯英文代码** | **英文！（漂移）** |

**关键观察：**
- 读中文文档时，10 条连续 reasoning 全是中文
- 读英文目录名/JSON 时，reasoning 仍为中文
- 读**完整代码文件内容**后，下一个 reasoning 立刻变成英文
- 第一条英文 reasoning 的内容直接是对刚读的代码的分析："Now I have a good understanding of the codebase. Let me analyze what needs to change..."

**结论：** 工具的 output 中注入的大量英文代码内容是漂移的**直接触发器**。当上下文中英文代码内容占比超过某个阈值，模型在 reasoning 层切换到英文。

---

### 假设 2：tool_calls 字段结构污染 — ⚠️ **弱支持（辅助因素）**

**证据：**
- tool_calls 的字段名（`filePath`、`state.input`、`state.output`、`callID`）是英文
- 这些字段名作为上下文的一部分，增加了英文 token 占比
- 但第一条英文 reasoning 中未直接引用字段名——它是自然语言分析代码

**结论：** 不是主因，但作为上下文中的英文 token 来源之一，**辅助推动了漂移**。属于 Hypothesis 1 的子集。

---

### 假设 3：reasoning 强制保留 — ✅ **支持（自锁机制）**

**OpenCode 架构分析：**
- DeepSeek API 的 `reasoning_content` 在后续请求中作为 assistant message 的一部分被携带
- 一旦第一条英文 reasoning 产生，后续所有请求的上下文中都包含英文 reasoning
- 这形成了**自增强反馈循环**：英文 reasoning → 被携带到下一轮 → 模型看到英文 reasoning → 更倾向英文 → 产生更多英文 reasoning

**证据：**
- 漂移后 99.4% 的 reasoning 保持英文（3085/3103）
- 零星恢复中文后（仅 8 次），下一轮 reasoning 立刻回到英文
- 这是因为英文 reasoning 在上下文中占绝对优势

**结论：** 不是触发因素，但是**漂移不可逆的根本原因**。一旦被 Hypothesis 1 触发，Hypothesis 3 将漂移锁定。

---

### 假设 4：system prompt 丢失 — ❌ **不支持**

**证据：**
- 漂移后，text（输出给用户的 content）**始终保持中文**
- 例如第一条英文 reasoning 所属 message 的 text 输出是："让我进一步了解模型定义和 transform 相关代码。"
- 这说明 system prompt 中"用中文输出"的指令**仍然生效**
- 如果 system prompt 丢失，content 层也会切换到英文

**推理：**
- DeepSeek 的 system prompt 对 **content 层**有强约束力，对 **reasoning 层**约束力弱
- reasoning 层更容易被上下文中的语言分布影响
- system prompt 始终存在于每次 API 调用中

**结论：** system prompt 未丢失。问题不在于 prompt 丢失，而在于 **prompt 对 reasoning 层的控制力弱于对 content 层的控制力**。

---

## 四、综合判断

```
污染链路：
  ┌─────────────────────────────────────────────────────────┐
  │  工具读取代码文件                                        │
  │  ↓                                                      │
  │  大量英文代码注入上下文（假设 1 ★主因）                    │
  │  ↓                                                      │
  │  英文 token 占比超过阈值，reasoning 切换到英文             │
  │  ↓                                                      │
  │  reasoning_content 被携带到下一轮（假设 3 ★锁定）          │
  │  ↓                                                      │
  │  英文 reasoning 自增强，几乎不可逆                        │
  │  ↓                                                      │
  │  content 层仍受 system prompt 约束，保持中文               │
  └─────────────────────────────────────────────────────────┘
```

| 假设 | 判断 | 角色 |
|:-----|:-----|:-----|
| 假设 1 工具返回英文内容 | **强烈支持** | 🎯 直接触发器 |
| 假设 3 reasoning 强制保留 | **支持** | 🔒 自锁机制 |
| 假设 2 字段结构污染 | 弱支持 | 🔧 辅助因素 |
| 假设 4 system prompt 丢失 | 不支持 | — |

---

## 五、对移山项目的意义

### 确认的事实

1. **"工具调用后 reasoning 语言漂移"是真实存在的**，不是幻觉
2. 漂移的直接原因是工具返回的英文内容（代码文件）在上下文中占主导
3. 一旦漂移发生，reasoning 几乎不可逆（99.4% 不再恢复）
4. content 层不受影响——system prompt 仍有效

### 对移山方案的影响

当前移山的核心策略是"用 system prompt 锁定中文"。从本次分析看：

- **对 content 层有效**：system prompt 能确保输出中文
- **对 reasoning 层弱效**：一旦上下文英文占比过高，reasoning 仍会漂移
- **系统提示词不是万能的**：纯 prompt 方案无法阻止 reasoning 层漂移

### 建议

1. **在 system prompt 中加入 reasoning 层语言约束**（如"你的思考过程也请使用中文"）——但效果可能有限
2. **监控 reasoning 语言**：如果发现 reasoning 变成英文，说明上下文英文比例过高
3. **考虑在工具返回内容前做语言过滤**：但这会影响代码分析准确性
4. **优先读中文文档，延后读代码**：在需要中文 reasoning 的阶段，控制英文内容注入量
5. **需要更多样本**：建议查看其他 session（尤其是以中文文档分析为主的 session）验证此模式

---

## 附录：数据取证

### A. 数据库表结构

- `message`: 顶级消息，含 role/user|assistant、agent、model、tokens 等
- `part`: 消息片段，type ∈ {step-start, reasoning, tool, text, step-finish, patch}
- `session`: 会话元数据，title="工程层背景阅读"

### B. 关键 part ID 速查

| Part ID | Type | 语言 | 时间 |
|:--------|:-----|:-----|:-----|
| `prt_de83d020f001FyC1VvBMJs41WE` | reasoning | zh | 1777717805583 ← 最后一条中文 |
| `prt_de83d0cda001G6zablxqTLAlUa` | tool(read) | — | 1777717808346 ← 读 provider.ts |
| `prt_de83d0f79001C5A7J6ELkz27pi` | tool(read) | — | 1777717809018 ← 读 index.ts |
| `prt_de83d1762001wDKX1rPqvxty44` | reasoning | en | 1777717811042 ← 第一条英文 |
| `prt_de83d38eb002TM1UQ2RUfGAUVv` | text | zh | 1777717819627 ← 输出仍中文 |
