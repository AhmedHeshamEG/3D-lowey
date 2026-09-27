import LoweyCore

// SwiftUI also defines `Document` and `LibraryItem`. Declarations in this module win over
// imported ones, so these aliases make the LoweyCore types the default inside the app.
typealias Document = LoweyCore.Document
typealias LibraryItem = LoweyCore.LibraryItem
