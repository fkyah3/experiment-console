Update on this — I've shipped the tool.

**What changed since my last post here:**

I realized I couldn't isolate variables inside opencode or any existing client. Too many layers — automatic message assembly, reasoning replay, tool execution wrappers. Every guess about what affects thinking language was just a guess.

So I built a tool that strips all of that away.

**Experiment Console** — a Godot 4.6 project where messages are bricks, not conversations:

- Each system/user/assistant/tool message is an independent block you add, remove, edit, or reorder manually
- reasoning_content and content display in separate, color-coded areas — you see exactly what the API returned
- thinking mode toggle, effort level, model selection — all exposed as simple UI controls
- Every request body and response body (including full usage with reasoning_tokens) is saved as a .md file
- No automatic message assembly. No hidden system prompt injection. No magic.

**Why this matters for this thread:**

The community has been asking "why does reasoning_content ignore system prompts and stay in English?" ([#1240](https://github.com/deepseek-ai/DeepSeek-V3/issues/1240), [#1257](https://github.com/deepseek-ai/DeepSeek-V3/issues/1257)). But the real question is harder to isolate inside any existing client — because you can't tell whether it's the model, the SDK, or the client framework causing the drift.

With Experiment Console, you can:

1. Manually construct a message sequence — add a user message, add a tool result with English error output, observe the next assistant's reasoning language
2. Toggle reasoning_content replay on/off for each round and see the difference
3. See the raw request body sent to the API — confirm your system prompt actually arrived
4. Compare "thinking on" vs "thinking off" for the same message sequence

The first experiment report is in the repo: English prompt + Chinese anchoring instruction. The results are mixed — which is exactly why we need more people testing with the same tool, under the same conditions.

**What I found so far (still early):**

- "Think in Chinese" as a system prompt works for content output — stable across long sessions
- But reasoning_content language shifts are real, and the trigger points are inconsistent
- Tool call error responses in English do appear to shift subsequent reasoning into English — consistent with my earlier suspicion
- I still cannot confirm whether this is the model ignoring the prompt or the API layer dropping the prompt somewhere in the chain — because I don't have a way to instrument the API side

**The tool is open source:**

GitHub: https://github.com/fkyah3/experiment-console
Windows build: https://github.com/fkyah3/experiment-console/releases/tag/v1.0.0

Set API Key → build your messages → send → observe raw reasoning_content.

I'm one person. If you have this issue, clone it, run your own tests, and share what you find. The experiment reports are in the repo too.

@qingkong66 — you asked me to shift focus from output text to thinking block. This tool is built for exactly that. It doesn't have answers yet, but it has no black boxes.
