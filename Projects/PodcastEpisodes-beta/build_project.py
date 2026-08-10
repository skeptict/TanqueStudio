#!/usr/bin/env python3
"""Emit the Podcast Auditions StoryFlow Editor project from bible.json + configs.json.

Standard library only, matching Scripts/verify_vtable_offsets.py.

    python3 Projects/PodcastAuditions/build_project.py
    python3 Projects/PodcastAuditions/verify_project.py

WHY A GENERATOR AND NOT A HAND-WRITTEN .json
--------------------------------------------
Two reasons, both of them failure modes that look like success.

1. Triple escaping. An object-valued item's `value` is a JSON *string containing JSON*, and the
   spoken-dialogue cards contain literal `"` characters that have to survive into the model's
   prompt. Three layers:

       what the model reads      "Walter Prine, reading for co-host."
       inside the cards array    "\\"Walter Prine, reading for co-host.\\""
       inside the item's value   "{\\"wild\\":\\"loop\\",\\"cards\\":[\\"\\\\\\"Walter Prine…\\\\\\"\\"]}"

   Lose the innermost quotes and `framesDialog` counts zero spoken words, so every clip renders at
   exactly `padding` frames. Nothing errors. Six plausible, uniformly-wrong videos.
   This file never concatenates strings to build JSON; it calls json.dumps twice.

2. Duplicated card lists. IDENTITY and WARDROBE appear in BOTH phases and must return the same card
   at the same loop counter. Emitting both from the same bible rows makes drift impossible.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent

DEFAULT_BIBLE = HERE / "bible.json"
DEFAULT_CONFIGS = HERE / "configs.json"


# The project's identity — its name and its filenames — lives in configs.json's "project" block,
# NOT in constants here.
#
# It was constants, and that turned out to be a trap. Standing this project up a second time
# (PodcastEpisodes-beta) meant copying the folder and editing it, and three of these were missed:
# the emitted project was still called "Podcast Auditions", it was still written to
# `Podcast Auditions.json`, and — the dangerous one — its test fixture still pointed at
# `podcast-auditions.json`, so building the new project would have silently overwritten the old
# project's fixture and left its tests asserting against the wrong content.
#
# Data-driven, both folders' copies of this script are byte-identical, and the next copy needs
# only configs.json touched. Same argument as the character card lists: the fix for "two copies
# that must agree" is one source, not more care.
def project_paths(cfg: dict) -> tuple[str, Path, Path]:
    """(projectName, output .json path, test-fixture .json path) from the configs' project block."""
    block = cfg.get("project")
    if not isinstance(block, dict):
        sys.exit("configs.json is missing its \"project\" block "
                 "(needs \"name\", \"outputBasename\", \"fixtureBasename\")")
    missing = [k for k in ("name", "outputBasename", "fixtureBasename") if not block.get(k)]
    if missing:
        sys.exit(f"configs.json \"project\" block is missing: {', '.join(missing)}")
    return (
        block["name"],
        HERE / f"{block['outputBasename']}.json",
        REPO / "TanqueStudioTests" / "Fixtures" / f"{block['fixtureBasename']}.json",
    )


# ──────────────────────────────────────────────────────────────────────────────
# Item value typing
#
# The pipeline's `allowedKeys` table (StoryflowPipeline.js:59-113, 52 keys) types every
# instruction, and validateInstructionArray refuses the WHOLE run on a mismatch. In the *project*
# format those types map onto exactly four JSON shapes:
#
#   flag    → literal `true`
#   string  → JSON string
#   number  → JSON number  ← only `frames` and `moodboardRemove` reach the pipeline this way
#   object  → JSON *string* containing the object; both exporters parse it on the way out
#
# `frames8` is the third number-valued type in the Editor (ITEM_CONFIGS, StoryflowEditor.html:1409)
# but it is NOT one of the 52 allowedKeys — the Editor rewrites it to `frames` on export
# (StoryflowEditor.html:2798). It is listed here for completeness; this project emits none of the
# three. Where the kickoff notes and the source disagree on frames8, the source wins.
# ──────────────────────────────────────────────────────────────────────────────

FLAG_TYPES = {"canvasClear", "loopEnd", "crop", "approve", "sizex2", "end"}
NUMBER_TYPES = {"frames", "frames8", "moodboardRemove"}
OBJECT_TYPES = {"config", "size", "loop", "framesDialog", "wildcard", "sweep", "xlMagic",
                "matte", "hrf", "moveScale", "adaptSize", "inpaintTools", "moodboardWeights",
                "maskBody", "poseJSON"}
STRING_TYPES = {"note", "prompt", "concat", "negPrompt", "loopSave", "loopLoad",
                "canvasSave", "canvasLoad", "interrogate", "enhance"}


def flag(item_type: str) -> dict:
    assert item_type in FLAG_TYPES, f"{item_type} is not a flag-valued type"
    return {"type": item_type, "value": True}


def text(item_type: str, value: str) -> dict:
    assert item_type in STRING_TYPES, f"{item_type} is not a string-valued type"
    assert isinstance(value, str)
    return {"type": item_type, "value": value}


def obj(item_type: str, value: dict) -> dict:
    """Object-valued item. The value is json.dumps'd HERE; the caller passes a real dict.

    This is escaping layer 2 of 3. Layer 3 is the json.dump of the whole project at the end.
    Layer 1 — the literal `"` around spoken dialogue — is added by quoted() below, inside the
    Python string, so it is a plain character by the time it reaches either dumps call.
    """
    assert item_type in OBJECT_TYPES, f"{item_type} is not an object-valued type"
    assert isinstance(value, dict), f"{item_type} needs a dict, got {type(value).__name__}"
    return {"type": item_type, "value": json.dumps(value, ensure_ascii=False, separators=(",", ":"))}


def config_ref(shortcut: str) -> dict:
    """A `config` item that references a configShortcuts entry rather than inlining JSON."""
    assert shortcut.startswith("#"), f"config shortcut {shortcut!r} must start with '#'"
    return {"type": "config", "value": shortcut}


def quoted(spoken: str) -> str:
    """Wrap spoken text in the literal quotation marks framesDialog counts words inside.

    framesDialog's regex is /"([^"]+)"/g (StoryflowPipeline.js:451) — it pairs quotes left to
    right across the whole accumulated concat. A `"` anywhere in the bible text or in a shared
    fragment would re-pair the spans and change the frame count without erroring, which is why
    the builder owns these quotes and the bible is forbidden from containing any.
    """
    assert '"' not in spoken, f"spoken text must not contain a quote character: {spoken!r}"
    return f'"{spoken}"'


# ──────────────────────────────────────────────────────────────────────────────
# Shared prompt fragments
#
# `concat` appends with NO separator (StoryflowPipeline.js:966). Every space between a fragment
# and the wildcard card next to it is one this file has to supply, and a missing one glues two
# words together in the prompt. So the spacing is declared, not just typed: each fragment states
# whether it leads and/or trails with a space, and _build_fragments asserts the text agrees.
# A stray edit that eats a trailing space fails the build instead of degrading the prompt.
# ──────────────────────────────────────────────────────────────────────────────


class Fragment:
    __slots__ = ("name", "value")

    def __init__(self, name: str, value: str, *, lead: bool, trail: bool):
        assert '"' not in value, (
            f"fragment {name!r} contains a quote character; it would create a spurious "
            f"framesDialog span and shift every clip's frame count"
        )
        assert value.startswith(" ") == lead, (
            f"fragment {name!r} declares lead={lead} but "
            f"{'does not start' if lead else 'starts'} with a space"
        )
        assert value.endswith(" ") == trail, (
            f"fragment {name!r} declares trail={trail} but "
            f"{'does not end' if trail else 'ends'} with a space"
        )
        self.name = name
        self.value = value


#                                                                       lead   trail
A_OPEN = Fragment("A_OPEN",
                  "A casting-room headshot, medium shot, of ",
                  lead=False, trail=True)

WEARING = Fragment("WEARING",
                   ", wearing ",
                   lead=False, trail=True)

A_CLOSE = Fragment("A_CLOSE",
                   ", seated on a folding chair against a bare grey wall under flat overhead "
                   "fluorescent light, facing the lens, mouth closed, neutral expression, hands "
                   "at rest. Sharp focus, 50mm, shallow depth of field.",
                   lead=False, trail=False)

B_OPEN = Fragment("B_OPEN",
                  "A locked-off medium shot of ",
                  lead=False, trail=True)

B_SAYS = Fragment("B_SAYS",
                  ", seated on a folding chair in an empty casting room. They look into the lens "
                  "and say, ",
                  lead=False, trail=True)

B_BEAT = Fragment("B_BEAT",
                  " After a beat they add, ",
                  lead=True, trail=True)

B_IN = Fragment("B_IN",
                " in ",
                lead=True, trail=True)

B_CLOSE = Fragment("B_CLOSE",
                   ". The camera holds perfectly still on a tripod, 50mm at f/2.8, no reframing "
                   "and no zoom. Faint room tone, the low hum of an air vent and the occasional "
                   "creak of the chair fill the space between lines. Single continuous shot, "
                   "natural motion blur, film-like cadence.",
                   lead=False, trail=False)

# `mouth closed` in A_CLOSE is load-bearing, not decoration: phase A's output IS phase B's first
# frame, and LTX-2 handles dialogue badly when the start frame is mid-word.
#
# Everything B_CLOSE says about room tone, the vent and the chair is the ENTIRE audio design.
# LTX-2 has no audio config field in this pipeline — audio is prompt-driven — so that fragment,
# the quoted dialogue and the voice wildcard are the whole of it.

NEG_PROMPT = ("blurry, low resolution, jpeg artifacts, watermark, on-screen text, subtitles, "
              "warped face, malformed hands, extra fingers, duplicated limbs, camera shake, "
              "handheld wobble, zoom, dolly move, rack focus, cut to another shot")

SETUP_NOTE = (
    "PODCAST AUDITIONS — read this before running.\n"
    "\n"
    "SETUP: create the folder ~Pictures/PodcastAuditions/anchors/ before the first run. Nothing "
    "in the pipeline creates directories, and loopSave is handed a full path.\n"
    "\n"
    "Keep that folder EMPTY except for what this project writes. loopLoad indexes the directory "
    "by sorted position, so any stray image — a thumbnail, an old export — repairs every anchor "
    "with the wrong character.\n"
    "\n"
    "RUN ORDER: phase A writes the six anchors, phase B reads them back as first frames. Run the "
    "whole project in one pass. In Tanque Studio it must be one pass — loop paths there resolve "
    "against the run's own timestamped output folder, so anchors from an earlier run are invisible "
    "to a later one.\n"
    "\n"
    "FIRST TIME: set both loop counts to 1 and run phase A alone. That proves the folder exists "
    "and that the canvas save lands, in a fraction of the time a full run takes.\n"
    "\n"
    "TRIM: to keep the characters and skip the auditions, delete the marked note below and "
    "everything after it."
)

TRIM_MARKER = "──────── TRIM LINE ────────"

TRIM_NOTE = (
    f"{TRIM_MARKER}  Delete this note and EVERY item below it to turn this into a "
    "characters-only project. Everything above it stands alone: it renders six stills and saves "
    "them to ~Pictures/PodcastAuditions/anchors/. Nothing below it is referenced from above."
)


# ──────────────────────────────────────────────────────────────────────────────
# Bible validation
# ──────────────────────────────────────────────────────────────────────────────

BIBLE_FIELDS = ("name", "identity", "wardrobe", "slate", "line", "voice", "seed")
SPOKEN_FIELDS = ("slate", "line")
PROSE_FIELDS = ("identity", "wardrobe", "voice")


def load_bible(path: Path) -> list[dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    rows = data.get("characters")
    if not isinstance(rows, list) or not rows:
        sys.exit(f"{path}: 'characters' must be a non-empty list")

    problems: list[str] = []
    for i, row in enumerate(rows):
        label = f"characters[{i}]"
        for field in BIBLE_FIELDS:
            if field not in row:
                problems.append(f"{label}: missing '{field}'")
        for field in PROSE_FIELDS + SPOKEN_FIELDS:
            v = row.get(field)
            if isinstance(v, str):
                if not v.strip():
                    problems.append(f"{label}.{field}: empty")
                if '"' in v:
                    problems.append(
                        f"{label}.{field}: contains a quote character — framesDialog counts words "
                        f"inside quoted spans and this would split one"
                    )
            elif field in row:
                problems.append(f"{label}.{field}: must be a string")
        if "seed" in row and not isinstance(row["seed"], int):
            problems.append(f"{label}.seed: must be an integer")

    if problems:
        sys.exit("bible.json is not usable:\n  " + "\n  ".join(problems))
    return rows


# ──────────────────────────────────────────────────────────────────────────────
# Project assembly
# ──────────────────────────────────────────────────────────────────────────────


def wildcard(cards: list[str]) -> dict:
    """A per-character wildcard. ALWAYS `wild: "loop"` — see the assertion, and read on.

    "loop" is the only mode that is a pure function of the global counter:

        case "loop":    return this.originalCards[globalLoopCounter % totalCards];
        case "once":    … this.currentIndex++ …          // internal state
        case "shuffle": … this.shuffledCards.shift()     // consumes a deck
        case "random":  … Math.random() …

    The whole two-phase architecture rests on that. Phase B's IDENTITY wildcard is a SECOND
    registry entry holding a duplicate of phase A's cards — you cannot reference one wildcard
    from two places — and the only thing making entry #2 return the same card at counter 3 that
    entry #1 returned is that both are stateless reads of the same counter. Any other mode
    decorrelates the phases immediately and pairs each character with someone else's anchor.
    """
    assert isinstance(cards, list) and cards, "wildcard needs a non-empty card list"
    return obj("wildcard", {"wild": "loop", "cards": cards})


def build_items(bible: list[dict], cfg: dict) -> list[dict]:
    n = len(bible)

    identity_cards = [row["identity"] for row in bible]
    wardrobe_cards = [row["wardrobe"] for row in bible]
    voice_cards = [row["voice"] for row in bible]
    slate_cards = [quoted(row["slate"]) for row in bible]
    line_cards = [quoted(row["line"]) for row in bible]
    # Sweep cards are stored as strings in Editor-authored projects and coerced to real JSON
    # numbers on export (StoryflowEditor.html:2807, StoryFlowProjectCodec.swift's sweep branch).
    # Matching that convention keeps the file byte-shaped like one the Editor would have written.
    seed_cards = [str(row["seed"]) for row in bible]

    sizes = cfg["sizes"]
    fd = cfg["framesDialog"]
    anchors_dir = cfg["anchorsDirectory"]
    anchor_file = cfg["anchorFilename"]

    # `start` must be present and must be 0. loopSave offsets by _startCount and loopLoad does
    # not (StoryflowPipeline.js:1279 vs :1258), so a non-zero start makes the pairing depend on
    # the anchors folder holding exactly these files and nothing else. And an ABSENT start leaves
    # _startCount undefined, so loopSave's index becomes NaN and every file is written as
    # `anchor_NaN.png`.
    loop_value = {"loop": n, "start": 0}

    items: list[dict] = [
        text("note", SETUP_NOTE),
        flag("canvasClear"),
        # negPrompt is persistent and does not render (StoryflowPipeline.js:1000). One setting
        # above both phases rather than one per phase.
        text("negPrompt", NEG_PROMPT),

        # ── PHASE A · CHARACTERS (stills) ────────────────────────────────────
        config_ref("#krea2_stills"),
        # `size` merges into the configuration AND calls updateCanvasSize; `config` merges without
        # touching the canvas (:1005 vs :1010). This is the item that re-frames the canvas, which
        # is why each phase carries one ABOVE its loop — loopLoad, unlike canvasLoad, does not
        # call updateCanvasSize and will happily drop a 16:9 anchor onto a square canvas.
        obj("size", {"width": sizes["stills"]["width"], "height": sizes["stills"]["height"]}),

        obj("loop", loop_value),
        # Inside the loop, so each still starts clean instead of img2img-ing the previous character.
        flag("canvasClear"),
        # Pinned seeds: insurance for regenerating an anchor you already approved. Seed is NOT the
        # consistency mechanism here — phase B is image-to-video, so identity arrives as pixels.
        obj("sweep", {"paramName": "seed", "wild": "loop", "cards": seed_cards}),
        text("concat", A_OPEN.value),
        wildcard(identity_cards),
        text("concat", WEARING.value),
        wildcard(wardrobe_cards),
        text("concat", A_CLOSE.value),
        # `prompt` IS the render trigger: concat += value; generate(); concat = "" (:959).
        # There is no separate generate instruction in this format.
        text("prompt", ""),
        text("loopSave", anchor_file),
        flag("loopEnd"),

        text("note", TRIM_NOTE),

        # ── PHASE B · AUDITIONS (video) ──────────────────────────────────────
        config_ref("#ltx2_video"),
        obj("size", {"width": sizes["video"]["width"], "height": sizes["video"]["height"]}),

        obj("loop", loop_value),
        text("loopLoad", anchors_dir),
        text("concat", B_OPEN.value),
        wildcard(identity_cards),
        text("concat", WEARING.value),
        wildcard(wardrobe_cards),
        text("concat", B_SAYS.value),
        wildcard(slate_cards),
        text("concat", B_BEAT.value),
        wildcard(line_cards),
        text("concat", B_IN.value),
        wildcard(voice_cards),
        text("concat", B_CLOSE.value),
        # generate:false plus an explicit bare `prompt`. Both engines honour generate:true, but the
        # explicit prompt makes the render point visible in both step lists and keeps preflight's
        # generate-detection honest. Costs one item.
        obj("framesDialog", {"wps": fd["wps"], "padding": fd["padding"], "generate": False}),
        text("prompt", ""),
        flag("loopEnd"),
    ]

    _assert_invariants(items, n, fd)
    return items


def _assert_invariants(items: list[dict], expected_cards: int, fd: dict) -> None:
    """Assert on the BUILT items, not on the intent that produced them.

    Everything here is also checked by verify_project.py against the written file. Doing it twice
    is deliberate: this catches a bad edit before anything reaches disk, verify catches a file
    that was edited after the fact.
    """
    for i, item in enumerate(items):
        t, v = item["type"], item["value"]
        if t in OBJECT_TYPES and isinstance(v, str) and not v.startswith("#"):
            parsed = json.loads(v)  # must round-trip
            if t == "wildcard":
                assert parsed["wild"] == "loop", \
                    f"item {i}: wildcard is {parsed['wild']!r}, must be 'loop'"
                assert len(parsed["cards"]) == expected_cards, \
                    f"item {i}: {len(parsed['cards'])} cards, expected {expected_cards}"
            if t == "sweep":
                assert parsed["wild"] == "loop", f"item {i}: sweep must be 'loop'"
                assert len(parsed["cards"]) == expected_cards
            if t == "loop":
                assert parsed["start"] == 0, f"item {i}: loop start must be 0"
                assert parsed["loop"] == expected_cards
            if t == "framesDialog":
                assert parsed["padding"] % 8 == 0, \
                    (f"item {i}: padding {parsed['padding']} is not a multiple of 8; "
                     f"framesDialog returns 8k+1 and padding is added raw")

    assert fd["padding"] % 8 == 0, f"configs.json framesDialog.padding {fd['padding']} must be a multiple of 8"

    # The trim line must be a single contiguous tail. Nothing above it may reference anything below.
    trim = [i for i, it in enumerate(items) if it["type"] == "note" and TRIM_MARKER in it["value"]]
    assert len(trim) == 1, f"expected exactly one TRIM LINE note, found {len(trim)}"
    head = items[:trim[0]]
    assert sum(1 for it in head if it["type"] == "loop") == 1, "phase A must contain exactly one loop"
    assert sum(1 for it in head if it["type"] == "loopEnd") == 1, "phase A's loop must be closed"


def build_project(bible: list[dict], cfg: dict) -> dict:
    shortcuts = cfg["configShortcuts"]
    return {
        "projectName": project_paths(cfg)[0],
        "items": build_items(bible, cfg),
        # All four shortcut maps are required to be present even when empty — the Editor and the
        # Swift codec both decode them as non-optional.
        "promptTriggers": {},
        # configShortcuts values are JSON *strings*: resolveConfigShortcuts does raw text
        # substitution of `#key` into the config item's value (StoryflowEditor.html:2418).
        "configShortcuts": {
            k: json.dumps(v, ensure_ascii=False, separators=(",", ":")) for k, v in shortcuts.items()
        },
        "poseJSONShortcuts": {},
        "wildcardShortcuts": {},
    }


# ──────────────────────────────────────────────────────────────────────────────
# Pipeline export
#
# The Editor PROJECT format and the pipeline INSTRUCTION ARRAY are two different things, and
# `StoryflowPipeline.js` only accepts the second. Hand it a project and preflight dies on
#
#     Exception: arr.entries is not a function
#
# at validateInstructionArray (:122) — `arr.entries()` is an Array method and a project is an
# object. Normally the Editor's "Export to Pipeline" (or Tanque Studio's Copy Pipeline) does this
# conversion; emitting it here means a recipient with only Draw Things never needs either.
#
# The transform, matching StoryFlowProjectCodec.toPipelineArray and the Editor's own exporter:
#   {type, value}          → {type: value}
#   config "#shortcut"     → the resolved config OBJECT
#   object-valued strings  → parsed to real objects (allowedKeys types them "object")
#   note                   → whitespace runs collapsed to single spaces (Editor does this for
#                            note/interrogate/enhance only; prompt/negPrompt/concat keep theirs)
#   sweep cards            → numeric-looking strings coerced to real numbers
#   append                 → {"end": true}
#
# PodcastAuditionsFixtureTests asserts this output is deep-equal to what Tanque Studio's codec
# produces for the same project, so the two implementations cannot drift.
# ──────────────────────────────────────────────────────────────────────────────


def _collapse_whitespace(s: str) -> str:
    return " ".join(s.split())


def _coerce_number(card):
    if not isinstance(card, str):
        return card
    trimmed = card.strip()
    if not trimmed:
        return card
    try:
        n = float(trimmed)
    except ValueError:
        return card
    return int(n) if n.is_integer() and abs(n) < 1e15 else n


def to_pipeline_array(project: dict) -> list[dict]:
    shortcuts = project["configShortcuts"]
    out: list[dict] = []

    for item in project["items"]:
        t, v = item["type"], item["value"]

        if t == "note":
            out.append({"note": _collapse_whitespace(v)})
        elif t == "config":
            if isinstance(v, str) and v.startswith("#"):
                out.append({"config": json.loads(shortcuts[v])})
            else:
                out.append({"config": json.loads(v)})
        elif t == "sweep":
            o = json.loads(v)
            if isinstance(o.get("cards"), list):
                o["cards"] = [_coerce_number(c) for c in o["cards"]]
            out.append({"sweep": o})
        elif t in OBJECT_TYPES:
            out.append({t: json.loads(v)})
        else:
            out.append({t: v})

    out.append({"end": True})
    return out


# ──────────────────────────────────────────────────────────────────────────────
# Report
# ──────────────────────────────────────────────────────────────────────────────


def spoken_frames(words: int, wps: float, padding: int) -> int:
    """StoryflowPipeline.js framesDialog() + the executor's `wps + value.padding` (:1045-1050)."""
    return math.ceil((words / wps) * 25 / 8) * 8 + 1 + padding


def report(project: dict, bible: list[dict], cfg: dict) -> None:
    fd = cfg["framesDialog"]
    print(f"  {len(project['items'])} items, {len(bible)} characters")
    print(f"  wps {fd['wps']}, padding {fd['padding']}\n")
    print(f"  {'character':<16} {'words':>5}  {'frames':>6}  {'seconds':>7}")
    for row in bible:
        words = len(row["slate"].split()) + len(row["line"].split())
        frames = spoken_frames(words, fd["wps"], fd["padding"])
        flagged = "  ⚠ over Tanque Studio's 257 cap" if frames > 257 else ""
        print(f"  {row['name']:<16} {words:>5}  {frames:>6}  {frames / 25:>6.1f}s{flagged}")

    todos = json.dumps(cfg["configShortcuts"]).count('"TODO_NED"')
    if todos:
        print(f"\n  ⚠ {todos} TODO_NED placeholder(s) still in configs.json — not runnable yet")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--bible", type=Path, default=DEFAULT_BIBLE)
    ap.add_argument("--configs", type=Path, default=DEFAULT_CONFIGS)
    ap.add_argument("--out", type=Path, default=None,
                    help="defaults to configs.json's project.outputBasename")
    ap.add_argument("--fixture", type=Path, default=None,
                    help="second copy for the Swift round-trip tests; --fixture '' to skip")
    args = ap.parse_args()

    bible = load_bible(args.bible)
    cfg = json.loads(args.configs.read_text(encoding="utf-8"))
    _, default_out, default_fixture = project_paths(cfg)
    out = args.out or default_out
    fixture = default_fixture if args.fixture is None else args.fixture
    project = build_project(bible, cfg)

    # Escaping layer 3. indent=2 matches the Editor's own Save Project output closely enough to
    # diff by eye; the content is what matters, not the whitespace.
    blob = json.dumps(project, ensure_ascii=False, indent=2) + "\n"
    out.write_text(blob, encoding="utf-8")
    print(f"wrote {out}")

    # The Draw Things-ready form. Paste THIS into the StoryFlow script, not the project above.
    pipeline = json.dumps(to_pipeline_array(project), ensure_ascii=False, indent=2) + "\n"
    pipeline_out = out.with_suffix(".pipeline.json")
    pipeline_out.write_text(pipeline, encoding="utf-8")
    print(f"wrote {pipeline_out}   ← paste this one into Draw Things")

    if str(fixture):
        fixture.write_text(blob, encoding="utf-8")
        fixture.with_suffix(".pipeline.json").write_text(pipeline, encoding="utf-8")
        print(f"wrote {fixture} (+ .pipeline.json)")
    print()
    report(project, bible, cfg)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
