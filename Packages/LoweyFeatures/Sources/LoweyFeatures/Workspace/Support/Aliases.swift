import LoweyCore

// SwiftUI also declares `Document` and `LibraryItem`; declarations in this module win over imported ones, so these
// make the Core types the default everywhere in the features. (`Scene`, `Transform` and `Axis` go through the
// engine's CoreScene, CoreTransform and CoreAxis.)
typealias Document = LoweyCore.Document
typealias LibraryItem = LoweyCore.LibraryItem
