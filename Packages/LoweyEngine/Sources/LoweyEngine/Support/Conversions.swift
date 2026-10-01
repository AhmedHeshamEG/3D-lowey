import CoreGraphics
import LoweyCore
import simd
import UIKit

public extension Vec3 {
    var simd: SIMD3<Float> { float3 }
}

public extension RGBA {
    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }
    var cgColor: CGColor { uiColor.cgColor }

    init(_ color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(Double(r), Double(g), Double(b), Double(a))
    }
}

public extension UIFont {
    /// The same font in another system design (rounded, serif…), or itself when unavailable.
    func withDesign(_ design: UIFontDescriptor.SystemDesign) -> UIFont {
        guard let descriptor = fontDescriptor.withDesign(design) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
