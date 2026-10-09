import Foundation

/// Minimal HTML helpers for the few fragments we read from embed pages.
enum HTMLText {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "hellip": "…", "mdash": "—", "ndash": "–", "laquo": "«", "raquo": "»", "copy": "©", "reg": "®",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "middot": "·", "bull": "•",
    ]

    /// Decodes named and numeric character references (`&amp;`, `&#064;`, `&#x1F600;`).
    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        out.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "&", let semi = s[i...].prefix(12).firstIndex(of: ";") {
                let entity = s[s.index(after: i)..<semi]
                if let decoded = decode(entity) {
                    out += decoded
                    i = s.index(after: semi)
                    continue
                }
            }
            out.append(c)
            i = s.index(after: i)
        }
        return out
    }

    private static func decode(_ entity: Substring) -> String? {
        if entity.hasPrefix("#") {
            let body = entity.dropFirst()
            let value = body.hasPrefix("x") || body.hasPrefix("X") ? UInt32(body.dropFirst(), radix: 16) : UInt32(body, radix: 10)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return named[String(entity)]
    }

    /// Converts an HTML fragment to plain text: `<br>` becomes a newline, tags are dropped, entities decoded.
    static func plainText(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        s = decodeEntities(s).replacingOccurrences(of: "\u{00A0}", with: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first start tag whose `class` attribute contains `className` as a whole word, e.g. `<img class="EmbeddedMediaImage" …>`.
    static func tag(withClass className: String, in html: String, from start: String.Index? = nil) -> Substring? {
        var searchStart = start ?? html.startIndex
        while let r = html.range(of: className, range: searchStart..<html.endIndex) {
            searchStart = r.upperBound
            guard let open = html[..<r.lowerBound].lastIndex(of: "<"),
                  let close = html[r.upperBound...].firstIndex(of: ">") else { continue }
            let tag = html[open...close]
            if let cls = attribute("class", in: tag), cls.split(separator: " ").contains(Substring(className)) { return tag }
        }
        return nil
    }

    /// Value of an attribute inside a start tag (entities decoded).
    static func attribute(_ name: String, in tag: Substring) -> String? {
        let pattern = "\\s" + NSRegularExpression.escapedPattern(for: name) + "\\s*=\\s*\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let text = String(tag)
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range), let r = Range(m.range(at: 1), in: text) else { return nil }
        return decodeEntities(String(text[r]))
    }

    /// Inner HTML of the element whose start tag has `className`, up to the matching close tag of the same name.
    static func element(withClass className: String, in html: String) -> Substring? {
        guard let tag = tag(withClass: className, in: html) else { return nil }
        let nameEnd = tag.dropFirst().firstIndex { $0 == " " || $0 == ">" || $0 == "/" } ?? tag.endIndex
        let name = String(tag[tag.index(after: tag.startIndex)..<nameEnd])
        guard !name.isEmpty else { return nil }
        var depth = 1
        var i = tag.endIndex
        while i < html.endIndex, let next = html[i...].firstIndex(of: "<") {
            let rest = html[next...]
            if rest.hasPrefix("</" + name) {
                depth -= 1
                if depth == 0 { return html[tag.endIndex..<next] }
            } else if rest.hasPrefix("<" + name + " ") || rest.hasPrefix("<" + name + ">") {
                depth += 1
            }
            i = html.index(after: next)
        }
        return nil
    }

    /// Picks the URL from a `srcset` that is closest to (but not below) `target` pixels wide, else the widest.
    static func bestSource(srcset: String, target: Int) -> String? {
        let candidates: [(url: String, width: Int)] = srcset.split(separator: ",").compactMap { entry in
            let parts = entry.trimmingCharacters(in: .whitespaces).split(separator: " ")
            guard let url = parts.first else { return nil }
            let width = parts.count > 1 ? Int(parts[1].dropLast()) ?? 0 : 0
            return (String(url), width)
        }
        guard !candidates.isEmpty else { return nil }
        if let fit = candidates.filter({ $0.width >= target }).min(by: { $0.width < $1.width }) { return fit.url }
        return candidates.max(by: { $0.width < $1.width })?.url
    }

    /// Digits in a string such as "111,768 likes" or "Me gusta: 1.234" (nil when there are none).
    static func integer(in text: String) -> Int? {
        let digits = text.filter { $0.isASCII && $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }
}
