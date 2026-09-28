import UIKit

extension UIColor {
    /// Couleur CSS envoyée par `nativex.setThemeColor` : `#rgb`, `#rrggbb`, `#rrggbbaa`,
    /// `rgb(r, g, b)` ou `rgba(r, g, b, a)`. `nil` si le format n'est pas reconnu.
    convenience init?(css: String) {
        let text = css.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if text.hasPrefix("#") {
            var hex = String(text.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
            let hasAlpha = hex.count == 8
            let r = (value >> (hasAlpha ? 24 : 16)) & 0xff
            let g = (value >> (hasAlpha ? 16 : 8)) & 0xff
            let b = (value >> (hasAlpha ? 8 : 0)) & 0xff
            let a = hasAlpha ? value & 0xff : 255
            self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
            return
        }

        if text.hasPrefix("rgb"), let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")") {
            let numbers = text[text.index(after: open)..<close]
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
                .compactMap { Double($0) }
            guard numbers.count >= 3 else { return nil }
            let alpha = numbers.count >= 4 ? numbers[3] : 1
            self.init(red: numbers[0] / 255, green: numbers[1] / 255, blue: numbers[2] / 255, alpha: alpha)
            return
        }
        return nil
    }
}
