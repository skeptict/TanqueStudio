# TanqueStudio — Reference Repositories

Before solving a UI or architecture problem from scratch, check here first.

## TanquePatterns
**Repo:** `/Users/skeptict/Documents/GitHub/TanquePatterns`
macOS SwiftUI app — more mature UI chrome than TanqueStudio. Use as reference implementation.

### Custom title bar (THE correct pattern)
File: `TanquePatterns/TitleBar.swift`
Clear traffic lights with a leading Spacer — NOT with .padding(.leading, N):
```swift
HStack(spacing: 8) {
    Spacer().frame(width: 60) // clears traffic lights
    appIcon
    wordmark
}
```
Bar at standard height (no frame height changes, no .padding(.top)).
WindowGroup: `.windowStyle(.hiddenTitleBar)` + `.ignoresSafeArea()` on ContentView.

### App icon
Use `NSImage(named: "AppIcon")` with RoundedRectangle fallback — more reliable than `NSApp.applicationIconImage`.

### DS tokens
TanquePatterns uses `TP.*` — TanqueStudio uses `TanqueDS.*`. Same concepts, different namespaces.

---

## DT-gRPC-Swift-Client
**Repo:** `https://github.com/euphoriacyberware-ai/DT-gRPC-Swift-Client`
gRPC client library for Draw Things. Check before modifying any connectivity code.
All transport is gRPC-only. Remote server: TLS enabled, response compression disabled.

---

## dtm
**Repo:** `https://github.com/kcjerrell/dtm`
DT project viewer — reference for metadata parsing and project file reading.

---

## AI session rules
- **Titlebar/top bar problem** → read `TanquePatterns/TitleBar.swift` first
- **gRPC problem** → check DT-gRPC-Swift-Client before auditing AppSettings
- **New DS tokens** → cross-reference TanquePatterns TP.* equivalents
