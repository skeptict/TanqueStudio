# Tanque Studio 0.9.53

**Splash, and smoother re-renders.** LLM Assist can now use **Splash** as its provider. Picking a
different provider no longer throws away the model you'd chosen. Generate's Model list keeps your
selected model pinned at the top. In the Style Browser, Re-render can now queue behind a running
batch and keeps the old image up until the new one is ready.

## LLM Assist: Splash

**Splash** (Inco AI's local inference engine, github.com/incoai/splash) is now in **Settings →
LLM Assist → Provider**, alongside Ollama, LM Studio and Jan. It works with Assist, Prompt
Composer and LLM operations, including describe-an-image if the model supports images.

- **Default address:** `http://127.0.0.1:8000`. A bare host such as `192.168.1.2` gets port 8000.
- **Needs an Apple M3 or newer on macOS 26.4 or later.** That requirement is Splash's own. On an
  M1 or M2 Mac you can still use a Splash running on another Mac.
- **On another Mac:** Splash only answers on its own machine by default. Turn on network access in
  Splash's settings (or start it with `--host 0.0.0.0`). If you also give it an API key, enter
  that key in the API key field.
- Thinking models work. Splash keeps the model's reasoning apart from its answer, and only the
  answer is shown.

**Verified in the app** against Splash serving Qwen3.6-35B-A3B on another Mac: Test Connection
listed the model, the Assist model menu showed it, and Enhance returned a clean result.

## LLM Assist: your model stays put

Switching provider used to replace your saved LLM model with the new server's first model, just
by opening Assist or Compose. Now your choice stays selected and is marked **(not on server)**,
with a note asking you to pick one of the server's models. Only an empty model name is filled in
automatically.

**Verified in the app:** switching Ollama → Splash → Ollama kept the chosen model.

## Generate: selected model pinned

Expand **Model** and the selected model now sits in a **SELECTED** row above the search field,
so you no longer scroll the list to find it. It stays while you filter. If a config names a
model Draw Things doesn't list, the row shows the filename with "Not in Draw Things' model list".

**Verified in the app:** the pinned row, and that it stays while you filter. **Not yet tried in
the app:** the captions for an empty model and for an unlisted model.

## Style Browser: Re-render

- **While a set is rendering**, Re-render in a style's detail view now adds it to the queue. It
  used to be greyed out. Click it again to take the style back out.
- **The old image stays up** while a style is waiting or re-rendering, with a **Queued · 2nd**
  or **Rendering…** badge over it on the card and in the detail view.
- **A failed Re-render keeps the image it was replacing** and shows the error, instead of
  leaving the card empty.
- If Draw Things refuses the render (no model selected, or a video model), the reason now shows
  in the detail view, not only behind it.

**Verified in the app** against Draw Things with a test set: queuing a Re-render during a batch,
taking it back out, the Queued and Rendering… badges, and the new image replacing the old.
**Not yet tried in the app:** a Re-render that fails (covered by tests).

## Notes

Test suite: 594 passed, 8 skipped, 0 failures. New tests cover Splash's default port, the model menu keeping an unlisted
choice, a failed Re-render keeping its image, and a Re-render joining a running queue.
