//
//  ModelAvailability.swift
//  TanqueStudio
//
//  One answer to "is this model in Draw Things' list", for every surface that asks.
//

import Foundation

/// Whether Draw Things' reported inventory contains a model.
///
/// ## ⚠️ Absence means "cannot confirm", not "will fail"
///
/// Draw Things' model list is its own **file inventory** (`EchoReply.files`, see
/// `DrawThingsGRPCClient.fetchModels`), and **Bridge Mode renders models that are
/// not on disk.** Measured 2026-09-07: `krea_2_turbo_q8p.ckpt` is absent from one
/// lab server's list of 524 and rendered there in 23.2 s; so is every LTX
/// checkpoint. Both are in daily use.
///
/// So **every caller must warn, never block.** A hard refusal in `generateInpaint`
/// survived until 2026-09-09, when it rejected a Qwen Edit model that renders fine
/// from Generate one panel over (`1bbf577`). Don't reintroduce one without a way to
/// ask Draw Things what it can actually serve.
///
/// This lives on its own rather than inside a feature's file because four surfaces
/// ask the question — Generate, inpaint, the metadata applier, the Render Queue —
/// and each inline copy had to independently remember the empty-list rule below.
enum ModelAvailability {

    /// ⚠️ **An empty `known` means the inventory could not be fetched, not that
    /// nothing is installed.** Treating that as "every model is unavailable" would
    /// turn an unreachable Draw Things into a wall of warnings about every job —
    /// a connection problem wearing the wrong error. This guard is the load-bearing
    /// part of the whole check, and the reason it is worth having in one place.
    ///
    /// An empty `model` is likewise not this function's complaint to make; callers
    /// that care already refuse it earlier with "Select a model first."
    static func isAvailable(_ model: String, in known: [DrawThingsModel]) -> Bool {
        guard !known.isEmpty else { return true }
        let name = model.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return true }
        return known.contains { $0.filename == name || $0.name == name }
    }
}
