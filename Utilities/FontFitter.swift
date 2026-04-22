import AppKit

/// Picks the largest system font size (down to a floor) at which a translated
/// string will fit inside a given point-space bounding box when wrapped. Used
/// by the in-place translation compositor so translated segments stay inside
/// the masked rectangle of the original text.
enum FontFitter {
    static let minimumPointSize: CGFloat = 8
    static let weight: NSFont.Weight = .medium

    /// - Parameters:
    ///   - text: the translated text to render
    ///   - size: the point-space size of the bounding box
    ///   - color: foreground color (caller picks based on background luminance)
    ///   - startPointSize: the font size to try first; typically derived from
    ///     the original text block's height so translated text matches visually
    static func fit(text: String, in size: CGSize, color: NSColor, startPointSize: CGFloat) -> NSAttributedString {
        let start = max(minimumPointSize, startPointSize)
        var pt = start

        while pt > minimumPointSize {
            if measure(text: text, pointSize: pt, color: color, in: size) {
                return makeAttributedString(text: text, pointSize: pt, color: color)
            }
            pt -= 1
        }
        return makeAttributedString(text: text, pointSize: minimumPointSize, color: color)
    }

    private static func measure(text: String, pointSize: CGFloat, color: NSColor, in size: CGSize) -> Bool {
        let attrs = makeAttributedString(text: text, pointSize: pointSize, color: color)
        let bounding = attrs.boundingRect(
            with: CGSize(width: size.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return bounding.width <= size.width && bounding.height <= size.height
    }

    private static func makeAttributedString(text: String, pointSize: CGFloat, color: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: pointSize, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        return NSAttributedString(string: text, attributes: attrs)
    }
}
