Update: 320 controlled experiments with the tool I built.

**Experiment Console** — a Godot 4.6 project where messages are independent blocks, not auto-assembled chat. No hidden prompt injection, no automatic message assembly, no magic. Just raw API calls with full request/response logging.

Repository: https://github.com/fkyah3/experiment-console
Windows build: https://github.com/fkyah3/experiment-console/releases/tag/v1.0.0

## Experiment Design

8 groups × 40 calls = **320 total API calls**, all with the same system prompt:

```
你的 reasoning 和 content 都必须使用中文
代码、路径、工具名、文件名、错误信息不翻译
```

Variables controlled:

| Group | Model | Question Language | Effort |
|-------|-------|------------------|--------|
| 01 | Flash | Chinese | high |
| 02 | Flash | Chinese | max |
| 03 | Flash | **English** | high |
| 04 | Flash | **English** | max |
| 05 | Pro | Chinese | high |
| 06 | Pro | Chinese | max |
| 07 | Pro | **English** | high |
| 08 | Pro | **English** | max |

Prompt tokens identical across all groups (~30). Temperature=0 (though thinking mode ignores it). Each call is independent — no multi-turn accumulation.

## Results

### Chinese reasoning rate

| Group | Model | Question | Effort | Chinese reasoning |
|-------|-------|----------|--------|-----------------:|
| 01 | Flash | Chinese | high | 100% |
| 02 | Flash | Chinese | max | 100% |
| 03 | Flash | **English** | high | **95%** |
| 04 | Flash | **English** | max | **97.5%** |
| 05 | Pro | Chinese | high | 100% |
| 06 | Pro | Chinese | max | 100% |
| 07 | Pro | **English** | high | **100%** |
| 08 | Pro | **English** | max | **97.5%** |

### Reasoning token efficiency

| Group | Model | Question | Effort | avg reasoning tokens | median |
|-------|-------|----------|--------|-------------------:|-------:|
| 01 | Flash | Chinese | high | 52.0 | 42.0 |
| 02 | Flash | Chinese | max | 47.9 | 44.5 |
| 03 | Flash | English | high | 104.5 | 91.5 |
| 04 | Flash | English | max | 127.9 | **69.0** |
| 05 | Pro | Chinese | high | 52.1 | 36.5 |
| 06 | Pro | Chinese | max | 56.0 | 48.5 |
| 07 | Pro | English | high | 104.1 | 65.0 |
| 08 | Pro | English | max | 153.2 | **91.0** |

## Key Findings

### 1. Pro + high + Chinese system prompt = 100% stable

Pro with `high` effort achieves **100% Chinese reasoning** even under English input. No drift, no jitter. This is the most reliable configuration.

The same prompt on Flash has ~95-97.5% Chinese reasoning under English input — a small but measurable difference.

### 2. Chinese questions save ~50% reasoning tokens

Every comparison pair shows the same pattern:

- Chinese question → ~50 avg reasoning tokens
- English question → ~105 avg reasoning tokens

The additional tokens go into one thing: the model spending reasoning cycles deciding "the user asked in English but I should answer in Chinese." This language-negotiation overhead is consistent and measurable.

### 3. effort=max amplifies variance on simple tasks

effort=max doesn't improve reasoning quality on a trivial question like "What is recursion?" — it amplifies the tail.

| Group | Condition | variance ratio | worst case |
|-------|-----------|---------------:|-----------:|
| 07 | Pro + English + **high** | 17.3x | 416 |
| 08 | Pro + English + **max** | **42.5x** | **765** |

The worst case (765 tokens on "What is recursion?") is the model overthinking — generating extensive meta-reasoning about language choice and response structure, not about the question itself.

### 4. The 5% jitter is random, not drift

The ~5% English reasoning on Flash is not gradual drift. The English occurrences appear in the middle of Chinese runs (e.g., sample #6 out of 40, then sample #14), surrounded by consistent Chinese reasoning. This is a model-internal behavior, not context accumulation.

### 5. reasoning language and output language are decoupled

320 samples confirm: reasoning=English + output=Chinese is the failure mode (content recovered, thinking didn't). But we also observed one case (0.3%) of reasoning=Chinese + output=English — confirming these are independent probability events.

## Practical Advice

- **For 100% Chinese reasoning**: use Pro + high effort + Chinese system prompt
- **Don't use max effort on simple tasks**: it triggers overthinking (40x+ variance)
- **effort=high is sufficient**: it doesn't reduce accuracy, it just stops the model from over-analyzing trivial questions
- **This is not a system prompt problem**: the ~5% jitter on Flash is model behavior, not prompt weakness. No amount of prompt engineering will fix it.

## Raw data

All 320 samples with per-call reasoning token, language, and content are in the repository under `experiment-console/实验报告/`.
