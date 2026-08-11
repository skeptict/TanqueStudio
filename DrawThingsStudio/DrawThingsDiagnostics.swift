import Foundation

// MARK: - DrawThingsDiagnostics
//
// Explanations for Draw Things failures whose real cause is nothing like their symptom, kept in
// one place because they are needed from more than one surface and have twice been learned the
// expensive way.
//
// This exists because the good explanation lived as a `private var` on `GenerateViewModel`, so
// StoryFlow — which hits the identical failure on every render in a long run — logged a bare
// "No image returned from generate step" instead. On 2026-08-11 that turned a stale Draw Things+
// session into an afternoon: the run reported "✓ Completed", saved a still where a clip should
// have been, and said nothing about why.

enum DrawThingsDiagnostics {

    /// Draw Things answered successfully with an **empty image list**.
    ///
    /// The cause is almost never what the symptom suggests. On 2026-08-04 the three obvious
    /// candidates — model missing, unsupported sampler, shared-secret mismatch — were all wrong
    /// and cost a full day. The actual cause was a **stale Draw Things+ session**: with the
    /// server's Bridge Mode on (its default), renders route through the DT+ account, and a bad
    /// session there fails exactly this way — success, zero images, no local generation
    /// attempted. Signing out of DT+ and back in cleared it.
    ///
    /// It recurred on 2026-08-11 with two further faces, both from the same root cause, which is
    /// why this text leads with the session rather than listing it last:
    ///
    /// - Draw Things **crashed** (`SIGTRAP` inside `TextEncoder.encodeLTX2`) — with the session
    ///   stale it could not reach the cloud, fell back to the local generator for a DT+-only
    ///   model, and read weights that were not on disk.
    /// - Draw Things **hung** in `textEncoding` for twenty minutes, emitting 7,614 progress
    ///   events without ever leaving the stage.
    ///
    /// So: empty, hung, or crashed, check the DT+ session first. Bridge Mode being *on* does not
    /// rule it out — on 2026-08-11 it was already on.
    static let noImageReturned =
        "With Bridge Mode on, renders go through your Draw Things+ account, and a stale session "
      + "fails exactly this way — sign out of Draw Things+ and back in, which has now fixed it "
      + "twice. Otherwise the model may not be usable on that server, or the sampler may not "
      + "suit it. Draw Things' own window shows what it actually did."
}
