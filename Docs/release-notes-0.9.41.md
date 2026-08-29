# Tanque Studio 0.9.41

A crash fix in Render Queue, a new way to seed prompts, and a bundle of smaller
fixes to the Generate page's Assist tools.

## Render Queue could crash Draw Things

The built-in "Krea 2 Turbo" default named the wrong file — `krea_2_turbo_q8p.ckpt`
instead of `krea_2_turbo_i8x.ckpt`. Krea 2 Turbo ships in several quantizations
that are genuinely different files, not interchangeable labels, and not every
one is available through Draw Things+ cloud. Requesting the one that wasn't
actually reachable on the server made Draw Things either return zero images or
crash outright, depending on how it failed to resolve the model. The crash
message pointed at text encoding and the empty-image message pointed at
Draw Things+ sign-in — neither of which was the real cause.

If you built a Story Studio project or Render Queue setup on the old default
and never changed the model, this is worth a fresh look: it should render now
where it previously failed or brought down the Draw Things server.

## Generate Ideas in Render Queue

The Prompt axis in Labs → Render Queue has a new wand button: give it a style
persona and a topic, and it asks your configured local LLM (Ollama, LM Studio,
or Jan) for a batch of prompt variants, then drops them straight into the
axis. It reuses the same LLM connection Assist and Story Studio's enhance menu
already use — nothing new to configure.

## Assist tools

- **Describe Image → Prompt**: a new Assist operation that sends the canvas
  (or the img2img source, or the moodboard) to a vision-capable local LLM and
  turns what it sees into a prompt.
- **Copy Config for DT** now says which config it copied. Dropping or
  selecting an imported image could leave the left panel and the image's own
  metadata disagreeing with no visual cue, so "Copy Config for DT" would
  silently export whichever one you didn't mean. It now flags the divergence
  and offers to copy the image's own config instead.
- Two metadata-import gaps are fixed: `num_frames`/`fps` are read from
  Draw Things PNGs now (previously reset to the model default on import), and
  `cfgZeroStar`/`resolutionDependentShift` are read from Draw Things' own `v2`
  block, not only Tanque Studio's.

## Behind the scenes

- The DT-gRPC-Swift-Client dependency is bumped to v1.6.14, fixing a real bug
  where any config field explicitly set to `0` or `false` was silently
  dropped from the wire and the server substituted its own default —
  meaning the same seed and config as the Draw Things app could still render
  differently.
- The unreachable classic Generate layout is removed. Its live code (the
  Assist tab, the canvas edit layers) was extracted first and is unaffected.
