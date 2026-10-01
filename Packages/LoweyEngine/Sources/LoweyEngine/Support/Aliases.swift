import LoweyCore

// SwiftUI also defines `Scene` and Foundation-adjacent frameworks define `Transform` and `Axis`. These aliases keep
// call sites readable without module-qualifying every use.
public typealias CoreScene = LoweyCore.Scene
public typealias CoreTransform = LoweyCore.Transform
public typealias CoreAxis = LoweyCore.Axis
