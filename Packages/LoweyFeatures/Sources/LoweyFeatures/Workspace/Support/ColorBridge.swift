import LoweyCore
import LoweyEngine
import SwiftUI
import UIKit

public extension RGBA {
    /// SwiftUI colour of a Core colour.
    var color: Color { Color(uiColor: uiColor) }

    /// Core colour of a SwiftUI colour (sRGB).
    init(_ color: Color) {
        self.init(UIColor(color))
    }
}

public extension ColorValue {
    func swatch(in palette: Palette) -> Color {
        resolved(in: palette).color
    }
}
