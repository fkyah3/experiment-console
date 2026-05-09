Quick update after fixing the bug.

I re-ran experiments with thinking:disabled + temperature=0, and the results are clean enough to share.

**Setup:** Same system prompt (Chinese anchoring), same question ("my cousin calls my grandmother what" — a question deliberately missing a precondition), 40 runs, thinking:disabled, temperature=0.

**Results:**

| metric | value |
|--------|-------|
| reasoning tokens | 0 across all 40 runs |
| avg response time | 1.1 seconds |
| correct identification of missing precondition | 40/40 |
| output variation | **none** — same wording across all runs |

The model correctly identified the missing precondition ("cousin on father's or mother's side?") every time, with zero reasoning tokens and near-identical output.

**What this tells us:**

1. **thinking:disabled + temperature=0 produces deterministic output.** 40 identical responses out of 40 runs. The internal variance we suspected is essentially zero in this mode.

2. **The model still reasons, but it's a different kind of reasoning.** With thinking:disabled, there's no reasoning_content, no costly chain-of-thought — but the model still correctly analyzes the question and identifies the gap. It just does it without the expensive internal monologue. This is consistent with my earlier guess: thinking mode is not a "thinking on/off" switch, it's a "internal sampling strategy" switch.

3. **For well-defined tasks with clear prompts, thinking:disabled is faster and equally capable.** 1.1 seconds vs 10-30 seconds with thinking:enabled, fewer tokens, same result quality for this class of task.

This doesn't mean thinking:disabled is always better — complex reasoning tasks still benefit from the thinking mode's internal exploration. But it does mean the API can produce fast, deterministic outputs when you need them, and the official website is likely using this mode for its instant responses.
