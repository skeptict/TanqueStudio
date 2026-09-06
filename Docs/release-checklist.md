# Release Checklist

The full process for cutting a public release. **Run every step, in order.**

A *test build* is a different, lighter flow: bump the 4th version component
(X.Y.Z → X.Y.Z.1), commit, clean Release build, zip to `Archives/`. No notarization, no
tag, no GitHub release.

---

## 0. Pre-flight

```bash
git status --short                       # working tree clean
git rev-parse --abbrev-ref HEAD          # expect main
git log --oneline origin/main..main      # know what's shipping
```

Merge feature branches with `--no-ff` **before** bumping, so the bump commit is the tag
target.

## 1. Verify — before bumping, not after

A failing test after the bump leaves a commit to unwind.

```bash
xcodebuild -project TanqueStudio.xcodeproj -scheme TanqueStudio \
           -configuration Debug -derivedDataPath .build build
```

```bash
xcodebuild test -project TanqueStudio.xcodeproj -scheme TanqueStudio \
                -only-testing:TanqueStudioTests -derivedDataPath .build
```

The StoryFlow round-trip harness used to be a separate hand-run `swiftc` invocation; as of
2026-07-26 it lives in `TanqueStudioTests` (`StoryFlowPipelineExportTests`) and runs with the
command above, so there is no extra step.

Both must be green. `testExportMatchesTheAuthorsOwnExport` diffs our pipeline export against the
StoryFlow author's own reference export — if it fails, an instruction has drifted from the
reference and the release should stop.

> **Scheme gotcha**: `xcshareddata` is gitignored, so on a fresh clone `TanqueStudioTests`
> is not in the shared scheme and `-only-testing:` fails with *"isn't a member of the
> specified test plan or scheme."* Add the `TestableReference` in Xcode first.

## 2. Bump the version

Both keys appear **six times each** in `TanqueStudio.xcodeproj/project.pbxproj`:

```bash
sed -i '' 's/MARKETING_VERSION = OLD;/MARKETING_VERSION = NEW;/g; s/CURRENT_PROJECT_VERSION = OLD;/CURRENT_PROJECT_VERSION = NEW;/g' TanqueStudio.xcodeproj/project.pbxproj
```

Confirm the replacement took, rather than assuming `sed` matched. **Use `-F`** — see below:

```bash
grep -cF "MARKETING_VERSION = NEW;" TanqueStudio.xcodeproj/project.pbxproj        # expect 6
grep -cF "CURRENT_PROJECT_VERSION = NEW;" TanqueStudio.xcodeproj/project.pbxproj  # expect 6
grep -cF "MARKETING_VERSION = OLD;" TanqueStudio.xcodeproj/project.pbxproj        # expect 0
grep -cF "CURRENT_PROJECT_VERSION = OLD;" TanqueStudio.xcodeproj/project.pbxproj  # expect 0
```

> **Why `-F`, and why not bare `grep -c "OLD"`.** Without `-F`, grep reads the pattern as a
> regular expression, where `.` matches *any* character — so `0.9.42` means "zero, anything,
> nine, anything, four, two", not the literal version string. The pinned DT-gRPC-Swift-Client
> revision in this very file is `2e44f4f99e742709eb90cfd96ff3fe10198421c1`, which contains
> `019842` and matches. Releasing 0.9.43 that check reported `1` where the checklist says
> "expect 0" — a phantom stale version, in a file where nothing was stale. `-F` treats the
> pattern as literal text and answers `0` correctly.
>
> Searching for the full `KEY = OLD;` rather than the bare version is the second half of the
> fix: it cannot collide with a hash, a date, or a dependency version even by accident.

Rebuild, then commit as `chore: bump to X.Y.Z (build N)`.

## 3. Notarize

```bash
bash Scripts/notarize.sh X.Y.Z
```

Requires the `Developer ID Application` certificate and the `TanqueStudio-Notarization`
keychain profile. One-time setup is in the script's header comment.

> **Never pipe this to `tail` or `head`.** A pipeline's exit status is the *last* command's,
> so `notarize.sh … | tail -40` reports success even when the script fails — and the
> truncation hides the error that would have told you. Let it print in full, or redirect to
> a file.

## 4. Verify the artifacts — not the exit code

```bash
ls -lh Archives/TanqueStudio-X.Y.Z.zip
xcrun stapler validate "/tmp/TanqueStudioExport/Tanque Studio.app"
spctl -a -vvv -t install "/tmp/TanqueStudioExport/Tanque Studio.app"
defaults read "/tmp/TanqueStudioExport/Tanque Studio.app/Contents/Info.plist" CFBundleShortVersionString
```

Expect the zip to exist (~13M), `The validate action worked!`, `source=Notarized Developer
ID`, and the version you just bumped to. **A clean exit code is not evidence that any of
this happened.**

## 5. Tag and push

```bash
git tag -a vX.Y.Z -m "vX.Y.Z — <one-line summary>"
git push origin main
git push origin vX.Y.Z
```

## 6. Publish

Notes live in the repo at `Docs/release-notes-X.Y.Z.md` and are drafted as the work lands,
not written from the git log on release day. **Check whether one already exists before
writing a new one** — a draft is where a previous release's owed follow-up gets parked, and
the whole point is that it survives the session that noticed it.

```bash
gh release create vX.Y.Z --title "…" --notes-file Docs/release-notes-X.Y.Z.md --target main Archives/TanqueStudio-X.Y.Z.zip
```

Then confirm it actually landed as Latest — `gh release view` does not report this, so
query the API:

```bash
gh api repos/skeptict/TanqueStudio/releases/latest --jq '.tag_name'
```

---

## Release-note honesty

State plainly what is verified and what isn't. **Do not claim a fix that hasn't been
confirmed on the hardware it targets.** Shipping an unverified fix is fine when it's labelled
as one and users are told how to report back; claiming it works is not.

Two rules that follow from the same principle:

- **Never record a machine-specific fix as "fixed" until that machine confirms it.** Write
  "shipped, awaiting verification." In 0.9.28 a fix for an Intel-only hang was written up as
  confirmed before any Intel machine had run it — it then failed, and the write-up had
  already told the next investigator not to re-propose the hypothesis that turned out to be
  correct.
- **A measurement taken where a bug doesn't reproduce is not evidence about where it does.**
  For anything specific to a machine, OS, or display, benchmark on the affected
  configuration or record the hypothesis as untested.
