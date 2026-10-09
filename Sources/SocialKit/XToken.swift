import Foundation

/// JavaScript's `Number.prototype.toString(radix)`, ported from V8's `DoubleToRadixCString` so the
/// output (including the last fractional digits) matches browsers and Node exactly.
enum JSNumber {
    private static let digits = Array("0123456789abcdefghijklmnopqrstuvwxyz")

    static func string(_ input: Double, radix: Int) -> String {
        precondition((2...36).contains(radix))
        if input.isNaN { return "NaN" }
        if input.isInfinite { return input < 0 ? "-Infinity" : "Infinity" }
        if input == 0 { return "0" }
        let negative = input < 0
        let value = abs(input)
        let r = Double(radix)

        var integer = value.rounded(.down)
        var fraction = value - integer
        // Only as many fractional digits as the double can distinguish.
        var delta = max(0.5 * (value.nextUp - value), Double.leastNonzeroMagnitude)
        var fractionDigits: [Character] = []
        if fraction >= delta {
            repeat {
                fraction *= r
                delta *= r
                let digit = Int(fraction)
                fractionDigits.append(digits[digit])
                fraction -= Double(digit)
                // Round half to even, propagating carries back through written digits.
                if fraction > 0.5 || (fraction == 0.5 && digit & 1 == 1), fraction + delta > 1 {
                    while true {
                        guard let last = fractionDigits.popLast() else {
                            integer += 1
                            break
                        }
                        let d = digits.firstIndex(of: last)!
                        if d + 1 < radix {
                            fractionDigits.append(digits[d + 1])
                            break
                        }
                    }
                    break
                }
            } while fraction >= delta
        }

        // Integer digits; beyond 2^53 the low digits are not representable and V8 writes zeros.
        var integerDigits: [Character] = []
        while (integer / r).exponent > 52 {
            integer /= r
            integerDigits.append("0")
        }
        repeat {
            let remainder = fmod(integer, r)
            integerDigits.append(digits[Int(remainder)])
            integer = (integer - remainder) / r
        } while integer > 0

        var out = negative ? "-" : ""
        out += String(integerDigits.reversed())
        if !fractionDigits.isEmpty { out += "." + String(fractionDigits) }
        return out
    }
}

/// X's public syndication endpoint (the one behind embedded tweets and Vercel's `react-tweet`).
enum XSyndication {
    /// `((Number(id) / 1e15) * Math.PI).toString(6 ** 2).replace(/(0+|\.)/g, '')`, as in react-tweet's `getToken`.
    static func token(for id: String) -> String {
        let number = Double(id) ?? .nan
        return JSNumber.string((number / 1e15) * Double.pi, radix: 36).filter { $0 != "0" && $0 != "." }
    }

    static func url(for id: String) -> URL {
        var components = URLComponents(string: "https://cdn.syndication.twimg.com/tweet-result")!
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "lang", value: "es"),
            URLQueryItem(name: "token", value: token(for: id)),
        ]
        return components.url!
    }
}
