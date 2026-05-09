One more question on the thinking mode behavior, this time about the difference between the official website and the API.

On the official DeepSeek website (chat.deepseek.com), there's a way to completely disable thinking — the model responds instantly, no hesitation. For a question like "what does my cousin call my grandmother," the website version quickly identifies the information gap ("cousin on father's or mother's side?") and asks for clarification. Clean, fast, no unnecessary reasoning.

But when we use the API with `thinking: disabled` and `temperature: 0`, the model **still appears to reason internally** — it hesitates, it generates unnecessary preamble text, it doesn't behave the same way as the website version with thinking turned off.

So the question is:

1. Is there an additional API parameter or setting that the official website uses to achieve this "truly no-thinking" behavior, which is not documented in the API reference?
2. Or does `thinking: disabled` on the API side actually mean something different from "thinking off" on the website side?
3. If the website uses the same API under the hood, is there some post-processing or prompt wrapping happening on the website's side that we're missing?

This matters a lot for our experiment design. If the API can truly disable the model's internal reasoning (like the website does), we need to know the right way to do it. If it can't, that's also important to know — it means the API and the website have fundamentally different behavior for the same parameter, and experiments done through the API won't reproduce website behavior.
