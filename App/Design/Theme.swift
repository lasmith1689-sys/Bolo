import SwiftUI

/// The Ajrakh palette: natural dye sources, as in the prototype. Don't substitute.
enum Palette {
    /// Deep indigo ground.
    static let night = Color(hex: 0x131E33)
    /// Panels.
    static let indigo = Color(hex: 0x1C2C4B)
    /// Hairlines and borders.
    static let rule = Color(hex: 0x33507F)
    /// Madder root: primary action, stamps.
    static let madder = Color(hex: 0xB04A34)
    static let madderLo = Color(hex: 0x8C3826)
    /// Pomegranate yellow: accents, runs, numerals, romanization.
    static let gold = Color(hex: 0xC9922F)
    /// Over-dyed indigo and yellow: the correct state only.
    static let green = Color(hex: 0x4E8265)
    /// Undyed cotton: body text.
    static let cream = Color(hex: 0xEFE4CC)
    /// Secondary text.
    static let dim = Color(hex: 0x96A5BE)
    /// Text on a gold chip.
    static let ink = Color(hex: 0x2A1D05)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Eczar for display (drawn for Indic scripts), Hind Vadodara for body and all Gujarati. Both SIL OFL,
/// bundled and registered through UIAppFonts. Sizes scale with Dynamic Type.
enum Typeface {
    enum EczarWeight: String {
        case regular = "Eczar-Regular"
        case medium = "Eczar-Medium"
        case semibold = "Eczar-SemiBold"
    }

    enum HindWeight: String {
        case regular = "HindVadodara-Regular"
        case medium = "HindVadodara-Medium"
        case semibold = "HindVadodara-SemiBold"
        case bold = "HindVadodara-Bold"
    }

    static func eczar(_ size: CGFloat, _ weight: EczarWeight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }

    /// Romanization: the working surface, in slanted Eczar and gold.
    static func roman(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Eczar-MediumItalic", size: size, relativeTo: style)
    }

    static func hind(_ size: CGFloat, _ weight: HindWeight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }

    /// Gujarati script. Hind Vadodara has no Gujarati digits, so numerals fall back to the system face.
    static func gujarati(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        hind(size, .semibold, relativeTo: style)
    }
}

/// Small-caps style labels ("THE BLOCKS", "WHAT DOES THIS MEAN?").
struct TrackedLabel: View {
    let text: String
    var size: CGFloat = 11
    var tracking: CGFloat = 0.22
    var color: Color = Palette.dim

    var body: some View {
        Text(text.uppercased())
            .font(Typeface.eczar(size, .semibold, relativeTo: .caption))
            .tracking(size * tracking)
            .foregroundStyle(color)
    }
}
