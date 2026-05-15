# 社区验证：`<thinking>` 标签触发随机内容

> 2026-05-16
> 来源：DeepSeek-V3 Issue #1314
> 复现：100 次批量实验

---

## 现象

只输入 `<thinking>`（无其它用户内容），模型生成与输入无关的回答——物理题、PHP 教程、地理知识、角色扮演等，内容呈随机分布。

## 复现数据

100 次 batch，model=deepseek-v4-flash，effort=high。

| 指标 | 数据 |
|:-----|:------|
| 中文 reasoning | 99/100 (99%) |
| 英文 reasoning | 1/100 (1%) |
| 工具调用 | 0 轮 |
| avg reasoning tokens | 163.3 |
| avg duration | 1.2s |

所有 output 内容均来自训练数据分布，未发现特定用户数据泄露。

## 结论

1. **这不是安全漏洞**——内容来自训练数据分布，非特定用户数据
2. **这不是 bug**——模型行为符合训练时的模式匹配
3. **这是 chat template 泄漏**——`<thinking>` 作为特殊 token，触发了训练数据中的完整模式接续

`<thinking>` 在训练数据中永远跟在"问题→回答"模式之后。模型看到这个 token 时不是在回复用户，而是在接续训练时见过的某个路径。这条路径的具体内容（物理题 vs PHP 教程）由 temperature=1 下的概率采样决定。

## 与 #1255 的关系

验证了 chat template + temperature=1 下的正反馈机制：
- 模型对输入格式的敏感度高于多数人的认知
- 特殊 token 能触发训练数据中的完整模式
- temperature=1 下这种"模式滑入"无法被内部打断

## 关键的悖论澄清

**问题：** 实验设置 temperature=0.0，为何输出随机？

**答案：** DeepSeek API 官方文档明确声明 thinking 模式下 temperature 参数**无效**，实际采样温度固定为 1.0。不是引擎用了 0.0 还随机，是 API 忽略了这个设置。

**No seed 参数：** DeepSeek API 不支持 `seed` 参数，无法请求确定性输出。

详见 [实验设计方案](../doc/移山/层工作区/V2阶段/调研层/产物/实验设计方案-thinking标签系统性验证.md)

## 实验数据

`实验报告/batch_20260516_0641_思考2/_summary.md`

## 待补实验

见 [实验设计方案](file:///E:/agent/MountainShift/doc/移山/层工作区/V2阶段/调研层/产物/实验设计方案-thinking标签系统性验证.md)
- P0：特殊 token 比对组（</thinking>、</s>、空输入）
- P1：无思考模式对照、正常用户场景模拟
