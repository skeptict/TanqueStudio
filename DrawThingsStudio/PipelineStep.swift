//
//  PipelineStep.swift
//  DrawThingsStudio
//
//  Data model for a single step in the workbench multi-step pipeline.
//

import Foundation

struct PipelineStep: Identifiable {
    let id = UUID()
    var prompt: String = ""           // empty = inherit from base prompt
    var negativePrompt: String = ""   // empty = inherit
    var modelOverride: String = ""    // empty = inherit
    var samplerOverride: Int = -1     // -1 = inherit; otherwise index into DrawThingsSampler.builtIn
    var stepsOverride: Int = 0        // 0 = inherit
    var cfgOverride: Double = 0       // 0 = inherit
    var strengthOverride: Double = 0.7
    var batchCount: Int = 1
    var usesPreviousOutput: Bool = true  // false only meaningful for step 1
}
