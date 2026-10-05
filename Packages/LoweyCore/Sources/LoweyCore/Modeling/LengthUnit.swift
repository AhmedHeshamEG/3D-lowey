import Foundation

/// The units lengths are shown and typed in. The scene itself is always in metres.
public enum LengthUnit: String, Codable, Sendable, CaseIterable {
    case millimetre = "mm"
    case centimetre = "cm"
    case metre = "m"
    case inch = "in"
    case foot = "ft"

    public var metres: Double {
        switch self {
        case .millimetre: 0.001
        case .centimetre: 0.01
        case .metre: 1
        case .inch: 0.0254
        case .foot: 0.3048
        }
    }

    public var symbol: String { rawValue }

    public var label: String {
        switch self {
        case .millimetre: "Millimetres"
        case .centimetre: "Centimetres"
        case .metre: "Metres"
        case .inch: "Inches"
        case .foot: "Feet"
        }
    }

    /// Decimal places worth showing (a tenth of a millimetre or better).
    var decimals: Int {
        switch self {
        case .millimetre: 1
        case .centimetre, .inch: 2
        case .metre, .foot: 3
        }
    }

    /// A length in metres as text in this unit: "40 mm", "12.5 mm", "1.25 m".
    public func format(_ metres: Double, symbol showsSymbol: Bool = true) -> String {
        let value = metres / self.metres
        let scale = pow(10, Double(decimals))
        let rounded = (value * scale).rounded() / scale
        var text = String(format: "%.\(decimals)f", rounded == 0 ? 0 : rounded)
        while text.contains("."), text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") { text.removeLast() }
        return showsSymbol ? "\(text) \(symbol)" : text
    }

    static func named(_ name: String) -> LengthUnit? {
        switch name.lowercased() {
        case "mm", "millimetre", "millimetres", "millimeter", "millimeters": .millimetre
        case "cm", "centimetre", "centimetres", "centimeter", "centimeters": .centimetre
        case "m", "metre", "metres", "meter", "meters": .metre
        case "in", "inch", "inches", "\"": .inch
        case "ft", "foot", "feet", "'": .foot
        default: nil
        }
    }
}

/// Typed lengths: numbers, + − × ÷, brackets and a unit on any number (`25mm`, `2*12`, `1ft 6in`, `40 - 2*3mm`).
/// Plain numbers are scale factors until the end, where whatever has no unit is read in the default unit; adding a
/// plain number to a length reads it in the default unit too.
public struct LengthExpression {
    public enum Failure: Error, Equatable {
        case empty
        case unexpected(String)
        case divisionByZero
    }

    private enum Token: Equatable {
        case number(Double)
        case unit(LengthUnit)
        case op(Character)
        case open, close
    }

    /// A value that is a length (in metres) or a plain number.
    private struct Quantity {
        var value: Double
        var isLength: Bool
    }

    private var tokens: [Token]
    private var position = 0
    private let unit: LengthUnit

    /// The length in metres.
    public static func evaluate(_ text: String, defaultUnit: LengthUnit) throws(Failure) -> Double {
        var parser = try LengthExpression(tokens: tokenize(text), unit: defaultUnit)
        guard !parser.tokens.isEmpty else { throw .empty }
        let result = try parser.sum()
        guard parser.position == parser.tokens.count else { throw .unexpected(parser.describe(parser.tokens[parser.position])) }
        return result.isLength ? result.value : result.value * defaultUnit.metres
    }

    private init(tokens: [Token], unit: LengthUnit) {
        self.tokens = tokens
        self.unit = unit
    }

    private func asLength(_ quantity: Quantity) -> Double {
        quantity.isLength ? quantity.value : quantity.value * unit.metres
    }

    private mutating func sum() throws(Failure) -> Quantity {
        var result = try product()
        while position < tokens.count {
            if case let .op(symbol) = tokens[position], symbol == "+" || symbol == "-" {
                position += 1
                let rhs = try product()
                result = add(result, rhs, sign: symbol == "+" ? 1 : -1)
            } else if case .number = tokens[position], result.isLength {
                // Lengths side by side add up: "1ft 6in".
                let rhs = try product()
                result = add(result, rhs, sign: 1)
            } else {
                break
            }
        }
        return result
    }

    private func add(_ lhs: Quantity, _ rhs: Quantity, sign: Double) -> Quantity {
        if lhs.isLength || rhs.isLength {
            return Quantity(value: asLength(lhs) + sign * asLength(rhs), isLength: true)
        }
        return Quantity(value: lhs.value + sign * rhs.value, isLength: false)
    }

    private mutating func product() throws(Failure) -> Quantity {
        var result = try factor()
        while position < tokens.count, case let .op(symbol) = tokens[position], symbol == "*" || symbol == "/" {
            position += 1
            let rhs = try factor()
            if symbol == "*" {
                let both = result.isLength && rhs.isLength
                result = Quantity(value: result.value * rhs.value / (both ? unit.metres : 1), isLength: result.isLength || rhs.isLength)
            } else {
                guard rhs.value != 0 else { throw .divisionByZero }
                result = Quantity(value: result.value / rhs.value, isLength: result.isLength && !rhs.isLength)
            }
        }
        return result
    }

    private mutating func factor() throws(Failure) -> Quantity {
        guard position < tokens.count else { throw .empty }
        let token = tokens[position]
        position += 1
        var quantity: Quantity
        switch token {
        case let .number(value):
            quantity = Quantity(value: value, isLength: false)
        case .open:
            quantity = try sum()
            guard position < tokens.count, tokens[position] == .close else { throw .unexpected("(") }
            position += 1
        case .op("-"):
            let inner = try factor()
            return Quantity(value: -inner.value, isLength: inner.isLength)
        default:
            throw .unexpected(describe(token))
        }
        if position < tokens.count, case let .unit(named) = tokens[position] {
            position += 1
            let value = quantity.isLength ? quantity.value / unit.metres * named.metres : quantity.value * named.metres
            quantity = Quantity(value: value, isLength: true)
        }
        return quantity
    }

    private func describe(_ token: Token) -> String {
        switch token {
        case let .number(value): String(value)
        case let .unit(unit): unit.symbol
        case let .op(symbol): String(symbol)
        case .open: "("
        case .close: ")"
        }
    }

    private static func tokenize(_ text: String) throws(Failure) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.isWhitespace {
                index = text.index(after: index)
            } else if character.isNumber || character == "." || character == "," {
                var end = index
                while end < text.endIndex, text[end].isNumber || text[end] == "." || text[end] == "," {
                    end = text.index(after: end)
                }
                guard let value = Double(text[index ..< end].replacingOccurrences(of: ",", with: ".")) else {
                    throw .unexpected(String(text[index ..< end]))
                }
                tokens.append(.number(value))
                index = end
            } else if let symbol = operatorSymbol(character) {
                tokens.append(.op(symbol))
                index = text.index(after: index)
            } else if character == "(" || character == ")" {
                tokens.append(character == "(" ? .open : .close)
                index = text.index(after: index)
            } else if character.isLetter || character == "\"" || character == "'" {
                let end = wordEnd(text, from: index)
                tokens.append(try word(String(text[index ..< end])))
                index = end
            } else {
                throw .unexpected(String(character))
            }
        }
        return tokens
    }

    private static func wordEnd(_ text: String, from index: String.Index) -> String.Index {
        var end = text.index(after: index)
        guard text[index].isLetter else { return end }
        while end < text.endIndex, text[end].isLetter {
            end = text.index(after: end)
        }
        return end
    }

    private static func word(_ word: String) throws(Failure) -> Token {
        if word.lowercased() == "x" { return .op("*") }
        guard let unit = LengthUnit.named(word) else { throw .unexpected(word) }
        return .unit(unit)
    }

    private static func operatorSymbol(_ character: Character) -> Character? {
        switch character {
        case "+", "-", "*", "/": character
        case "×": "*"
        case "÷": "/"
        case "−": "-"
        default: nil
        }
    }
}
