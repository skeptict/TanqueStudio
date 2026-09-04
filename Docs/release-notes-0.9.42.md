# Tanque Studio 0.9.42

A dependency bump that fixes newer Draw Things model families rendering as
noise, and a change to the built-in Krea 2 Turbo default so that LoRAs
actually take effect.

## LoRAs now work on the built-in default

If you added a LoRA to a Story Studio project built on the built-in "Krea 2
Turbo" default and it appeared to do nothing at all, this is why: the default
named `krea_2_turbo_i8x.ckpt`, and that quantization **silently ignores LoRAs**.
No error, no warning — the LoRA is simply dropped and you get the same image you
would have got without it.

This was confirmed with a controlled comparison: same seed, same prompt, same
server, LoRA on versus off. On `i8x` the two renders were identical. On
`krea_2_turbo_q6p.ckpt` the same LoRA applied plainly and obviously.

The built-in default is now `krea_2_turbo_q6p.ckpt`. Existing projects keep
whatever model they were saved with — if one of them is on `i8x` and you are
wondering why its LoRAs do nothing, switch it to another quantization.

**This is a property of the quantization, not of Tanque Studio.** Any `i*x`
Krea 2 Turbo file is likely to behave the same way; the other quantizations
have not all been individually tested.

## Newer model families no longer render as noise

The DT-gRPC-Swift-Client dependency is bumped from v1.6.14 to v1.6.16.

The Draw Things server needs a model's specification to resolve its version,
modifier, objective and latent space. For newer families it has no built-in
entry for — Flux.2 Klein, Krea 2 — it was falling back to Stable Diffusion v1
defaults, so those models came back as noise or failed outright. The client now
looks the model up in a bundled copy of Draw Things' `models.json` and falls
back to fetching the live list from `models.drawthings.ai` for anything newer
than that snapshot.

Verified on this release: Krea 2 Turbo and Flux.2 Klein 9B both render clean,
coherent images through the plain text-to-image path, where the relevant
failure mode would have been visible noise.

## Behind the scenes

- v1.6.16 also removes `serializeDefaults` from the FlatBuffer writer. Since
  v1.6.14 exists specifically to stop config fields explicitly set to `0` or
  `false` being dropped on the wire, that removal was checked rather than
  taken on trust: every scalar field's declared default in the client was
  diffed against Draw Things' own `config.fbs` schema, and all of them match.
  Fields omitted as defaults therefore round-trip to the same value on the
  server.
- v1.6.16 also sends LoRA specifications with each request. For a LoRA that
  Draw Things doesn't recognise, the client synthesises a specification using
  the *current model's* version. That is a guess, and for a LoRA genuinely
  trained against a different architecture it is the wrong guess — the server
  will load it rather than correctly skipping it. In practice such a LoRA has
  no visible effect either way. Not fixed here.
