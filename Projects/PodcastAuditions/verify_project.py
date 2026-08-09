#!/usr/bin/env python3
"""Pre-flight the emitted Podcast Auditions project. Standard library only.

    python3 Projects/PodcastAuditions/verify_project.py
    python3 Projects/PodcastAuditions/verify_project.py --strict     # before a real run

Exit 0 clean, 1 on any FAIL. `--strict` additionally fails on the TODO_NED placeholders, which is
the gate to put between "the generator works" and "this is worth spending GPU time on".

WHAT THIS IS FOR
----------------
Every check here exists because its failure mode is SILENT. None of them raise in Draw Things.
They produce six finished, plausible-looking renders that are wrong:

  wildcard not in "loop" mode   → phase B pairs each character with somebody else's anchor
  unequal card counts           → same, by a different route: the lists fall out of lockstep
  zero quoted spans             → framesDialog counts no words, EVERY clip is exactly `padding`
                                  frames long, and the run looks completely normal
  padding not a multiple of 8   → numFrames is not 8k+1, which LTX will not accept cleanly
  an unparseable object value   → the pipeline's preflight refuses the entire run (this one is
                                  at least loud, but it is loud in Draw Things, not here)

The one thing this script cannot check is whether the prompt is any good.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_PROJECT = HERE / "Podcast Auditions.json"
DEFAULT_CONFIGS = HERE / "configs.json"

TANQUE_FRAME_CAP = 257

# ──────────────────────────────────────────────────────────────────────────────
# `allowedKeys`, transcribed verbatim from StoryflowPipeline.js:59-113 (the 260802 drop).
#
# Exactly 52 keys. validateInstructionArray refuses the WHOLE instruction array on an unknown key
# or a type mismatch, so an item type that is not in this table does not "mostly work" — the run
# never starts.
#
# Note what is NOT here: `frames8`. It exists in the Editor (ITEM_CONFIGS) as the 25fps duration
# readout, and the Editor rewrites it to `frames` on export (StoryflowEditor.html:2798). Emitting
# it verbatim would fail preflight. This table follows the source, not the Editor's item palette.
# ──────────────────────────────────────────────────────────────────────────────
ALLOWED_KEYS: dict[str, str] = {
    "note": "string", "prompt": "string", "config": "object", "size": "object",
    "frames": "number", "framesDialog": "object", "faceZoom": "flag", "askZoom": "string",
    "removeBkgd": "flag", "canvasClear": "flag", "canvasSave": "string", "canvasLoad": "string",
    "moveScale": "object", "adaptSize": "object", "crop": "flag", "moodboardClear": "flag",
    "moodboardCanvas": "flag", "moodboardLoad": "flag", "moodboardAdd": "string",
    "moodboardRemove": "number", "moodboardWeights": "object", "maskClear": "flag",
    "maskLoad": "string", "maskGet": "flag", "maskBkgd": "flag", "maskFG": "flag",
    "maskBody": "flag", "maskAsk": "string", "depthExtract": "flag", "depthCanvas": "flag",
    "depthToCanvas": "flag", "inpaintTools": "object", "xlMagic": "object", "negPrompt": "string",
    "poseExtract": "flag", "poseJSON": "object", "loop": "object", "loopLoad": "string",
    "loopAddMB": "string", "loopLoadMask": "string", "loopSave": "string", "loopEnd": "flag",
    "end": "flag", "concat": "string", "approve": "flag", "wildcard": "object", "sweep": "object",
    "interrogate": "string", "enhance": "string", "sizex2": "flag", "matte": "object",
    "hrf": "object",
}
assert len(ALLOWED_KEYS) == 52, f"transcription drift: {len(ALLOWED_KEYS)} keys, expected 52"

# Types whose project-format `value` is a JSON string that MUST parse as an object.
# `config` is exempt when it holds a `#shortcut` reference instead of inline JSON.
OBJECT_VALUED = {k for k, v in ALLOWED_KEYS.items() if v == "object"}

QUOTED_SPAN = re.compile(r'"([^"]+)"')


class Report:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.warnings: list[str] = []

    def fail(self, msg: str) -> None:
        self.failures.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    def check(self, ok: bool, msg: str) -> bool:
        if not ok:
            self.fail(msg)
        return ok


# ──────────────────────────────────────────────────────────────────────────────
# Structure
# ──────────────────────────────────────────────────────────────────────────────

def check_shape(project: dict, r: Report) -> None:
    for key in ("projectName", "items", "promptTriggers", "configShortcuts",
                "poseJSONShortcuts", "wildcardShortcuts"):
        if key not in project:
            r.fail(f"project is missing top-level key '{key}' (all four shortcut maps must be "
                   f"present even when empty)")
    if not isinstance(project.get("items"), list) or not project["items"]:
        r.fail("'items' must be a non-empty list")


def check_types_and_values(project: dict, r: Report) -> list[tuple[int, str, object]]:
    """Every type in allowedKeys; every object-valued item parses. Returns (index, type, parsed)."""
    parsed_objects: list[tuple[int, str, object]] = []
    for i, item in enumerate(project.get("items", [])):
        t = item.get("type")
        v = item.get("value")

        expected = ALLOWED_KEYS.get(t)
        if expected is None:
            r.fail(f"item {i}: type {t!r} is not one of the 52 allowedKeys — the pipeline "
                   f"refuses the entire instruction array on an unknown key")
            continue

        if expected == "flag" and v is not True:
            r.fail(f"item {i} ({t}): flag-typed value must be literal true, got {v!r}")
        if expected == "number" and not isinstance(v, (int, float)):
            r.fail(f"item {i} ({t}): must be a JSON number, got {type(v).__name__}")
        if expected == "string" and not isinstance(v, str):
            r.fail(f"item {i} ({t}): must be a JSON string, got {type(v).__name__}")

        if t in OBJECT_VALUED:
            if t == "config" and isinstance(v, str) and v.startswith("#"):
                continue  # shortcut reference, resolved at export
            if not isinstance(v, str):
                r.fail(f"item {i} ({t}): object-valued items are stored as JSON STRINGS in the "
                       f"project format, got {type(v).__name__}")
                continue
            try:
                obj = json.loads(v)
            except json.JSONDecodeError as e:
                r.fail(f"item {i} ({t}): value does not parse as JSON — {e}")
                continue
            if not isinstance(obj, (dict, list)):
                r.fail(f"item {i} ({t}): value parsed as {type(obj).__name__}, expected an object")
                continue
            parsed_objects.append((i, t, obj))
    return parsed_objects


def check_wildcards(parsed: list[tuple[int, str, object]], r: Report) -> None:
    """Every wildcard in `loop` mode, and every per-character card list the same length.

    `loop` is a pure function of the global counter; `once`, `shuffle` and `random` all carry
    state or entropy. Only `loop` makes phase B's duplicate of the IDENTITY list return the same
    card at the same counter that phase A's did.
    """
    counts: dict[int, list[int]] = {}
    saw_wildcard = False

    for i, t, obj in parsed:
        if t not in ("wildcard", "sweep"):
            continue
        if t == "wildcard":
            saw_wildcard = True
        mode = obj.get("wild")
        if mode != "loop":
            r.fail(f"item {i} ({t}): wild is {mode!r}, must be 'loop' — any other mode "
                   f"decorrelates the two phases and pairs characters with the wrong anchor")
        cards = obj.get("cards")
        if not isinstance(cards, list) or not cards:
            r.fail(f"item {i} ({t}): 'cards' must be a non-empty list")
            continue
        counts.setdefault(len(cards), []).append(i)

    if not saw_wildcard:
        r.fail("no wildcard items at all — this project is built on them")
    if len(counts) > 1:
        detail = "; ".join(f"{n} cards at items {items}" for n, items in sorted(counts.items()))
        r.fail(f"card counts are not all equal, so the lists fall out of lockstep — {detail}")


def check_loops(parsed: list[tuple[int, str, object]], card_count: int | None, r: Report) -> None:
    for i, t, obj in parsed:
        if t != "loop":
            continue
        if "start" not in obj:
            r.fail(f"item {i} (loop): 'start' is absent — loopSave computes "
                   f"_loopCounter + _startCount, so an undefined start writes anchor_NaN.png")
        elif obj["start"] != 0:
            r.fail(f"item {i} (loop): start is {obj['start']}, must be 0 — loopSave offsets by "
                   f"start and loopLoad does not, so a non-zero start makes the anchor pairing "
                   f"depend on the folder holding exactly these files")
        if card_count is not None and obj.get("loop") != card_count:
            r.fail(f"item {i} (loop): loop count {obj.get('loop')} does not match the "
                   f"{card_count}-card wildcards")


def check_padding(parsed: list[tuple[int, str, object]], r: Report) -> None:
    for i, t, obj in parsed:
        if t != "framesDialog":
            continue
        padding = obj.get("padding")
        if not isinstance(padding, int):
            r.fail(f"item {i} (framesDialog): padding must be an integer, got {padding!r}")
        elif padding % 8 != 0:
            r.fail(f"item {i} (framesDialog): padding {padding} is not a multiple of 8. "
                   f"framesDialog() returns 8k+1 and the executor adds padding raw, so "
                   f"{padding} gives numFrames ≡ {(1 + padding) % 8} (mod 8). "
                   f"The Editor's default of 49 is one of the bad ones; use 48.")


def check_config_shortcuts(project: dict, r: Report) -> None:
    shortcuts = project.get("configShortcuts", {})
    for i, item in enumerate(project.get("items", [])):
        if item.get("type") != "config":
            continue
        v = item.get("value", "")
        if isinstance(v, str) and v.startswith("#"):
            if v not in shortcuts:
                r.fail(f"item {i} (config): references {v!r}, which is not in configShortcuts")
            elif not shortcuts[v].strip():
                r.fail(f"item {i} (config): shortcut {v!r} is empty")
            else:
                try:
                    check_config_value_types(v, json.loads(shortcuts[v]), r)
                except json.JSONDecodeError as e:
                    r.fail(f"configShortcuts[{v!r}] does not parse as JSON — {e}")


# Strings that are really a number or a bool wearing quotes. `"2"` is valid JSON, exports
# cleanly, and is then assigned verbatim to a numeric config field.
QUOTED_SCALAR = re.compile(r"^\s*(-?\d+(\.\d+)?([eE][-+]?\d+)?|true|false|null)\s*$")


def check_config_value_types(name: str, config: dict, r: Report) -> None:
    """Catch a numeric or boolean config value that was typed with quotes around it.

    `config` is applied with Object.assign(configuration, value) (StoryflowPipeline.js:1002) and
    nothing coerces on the way in — unlike `sweep`, whose numeric-looking cards ARE coerced on
    export. So "seedMode": "2" hands Draw Things the string "2" for an integer enum. It parses,
    it exports, it validates, and then it either errors deep inside DT or is quietly ignored.

    Deliberately a shape rule rather than a per-key table: a value that looks like a number and
    is wrapped in quotes is wrong whatever the key is called, and this needs no maintenance when
    the config gains a field.
    """
    if not isinstance(config, dict):
        r.fail(f"configShortcuts[{name!r}] is not an object")
        return
    for key, value in config.items():
        if isinstance(value, str) and QUOTED_SCALAR.match(value):
            r.fail(f"configShortcuts[{name!r}].{key} is the STRING {value!r}, not the value "
                   f"{value.strip()}. Draw Things applies the config with Object.assign and "
                   f"coerces nothing, so a quoted number is handed over as text. Drop the quotes.")


# ──────────────────────────────────────────────────────────────────────────────
# Loop-block simulation — the part that catches the silent frame-count failure
# ──────────────────────────────────────────────────────────────────────────────

def loop_blocks(items: list[dict]) -> list[tuple[int, int, int]]:
    """(start_index, end_index, repeat_count) for each top-level loop..loopEnd pair.

    Sequential blocks are the design; nested ones are not possible in this format at all —
    the pipeline has a single _loopMarker, and `loop` only initialises when it is -1.
    """
    blocks, open_at = [], None
    for i, item in enumerate(items):
        if item["type"] == "loop":
            if open_at is None:
                try:
                    open_at = (i, json.loads(item["value"]).get("loop", 1))
                except (json.JSONDecodeError, TypeError):
                    open_at = (i, 1)
        elif item["type"] == "loopEnd" and open_at is not None:
            blocks.append((open_at[0], i, open_at[1]))
            open_at = None
    return blocks


def simulate(items: list[dict], start: int, end: int, counter: int) -> str:
    """Rebuild the accumulated `concat` for one pass of one loop block.

    Mirrors the executor: `concat` grows on concat/wildcard, and `prompt` fires the render and
    clears it (StoryflowPipeline.js:959-969). Card selection is originalCards[counter % len],
    which is exactly what `wild: "loop"` does.
    """
    concat = ""
    for item in items[start:end]:
        t, v = item["type"], item["value"]
        if t == "concat":
            concat += v
        elif t == "wildcard":
            cards = json.loads(v)["cards"]
            concat += cards[counter % len(cards)]
        elif t == "prompt":
            concat += v
            break  # render fires here; everything after is the next pass
    return concat


def js_word_count(concat: str) -> tuple[int, list[str]]:
    """framesDialog's word count: tokens inside "..." spans ONLY (StoryflowPipeline.js:449-471).

    Unquoted stage direction does not count toward the frame budget. That is the whole reason an
    auditions premise fits this format — the shot description can be as long as it needs to be.
    """
    spans = QUOTED_SPAN.findall(concat)
    return sum(len(s.strip().split()) for s in spans), spans


def frames_for(words: int, wps: float, padding: int) -> int:
    return math.ceil((words / wps) * 25 / 8) * 8 + 1 + padding


def check_dialogue_and_report(project: dict, r: Report) -> None:
    items = project["items"]
    blocks = loop_blocks(items)
    if not blocks:
        r.fail("no loop blocks found")
        return

    # Drift guard: phase A duplicates its card lists into phase B. If the two ever diverge,
    # every character gets somebody else's wardrobe. Emitting both from one bible makes this
    # impossible — this asserts the file on disk actually has that property.
    if len(blocks) == 2:
        def lists(b):
            return [json.loads(it["value"])["cards"]
                    for it in items[b[0]:b[1]] if it["type"] == "wildcard"]
        a_lists, b_lists = lists(blocks[0]), lists(blocks[1])
        if a_lists != b_lists[:len(a_lists)]:
            r.fail("phase A's card lists are not a prefix of phase B's — the duplicated IDENTITY "
                   "and WARDROBE lists have drifted apart")

    for bi, (start, end, repeats) in enumerate(blocks):
        fd_item = next((it for it in items[start:end] if it["type"] == "framesDialog"), None)
        if fd_item is None:
            continue
        fd = json.loads(fd_item["value"])
        wps, padding = fd.get("wps", 2.4), fd.get("padding", 49)

        print(f"\n  loop block {bi + 1}  (items {start}–{end}, {repeats} passes, "
              f"wps {wps}, padding {padding})")
        print(f"    {'#':>2}  {'words':>5}  {'frames':>6}  {'seconds':>7}   spans")

        for k in range(repeats):
            concat = simulate(items, start, end, k)
            words, spans = js_word_count(concat)
            if not spans:
                r.fail(f"pass {k}: the assembled prompt has ZERO quoted spans. framesDialog "
                       f"would count no words and this clip would render at exactly "
                       f"{padding} frames — the failure that looks like a working run.")
                continue
            frames = frames_for(words, wps, padding)
            note = ""
            if frames > TANQUE_FRAME_CAP:
                note = f"   ⚠ over Tanque Studio's {TANQUE_FRAME_CAP} cap"
                r.warn(f"pass {k}: {frames} frames exceeds Tanque Studio's {TANQUE_FRAME_CAP}-frame "
                       f"cap. StoryflowPipeline.js has no cap, so the two engines would silently "
                       f"render different lengths. Trim to 20 spoken words or fewer.")
            preview = " + ".join(f'"{s}"' for s in spans)
            if len(preview) > 58:
                preview = preview[:55] + "…"
            print(f"    {k:>2}  {words:>5}  {frames:>6}  {frames / 25:>6.1f}s   {preview}{note}")


def check_placeholders(project: dict, strict: bool, r: Report) -> None:
    blob = json.dumps(project, ensure_ascii=False)
    todo_ned = blob.count("TODO_NED")
    todo_bible = blob.count("TODO NED REPLACE ME") + blob.count("PLACEHOLDER")
    msg = []
    if todo_ned:
        msg.append(f"{todo_ned} TODO_NED value(s) from configs.json")
    if todo_bible:
        msg.append(f"{todo_bible} placeholder string(s) from bible.json")
    if msg:
        line = ("still placeholder: " + ", ".join(msg)
                + " — structurally valid, not yet worth rendering")
        (r.fail if strict else r.warn)(line)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("project", nargs="?", type=Path, default=DEFAULT_PROJECT)
    ap.add_argument("--strict", action="store_true",
                    help="also fail on remaining TODO_NED / bible placeholders")
    args = ap.parse_args()

    if not args.project.exists():
        sys.exit(f"{args.project} does not exist — run build_project.py first")

    r = Report()
    try:
        project = json.loads(args.project.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        sys.exit(f"{args.project} is not valid JSON — {e}")

    print(f"verifying {args.project.name}  ({project.get('projectName')!r}, "
          f"{len(project.get('items', []))} items)")

    check_shape(project, r)
    if r.failures:
        _emit(r)
        return 1

    parsed = check_types_and_values(project, r)
    check_wildcards(parsed, r)
    card_counts = {len(o["cards"]) for _, t, o in parsed
                   if t == "wildcard" and isinstance(o.get("cards"), list)}
    check_loops(parsed, card_counts.pop() if len(card_counts) == 1 else None, r)
    check_padding(parsed, r)
    check_config_shortcuts(project, r)
    check_dialogue_and_report(project, r)
    check_placeholders(project, args.strict, r)

    return _emit(r)


def _emit(r: Report) -> int:
    print()
    for w in r.warnings:
        print(f"  ⚠ WARN  {w}")
    for f in r.failures:
        print(f"  ✗ FAIL  {f}")
    if r.failures:
        print(f"\n{len(r.failures)} failure(s).")
        return 1
    print(f"OK — no failures{f', {len(r.warnings)} warning(s)' if r.warnings else ''}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
