Quick question about "thinking mode" semantics that came up in our experiments.

We've been running controlled experiments comparing thinking:enabled vs thinking:disabled. Our current understanding is:

- **thinking:enabled** = model uses its own internal sampling defaults; temperature/top_p/penalty are silently ignored
- **thinking:disabled** = user controls all sampling parameters (temperature, top_p, etc.)

But the model **still reasons** in both modes — the only difference is whether `reasoning_content` is exposed and who controls the sampling strategy. "Thinking mode" as a name suggests it's about whether the model thinks, but our experiments suggest it's actually about **which sampling regime is active**.

Two questions:

1. Is this understanding correct? Is thinking:enabled/disabled essentially a **sampling control switch** rather than a "thinking on/off" switch?

2. If thinking:disabled + temperature=0 — is this truly greedy decoding, or is there still internal variance from the model side?

This distinction matters for experiment design. If thinking:disabled + temperature=0 gives deterministic output, it opens up a lot of possibilities for multi-turn architectures where we need stable intermediate results. But if there's still internal variance even with temperature=0 in thinking:disabled mode, we need to account for that.

Thanks for clarifying.
