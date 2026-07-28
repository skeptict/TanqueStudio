# Connection Reliability — Specification

**Status:** §2a–2e shipped in v0.9.29. §2f added 2026-07-27 and shipped in v0.9.32.
**Decided:** 2026-07-05 (Ned) — fix the wedged-connection bug cluster found during v0.9.23 testing. Queued right after Learnability Phase 1 (merged `d6b7676`).

## 1. Problem (confirmed by reading code, not speculation — 2026-07-05 live triage)

TanqueStudio's connection state can get **permanently wedged** with no in-app recovery except quitting and relaunching. Three compounding bugs, verified against the actual server (`192.168.1.34:7859`, secret `CD54PV9V3YMR` — confirmed healthy, 127 files, at time of incident, so this is a client-side bug, not a server/secret problem):

1. **No timeout anywhere in `DrawThingsGRPCClient`** (`fetchModels`, `fetchLoRAs`, `echo` — grepped, zero hits for "timeout"/"deadline"). A stalled gRPC call awaits forever.
2. **`GenerateViewModel.loadAssets()`** (`GenerateViewModel.swift:1012`) sets `isLoadingAssets = true` before its `Task`, resets it only at the end. If the fetch inside hangs, `isLoadingAssets` never resets, so the reentry guard `guard !isLoadingAssets else { return }` permanently no-ops every future call — **including the manual refresh (⟳) button** next to Model in Generate. Only a full relaunch clears it (fresh process, no stuck Task).
3. **`SettingsView.testConnection()`** (`SettingsView.swift:362-375`) builds `DrawThingsGRPCClient(host:port:)` **without `sharedSecret:` at all**, then calls `checkConnection()`, which just checks whether `echo()` threw. DT's `echo()` succeeds (empty file list, `sharedSecretMissing: true`) even with a missing/wrong secret — so Test Connection reports false-positive "success" almost regardless of whether the real configured secret is correct. It's also entirely disconnected from `GenerateViewModel.models`: even its `.tanqueDTConnectionVerified` notification only re-triggers `loadAssets()`, which is still wedged by #2.

Net effect observed: "disconnected" badge (`ContentView.swift:126`, cosmetic `!vm.models.isEmpty`) stuck forever, refresh icon inert, Settings' Test Connection powerless to help.

## 2. Scope

### 2a. Timeout + cancellation on the gRPC asset calls

- Add a reasonable timeout (10–15s) to `fetchModels()` / `fetchLoRAs()` in `DrawThingsGRPCClient.swift` — wrap with `withThrowingTaskGroup` racing the real call against a `Task.sleep` timeout, or use the underlying gRPC call's deadline option if `DrawThingsService`/`DrawThingsClient` expose one (check `DT-gRPC-Swift-Client` — `CallOptions` may already support a timeout; prefer that over a manual race if available).
- On timeout, throw a distinct error (don't just return empty) so callers can tell "timed out" from "genuinely empty."

### 2b. Make `loadAssets()` resilient

- `GenerateViewModel.loadAssets()`: ensure `isLoadingAssets` resets in all paths, including timeout/cancellation — use `defer { isLoadingAssets = false }` inside the `Task` rather than only at the end of the happy path.
- Add real force-refresh semantics: track the in-flight `Task` and cancel it before starting a new one, instead of the current no-op reentry guard. A user hitting refresh should always be able to try again, even if the previous attempt is stuck.
- Surface the timeout distinctly: if the fetch times out, set `errorMessage`/`transientWarning` with a clear "Draw Things didn't respond in time — check the connection" message rather than silently leaving `models` empty.

### 2c. Fix `SettingsView.testConnection()`

- Pass the actual configured secret: `DrawThingsGRPCClient(host: host, port: port, sharedSecret: settings.dtSharedSecretOrNil)`.
- `checkConnection()`'s success criterion should reflect whether the *authenticated* echo succeeded (has files or explicitly `sharedSecretMissing == false`), not just "didn't throw." Consider surfacing `sharedSecretMissing` distinctly in the UI ("connected, but secret required" vs "connected").
- Apply the same 2a timeout here too — Test Connection can hang exactly like `loadAssets()` can.

### 2d. Real connection-health signal

- Replace or augment the cosmetic `ContentView.isConnected` (`!vm.models.isEmpty`) with a signal that reflects an actual recent successful/failed check — e.g. `GenerateViewModel` tracks `lastConnectionCheck: Date?` / `lastConnectionSucceeded: Bool` updated by both `loadAssets()` and the `.tanqueDTConnectionVerified` notification path, and the badge reads that instead of inferring from `models.isEmpty` (which conflates "empty inventory" with "not connected" — a server can be reachable and correctly report zero LoRAs, for instance).

### 2e. Error-message wording (smaller, related item)

- "Draw Things returned no image" (`GenerateViewModel.swift:444,820`) presumes local-only rendering ("the model isn't downloaded in Draw Things") — doesn't account for DT+ cloud bridge users, where no local download is needed. TS cannot distinguish not-local / not-bridged / bad-sampler / bad-secret from DT's response (no error code differentiates them) — but the wording should stop presuming local-only, and should branch on known state: if `models` is empty/stale (per 2d's real signal) at generate time, lead with "you may not be connected — check Settings" instead of guessing three causes blind.

### 2f. Timeout on the render RPC itself (added 2026-07-27)

**Why this is a late addition, and the lesson in it.** §1's bug list named `fetchModels`, `fetchLoRAs`, and `echo` — the three calls the 2026-07-05 triage grepped for. `generateImage` was not on that list and so §2a never covered it, which left the app in the odd state of bounding every *cheap* call while the *expensive* one, the only call that can legitimately run for hours, stayed unbounded. The grep was accurate; the inventory it produced was read as complete when it was only complete for the calls that had misbehaved that day.

Found during the v0.9.31 release run: `StoryFlowLiveRunTests.testTheStoredConfigDescribesTheImageItCameWith` timed out at 300s against `192.168.1.34`. The request was well-formed (640×448, confirmed in `request_log.txt`); the identical request succeeded 3/3 against this Mac's own Draw Things and failed 3/3 against the remote in the same session; a 1024×1024 render with the same model and frame count succeeded on that same remote a minute later. So: not the model, not the config, not the frame count. The server accepted the connection, accepted the request, and never answered. Every caller — Generate, inpaint, and `StoryFlowEngine.executeGenerate` — awaited forever with nothing surfaced. Long-standing, unrelated to the four fixes in v0.9.31.

Note that `executeGenerate` already handles a genuine zero-image response correctly (`guard let img = images.first else { log("⚠ No image returned"); return }`). That path was never reached. The hang was purely the unbounded RPC.

- Same race-against-a-sleep as `performEcho`, for the same stated reason: the package builds its own `CallOptions` internally and exposes no deadline to callers.
- **Do not reuse `echoTimeout`.** 15s is right for a handshake and catastrophic for a render. The budget is derived per-request instead: `120s + (megapixels × steps × frames × batchSize × batchCount) × 8s`, doubled when hires fix is on, clamped to **[5 min, 6 h]**. The rate is deliberately far slower than real hardware — this is a watchdog, not an ETA, and the two failure modes are not symmetric: overshooting costs a longer wait before an error appears, undershooting kills a healthy render.
- Both render paths are covered — the high-level client (txt2img/img2img) and the low-level service (inpaint).
- Throws `DrawThingsError.generationTimedOut(seconds:)`, kept **distinct from `.timeout`**: the causes and the advice differ, and `loadAssets()` matches on `.timeout` specifically. Its message states how long we waited and that the render may still be running server-side, because callers surface `localizedDescription` verbatim.
- `CancellationError` and `DrawThingsError` now pass through `generateImage`'s catch untouched rather than being rewrapped as `.requestFailed(-1, …)`. The sleep child makes cancellation surface from inside the call where it previously could not, and rewrapping would route a deliberate Cancel into the red-error arm instead of `GenerateViewModel`'s quiet reset.
- Escape hatch: `tanqueStudio.dtGenerateTimeoutMinutes` (UserDefaults, minutes, ≤ 0 or absent = derive). **No UI** — deliberately, so the change had no visual surface to verify. Promoting it to a real setting is a follow-up, not a prerequisite.
- Cancelling client-side does **not** stop the server. Draw Things keeps rendering; the guarantee is only that we stop waiting.

**Verification (done, not planned):** the watchdog fires end-to-end against the real remote in 3.5s with a forced 3s budget; a healthy 512×512 render against the local server still returns an image; both new `request_log.txt` lines confirmed in the actual log. 16 unit tests pin the budget arithmetic (`GenerateTimeoutTests`) — the failure mode that matters is a budget too *short*, and no build or smoke test catches a healthy render killed mid-flight. Two further tests are `TS_LIVE_DT`-gated. The original hang itself was **not** reproduced: that remote answers normally now, so the live proof comes from the forced-short-budget test rather than from the original failure.

## 3. Out of scope

- Do not add retry-with-backoff loops — a single bounded timeout + a working manual refresh is sufficient; don't over-engineer.
- Do not touch the DT-gRPC-Swift-Client package itself unless the deadline/timeout mechanism genuinely isn't exposed at the call-option level (check first — this may need zero upstream changes).
- No SwiftData schema changes. No StoryStudio*/StoryFlow* edits.

## 4. Verification (exit criteria)

- Build green + launch smoke test green.
- Reproduce the original bug class if possible: simulate a hang (e.g., point at an unreachable IP briefly, or a firewall-blocked port) and confirm (a) the call times out within the configured window instead of hanging forever, (b) `isLoadingAssets` resets, (c) the manual refresh button works immediately after, (d) Settings' Test Connection also times out cleanly rather than hanging.
- Live against the real DT server (`192.168.1.34:7859`, secret in Settings): Test Connection now reports success/failure based on the actual authenticated echo, not just RPC-didn't-throw. Try Test Connection with a deliberately wrong secret — should report failure (or "secret required"), not false-positive success.
- Existing stills/generate flow regression-checked — no behavior change for the healthy-connection path.

## 5. Hard rules

Same base rules as `Docs/story-studio-v2-spec.md` §8 (no pbxproj edits, additive-only on ported files — `DrawThingsGRPCClient.swift` is not a "ported, do-not-modify" file per the README's list, so normal edits are fine; `tanqueStudio.*` settings keys; conventional commits). No SwiftData schema changes.
