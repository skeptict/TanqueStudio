# Connection Reliability — Specification

**Status:** approved design, ready for implementation
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
