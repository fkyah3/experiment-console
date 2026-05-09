Update on the root cause analysis — we traced the pollution path through actual database records (opencode sessions, Flash model).

**We analyzed two real sessions with complete message chains — including tool calls, tool results, and every reasoning block.** Here's what we found.

## The pollution chain (confirmed)

```
Tool reads English code file
  → Large volume of English content injected into message history
  → English token ratio in context crosses a threshold
  → Next turn's reasoning_content switches to English
  → English reasoning is forcibly carried into subsequent requests (API requirement)
  → English reasoning self-reinforces — 99.4% stays English, almost irreversible
```

The trigger point is precise: in one session, 10 consecutive Chinese reasoning blocks were stable while reading Chinese documents. The moment it read a TypeScript source file, the next reasoning flipped to English. Not gradual — instantaneous.

## What's NOT the cause

- **System prompt was NOT lost.** Content output remained Chinese throughout all sessions. The system prompt controls content strongly but reasoning weakly.
- **The `tool_calls` field structure** (parameter names in English) is a minor contributor but not the trigger.

## The formula

```
reasoning language ≈ token ratio in messages + system prompt's initial bias
```

Token ratio is the dominant variable. System prompt sets the starting point, but every tool call injects new tokens that shift the ratio. When English tokens dominate enough, reasoning switches — and once switched, the API's requirement to carry reasoning_content forward locks it in.

## Two distinct degradation modes

| Type | Symptom | Trigger | Severity |
|------|---------|---------|----------|
| **Language switch** (zh→en reasoning) | Tool returning English content | P0 — irreversible in session |
| **Character leak** (simplified→traditional text) | Training data distribution | P3 — self-correcting, rare |

## What this means

The root cause is not in the model's behavior or the system prompt. It's in **how we assemble messages between turns.** Specifically: English tool results go directly into the message array that gets sent back to the API. If we filter what enters that array (keeping full results in storage but only injecting key conclusions in Chinese), the ratio stays favorable.

This is the design direction we're taking in our project: separate "retain everything" (原文层) from "what goes into the next request" (context layer). The full results are never lost, but they don't directly pollute the reasoning language.

No database dumps attached for privacy reasons, but the analysis methodology is fully reproducible: search your session data for the first point where `reasoning_content` switches language, then examine the tool calls immediately preceding that point.
