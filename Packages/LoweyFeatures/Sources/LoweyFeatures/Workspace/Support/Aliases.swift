import LoweyCore

// SwiftUI also declares `Document`, `LibraryItem`, `Scene` and `Axis`, and `Transform` is a common name; declarations in
// this module win over imported ones, so these make the Core types the default everywhere in the features (whether or
// not a file imports the engine, which publishes the same Core… names).
typealias Document = LoweyCore.Document
typealias LibraryItem = LoweyCore.LibraryItem
typealias CoreScene = LoweyCore.Scene
typealias CoreTransform = LoweyCore.Transform
typealias CoreAxis = LoweyCore.Axis
