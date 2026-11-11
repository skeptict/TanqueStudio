import CoreGraphics
import CoreText
import Foundation

/// Turns the sheet's text into the lines the glass screen shows.
enum ScreenTextLayout {
    static let columns = 48
    static let rows = 16

    struct Page: Equatable {
        var lines: [String]
        var cursorRow: Int
        var cursorColumn: Int
    }

    /// Word-wraps to `columns`; a word longer than a line is broken hard.
    static func wrap(_ text: String, columns: Int = columns) -> [String] {
        var lines: [String] = []
        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var current: [Character] = []
            for ch in paragraph {
                current.append(ch)
                guard current.count > columns else { continue }
                if ch == " " {
                    // The space that overflowed becomes the line break.
                    lines.append(String(current.dropLast()))
                    current = []
                } else if let space = current.lastIndex(of: " ") {
                    lines.append(String(current[..<space]))
                    current = Array(current[(space + 1)...])
                } else {
                    lines.append(String(current.dropLast()))
                    current = [ch]
                }
            }
            lines.append(String(current))
        }
        return lines
    }

    /// The last `rows` lines, with the cursor after the final character.
    static func page(for text: String, columns: Int = columns, rows: Int = rows) -> Page {
        var lines = wrap(text, columns: columns)
        if let last = lines.last, last.count >= columns { lines.append("") }
        let visible = Array(lines.suffix(rows))
        return Page(lines: visible, cursorRow: visible.count - 1, cursorColumn: visible.last?.count ?? 0)
    }
}

/// Draws a page as warm amber type on a dark tube.
struct ScreenTextRenderer {
    static let width = 1152
    static let height = 832
    /// Width over height of the image, and so of the screen that carries it.
    static let aspect = Float(width) / Float(height)

    private let font: CTFont
    private let cellWidth: CGFloat
    private let lineHeight: CGFloat
    private let marginX: CGFloat = 48
    private let marginY: CGFloat = 32
    private let amber = CGColor(srgbRed: 1.0, green: 0.70, blue: 0.28, alpha: 1)

    init() {
        let columns = CGFloat(ScreenTextLayout.columns)
        cellWidth = (CGFloat(Self.width) - 2 * marginX) / columns
        lineHeight = (CGFloat(Self.height) - 2 * marginY) / CGFloat(ScreenTextLayout.rows)

        // Size the app's mono face so exactly `columns` glyphs span the screen.
        let probe = CTFontCreateWithName("IBMPlexMono-Regular" as CFString, 100, nil)
        var glyph = CGGlyph(0)
        var zero: UniChar = 0x30
        CTFontGetGlyphsForCharacters(probe, &zero, &glyph, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(probe, .horizontal, &glyph, &advance, 1)
        let perPoint = advance.width > 0 ? advance.width / 100 : 0.6
        font = CTFontCreateWithName("IBMPlexMono-Regular" as CFString, cellWidth / perPoint, nil)
    }

    func image(for page: ScreenTextLayout.Page, showCursor: Bool) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: Self.width, height: Self.height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let full = CGRect(x: 0, y: 0, width: Self.width, height: Self.height)
        ctx.setFillColor(CGColor(srgbRed: 0.055, green: 0.035, blue: 0.02, alpha: 1))
        ctx.fill(full)

        // Phosphor glow.
        ctx.setShadow(offset: .zero, blur: 9, color: amber.copy(alpha: 0.75))

        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): amber,
        ]
        let top = CGFloat(Self.height) - marginY
        for (row, text) in page.lines.enumerated() where !text.isEmpty {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            ctx.textPosition = CGPoint(x: marginX, y: top - CGFloat(row + 1) * lineHeight + lineHeight * 0.28)
            CTLineDraw(line, ctx)
        }

        if showCursor, page.cursorRow >= 0 {
            let x = marginX + CGFloat(page.cursorColumn) * cellWidth
            let y = top - CGFloat(page.cursorRow + 1) * lineHeight + lineHeight * 0.12
            ctx.setFillColor(amber)
            ctx.fill(CGRect(x: x, y: y, width: cellWidth * 0.9, height: lineHeight * 0.78))
        }

        // Faint scanlines so the type reads as a tube, not a printout.
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.16))
        var y = 0
        while y < Self.height {
            ctx.fill(CGRect(x: 0, y: y, width: Self.width, height: 1))
            y += 4
        }
        return ctx.makeImage()
    }
}
