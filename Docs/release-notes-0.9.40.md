# Tanque Studio 0.9.40

A crash fix. Nothing else changed.

## Removing a LoRA no longer crashes the app

In 0.9.39, deselecting a LoRA in the Focus Room drawer could terminate the app
immediately — an out-of-bounds array read on the main thread, with no warning and
no chance to save. Applying LoRAs was fine; removing one was not.

The drawer's rows were identified by their position in the list, and each row's
weight slider read and wrote through that position. Removing a row shortens the
list while the remaining rows are still being redrawn, so a row could look up a
slot that no longer existed. Rows above the removed one were unaffected, which is
why it did not show up in every case.

Rows are now identified by the LoRA's own file, and every read and write resolves
through that identity rather than through a position. Removing a row can no
longer leave another row pointing at the wrong LoRA, or at nothing.

If you are on 0.9.39, this is worth taking.

---

## Note for the curious

Two other places in the app already did this correctly — the Generate panel's own
LoRA list, and the StoryFlow step editor, which carries a comment explaining this
exact hazard. The drawer was written with positions anyway. The new tests pin the
behaviour so a future rewrite cannot quietly go back to indices.

Everything in [0.9.39](release-notes-0.9.39.md) still applies; this release adds
nothing to it.
