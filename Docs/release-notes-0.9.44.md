# Tanque Studio 0.9.44

A follow-up to 0.9.43: the second half of a stills-then-animate run is now one
button instead of hand-picking images out of the gallery, and the Render Queue
stops relying on autosave for changes you have just made.

## Use Results as Sources

Setting up "render a batch of stills, then animate each one" meant finding the
images you had *just made* in a gallery that may hold thousands, and selecting
them in the right order — because for a paired axis the order **is** the pairing,
so getting it wrong silently animates each image with someone else's prompt.

There is now a **Use Results as Sources** button in the JOBS header. It takes
every finished job's result into a Source Image axis **in queue order**, which is
the order your prompts were in, so the pairing is right by construction rather
than rebuilt by eye.

- It **appends** rather than replaces, and skips images already in the axis, so
  pressing it twice changes nothing and anything you picked by hand survives.
- The picker is unchanged and remains the way to choose images the queue did not
  produce — files from disk, older renders, anything else.

### One paired axis is not enough

The new axis arrives set to **Pair**, but your Prompt axis is deliberately left
alone — silently changing a setting you chose would be worse than leaving you a
step. A *single* paired axis behaves exactly like a crossed one, so until the
Prompt axis is also on Pair, six images and six prompts is **36** jobs, not six.

The queue now says so: when one axis is paired and another of the same length is
not, a line above Expand tells you which switch to flip. The Expand button's own
count is the other giveaway.

`Docs/render-queue-two-pass-example.md` walks the whole flow end to end.

## Queue changes reach disk when you make them

The Render Queue relied entirely on SwiftData's autosave for structural edits, so
the file on disk could lag what you were looking at by an indefinite interval.
Adding an axis, deleting a job, reordering, Clear All and especially **Expand**
now flush immediately.

This matters more than it used to: since 0.9.43 each job carries its own copy of
its source image, so re-doing a large expansion is no longer the trivial cost it
was when jobs were only text.

Typing in an axis's values box is still left to autosave, deliberately — it fires
on every keystroke, and a disk write per character would be a worse trade than
the exposure it closes.

## Notes

Nothing in this release changes how anything renders. If a queue you built in
0.9.43 looks the same after upgrading, that is expected — the difference is that
it is now written down as soon as you build it.
