import SwiftUI
import AppKit

/// The Stamp design system: warm paper, one ink stroke for every outline, a few bright fills,
/// and a hard offset shadow on things you can press.
/// Values come from the Stamp design system's tokens (light and dark).
enum Stamp {

    // MARK: - Colors

    static let paper = dynamic(light: 0xFAF7F0, dark: 0x171614)
    static let paperRaised = dynamic(light: 0xFFFFFF, dark: 0x22201D)
    static let paperSunk = dynamic(light: 0xF1ECE1, dark: 0x0F0E0D)
    static let ink = dynamic(light: 0x141414, dark: 0xF5F1E8)
    static let inkMuted = dynamic(light: 0x4A4744, dark: 0xC9C2B6)
    static let inkSubtle = dynamic(light: 0x67635D, dark: 0xA39C90)
    static let line = ink
    static let lineSoft = dynamic(light: 0xE2DCCF, dark: 0x34312C)
    static let stampShadow = dynamic(light: 0x141414, dark: 0x8A8378)
    /// Text and icons on any bright fill; dark in both themes
    static let onFill = Color(hex: 0x141414)
    static let tomato = Color(hex: 0xFF6B4A)
    static let tomatoSoft = dynamic(light: 0xFFE1D8, dark: 0x3D2019)
    static let sky = Color(hex: 0x7CC4FF)
    static let skySoft = dynamic(light: 0xDCEFFF, dark: 0x162A3A)
    static let sun = Color(hex: 0xFFD84D)
    static let mint = Color(hex: 0x8FE3B0)
    static let mintSoft = dynamic(light: 0xD9F6E4, dark: 0x14301F)
    static let alert = dynamic(light: 0xB42318, dark: 0xFF8A7A)

    // MARK: - Shape

    static let stroke1: CGFloat = 1.5
    static let stroke2: CGFloat = 2
    static let radiusSm: CGFloat = 6
    static let radiusMd: CGFloat = 10
    static let radiusLg: CGFloat = 16

    enum ShadowSize: CGFloat {
        case none = 0, sm = 2, md = 3, lg = 6
    }

    // MARK: - Type
    // Stamp's own faces aren't bundled, so the rounded system face stands in for the display face.

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static let heading = display(26)
    static let title = display(18)
    static let body = Font.system(size: 14, weight: .medium)
    static let label = Font.system(size: 13, weight: .bold)
    static let small = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 11, weight: .bold)
    static let numeral = Font.system(size: 12, weight: .semibold, design: .monospaced)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Surfaces

extension View {
    /// An ink outline with a hard offset shadow, the Stamp look for anything raised
    func stampSurface(
        fill: Color = Stamp.paperRaised,
        radius: CGFloat = Stamp.radiusMd,
        stroke: CGFloat = Stamp.stroke1,
        shadow: Stamp.ShadowSize = .md
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Stamp.line, lineWidth: stroke)
            )
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(Stamp.stampShadow)
                    .offset(x: shadow.rawValue, y: shadow.rawValue)
            )
    }
}

// MARK: - Button

struct StampButtonStyle: ButtonStyle {
    enum Variant { case `default`, primary, secondary, ghost }
    enum Size { case sm, md, lg }

    var variant: Variant = .default
    var size: Size = .md
    var fullWidth = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shadow: Stamp.ShadowSize = (variant == .ghost || pressed) ? .none : .md
        let offset: CGFloat = pressed && variant != .ghost ? Stamp.ShadowSize.md.rawValue : 0

        return configuration.label
            .font(size == .sm ? Stamp.small.weight(.bold) : Stamp.label)
            .foregroundColor(foreground)
            .padding(.horizontal, size == .sm ? 10 : (size == .lg ? 18 : 14))
            .frame(height: size == .sm ? 28 : (size == .lg ? 42 : 34))
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .modifier(StampButtonBackground(variant: variant, shadow: shadow))
            .offset(x: offset, y: offset)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch variant {
        case .primary, .secondary: return Stamp.onFill
        case .default, .ghost: return Stamp.ink
        }
    }
}

private struct StampButtonBackground: ViewModifier {
    let variant: StampButtonStyle.Variant
    let shadow: Stamp.ShadowSize

    func body(content: Content) -> some View {
        switch variant {
        case .ghost:
            content
        case .primary:
            content.stampSurface(fill: Stamp.tomato, shadow: shadow)
        case .secondary:
            content.stampSurface(fill: Stamp.sky, shadow: shadow)
        case .default:
            content.stampSurface(fill: Stamp.paperRaised, shadow: shadow)
        }
    }
}

extension ButtonStyle where Self == StampButtonStyle {
    static func stamp(_ variant: StampButtonStyle.Variant = .default,
                      size: StampButtonStyle.Size = .md,
                      fullWidth: Bool = false) -> StampButtonStyle {
        StampButtonStyle(variant: variant, size: size, fullWidth: fullWidth)
    }
}

// MARK: - Badge

struct StampBadge: View {
    enum Tone { case neutral, tomato, sky, mint, sun, alert }

    let text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text.uppercased())
            .font(Stamp.caption)
            .tracking(0.4)
            .foregroundColor(tone == .alert ? Stamp.alert : (tone == .neutral ? Stamp.ink : Stamp.onFill))
            .padding(.horizontal, 7)
            .frame(height: 22)
            .stampSurface(fill: fill, radius: Stamp.radiusSm, shadow: .sm)
            .fixedSize()
    }

    private var fill: Color {
        switch tone {
        case .neutral: return Stamp.paperRaised
        case .tomato: return Stamp.tomato
        case .sky: return Stamp.sky
        case .mint: return Stamp.mint
        case .sun: return Stamp.sun
        case .alert: return Stamp.paperRaised
        }
    }
}

// MARK: - Card

struct StampCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(Stamp.title)
                    .foregroundColor(Stamp.ink)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stampSurface(fill: Stamp.paperRaised, radius: Stamp.radiusLg, shadow: .md)
    }
}

// MARK: - Segmented

/// A choice between two to four options: a sunk track with the chosen option stamped on top
struct StampSegmented<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var tint: Color = Stamp.paperRaised
        var id: Value { value }
    }

    var label: String?
    let options: [Option]
    @Binding var selection: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label).font(Stamp.label).foregroundColor(Stamp.ink)
            }
            HStack(spacing: 4) {
                ForEach(options) { option in
                    let isSelected = option.value == selection
                    Button {
                        selection = option.value
                    } label: {
                        Text(option.label)
                            .font(Stamp.label)
                            .foregroundColor(isSelected && option.tint != Stamp.paperRaised ? Stamp.onFill : Stamp.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background {
                                if isSelected {
                                    Color.clear.stampSurface(fill: option.tint, radius: 8, shadow: .sm)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: Stamp.radiusMd).fill(Stamp.paperSunk))
            .overlay(RoundedRectangle(cornerRadius: Stamp.radiusMd).strokeBorder(Stamp.line, lineWidth: Stamp.stroke1))
        }
    }
}

// MARK: - Switch

/// An on/off switch that turns mint and shows a check when on
struct StampSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Stamp.mint : Stamp.paperSunk)
                        .overlay(Capsule().strokeBorder(Stamp.line, lineWidth: Stamp.stroke1))
                        .frame(width: 44, height: 26)
                    Circle()
                        .fill(Stamp.paperRaised)
                        .overlay(Circle().strokeBorder(Stamp.line, lineWidth: Stamp.stroke1))
                        .overlay {
                            if configuration.isOn {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundColor(Stamp.onFill)
                            }
                        }
                        .frame(width: 20, height: 20)
                        .padding(3)
                }
                .animation(.easeOut(duration: 0.12), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

extension ToggleStyle where Self == StampSwitchStyle {
    static var stamp: StampSwitchStyle { StampSwitchStyle() }
}

// MARK: - Fields

extension View {
    /// Stamp look for text fields and editors: raised paper, ink outline, small stamp
    func stampField(error: Bool = false) -> some View {
        self
            .textFieldStyle(.plain)
            .font(Stamp.body)
            .foregroundColor(Stamp.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Stamp.radiusMd).fill(Stamp.paperRaised))
            .overlay(
                RoundedRectangle(cornerRadius: Stamp.radiusMd)
                    .strokeBorder(error ? Stamp.alert : Stamp.line, lineWidth: Stamp.stroke1)
            )
            .background(
                RoundedRectangle(cornerRadius: Stamp.radiusMd)
                    .fill(Stamp.stampShadow)
                    .offset(x: 2, y: 2)
            )
    }
}

/// A labelled field: label above, optional hint or error below
struct StampLabeled<Content: View>: View {
    let label: String
    var hint: String?
    var error: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Stamp.label).foregroundColor(Stamp.ink)
            content
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(Stamp.small)
                    .foregroundColor(Stamp.alert)
            } else if let hint {
                Text(hint).font(Stamp.small).foregroundColor(Stamp.inkSubtle)
            }
        }
    }
}

/// A Stamp-styled pop-up menu for picking one value
struct StampPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    var title: (Value) -> String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    if option == selection {
                        Label(title(option), systemImage: "checkmark")
                    } else {
                        Text(title(option))
                    }
                }
            }
        } label: {
            HStack {
                Text(title(selection))
                    .font(Stamp.body)
                    .foregroundColor(Stamp.ink)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Stamp.ink)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34)
            .stampSurface(fill: Stamp.paperRaised, radius: Stamp.radiusMd, shadow: .sm)
            .contentShape(Rectangle())
        }
        // A plain-button menu draws the custom label as is
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
    }
}
