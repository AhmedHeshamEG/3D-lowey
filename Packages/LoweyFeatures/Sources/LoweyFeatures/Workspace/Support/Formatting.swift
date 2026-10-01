import Foundation

/// Human-friendly numbers and times for panels.
public enum NumberFormat {
    /// Two decimals at most, none for whole numbers.
    public static func short(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(format: "%.0f", rounded) }
        return String(format: "%.2f", rounded)
    }

    public static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

public enum TimeFormat {
    /// 00:01.25
    public static func clock(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = time - Double(minutes * 60)
        return String(format: "%02d:%05.2f", minutes, seconds)
    }

    /// 2s / 2.5s (ruler labels).
    public static func short(_ time: Double) -> String {
        time == time.rounded() ? "\(Int(time))s" : String(format: "%.1fs", time)
    }

    /// The ruler's tick step for a zoom (points per second).
    public static func tickStep(pointsPerSecond: Double) -> Double {
        for step in [1.0 / 30, 1.0 / 10, 0.2, 0.5, 1, 2, 5, 10, 30] where step * pointsPerSecond >= 12 {
            return step
        }
        return 60
    }
}

extension String {
    /// camelCase → "Camel case".
    var spacedTitle: String {
        var result = ""
        for character in self {
            if character.isUppercase { result += " " }
            result += String(character)
        }
        return result.prefix(1).uppercased() + result.dropFirst().lowercased()
    }
}
