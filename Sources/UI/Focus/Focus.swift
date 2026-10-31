import SwiftUI
import AppKit

/// The Focus design system. Light only.
/// Tokens mirror docs/design/focus-tokens.json; the guide is docs/design/FOCUS.md.
enum Focus {

    // MARK: - Surfaces

    static let canvas = Color(hex: 0xFBFBFA)
    static let sidebar = Color(hex: 0xF3F3F1)
    static let raised = Color(hex: 0xFFFFFF)
    static let hover = Color(hex: 0xEEEEEB)
    /// The keyboard-selected row or card (↑/↓): a step darker than hover
    static let selected = Color(hex: 0xE8E8E4)
    static let scrim = Color(hex: 0x18181B).opacity(0.14)

    // MARK: - Text

    static let text = Color(hex: 0x18181B)
    static let text2 = Color(hex: 0x4F4F58)
    static let text3 = Color(hex: 0x6E6E78)

    // MARK: - Lines

    static let hairline = Color.black.opacity(0.08)
    static let lineStrong = Color.black.opacity(0.14)

    // MARK: - Signals

    /// A running timer, and the one primary button. Nothing else uses it.
    static let live = Color(hex: 0xF0532F)
    static let liveText = Color(hex: 0xC93C1B)
    static let liveSoft = Color(hex: 0xF0532F).opacity(0.08)
    static let liveGlow = Color(hex: 0xF0532F).opacity(0.35)
    static let onLive = Color(hex: 0x1A0A05)
    static let done = Color(hex: 0x6D5AE6)
    static let progress = Color(hex: 0xB76E00)
    static let ok = Color(hex: 0x15803D)
    static let risk = Color(hex: 0xDC2626)
    static let ringTrack = Color(hex: 0xE4E4E0)
    /// A brief wash on a task just added (fades out)
    static let justAdded = Color(hex: 0xE0A020).opacity(0.16)

    /// Project tile palette, in the order new projects get them
    static let projectPalette: [UInt32] = [0xFF6B4A, 0x4EA1F5, 0x2DBE7A, 0xE0A020, 0x8B5CF6, 0xEC4899, 0x14B8A6, 0x64748B]

    /// Workflow status colors: the three signal tones (text3 gray, progress, done) first, then the
    /// project palette. Statuses tint their icon, board column and dropdown with it.
    static let statusPalette: [UInt32] = [0x6E6E78, 0xB76E00, 0x6D5AE6, 0x4EA1F5, 0x14B8A6, 0x2DBE7A, 0xE0A020,
                                          0xFF6B4A, 0xEC4899, 0x8B5CF6, 0xDC2626]

    // MARK: - Type

    static let taskTitle = Font.system(size: 26, weight: .semibold)
    static let pageTitle = Font.system(size: 20, weight: .semibold)
    static let header = Font.system(size: 15, weight: .semibold)
    /// Task titles in rows and cards: regular weight
    static let row = Font.system(size: 13.5)
    /// Running task titles, and project names in the menu: medium
    static let rowStrong = Font.system(size: 13.5, weight: .medium)
    /// Group and column headings in lists and the board ("To do 4", "Sprint 3")
    static let groupTitle = Font.system(size: 13.5, weight: .semibold)
    static let body = Font.system(size: 13.5)
    static let control = Font.system(size: 13, weight: .medium)
    static let meta = Font.system(size: 12.5)
    static let caption = Font.system(size: 11, weight: .semibold)
    static let clock = Font.system(size: 13, weight: .semibold).monospacedDigit()
    static let clockLarge = Font.system(size: 26, weight: .semibold).monospacedDigit()
    static let mono = Font.system(size: 12.5, design: .monospaced)

    // MARK: - Shape and size

    static let radiusTag: CGFloat = 6
    static let radiusControl: CGFloat = 7
    static let radiusCard: CGFloat = 10
    static let radiusPanel: CGFloat = 12

    static let rowHeight: CGFloat = 46
    static let controlHeight: CGFloat = 30
    static let tagHeight: CGFloat = 22
    static let sidebarWidth: CGFloat = 240
    static let inspectorWidth: CGFloat = 320
    static let taskPanelWidth: CGFloat = 860
    static let menuWidth: CGFloat = 360
    /// The floating selection bar (FocusActionBar)
    static let actionBarHeight: CGFloat = 44

    // MARK: - Motion

    static let hoverAnimation = Animation.easeOut(duration: 0.12)
    static let menuAnimation = Animation.easeOut(duration: 0.15)
    static let sheetAnimation = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22)

    // MARK: - Tints

    /// Colors for a tinted control such as the status or priority dropdown
    struct Tint: Equatable {
        let icon: Color
        let fill: Color
        let text: Color
        let border: Color
    }

    static let neutralTint = Tint(icon: text3, fill: Color(hex: 0xF1F1EE), text: text2, border: Color(hex: 0xE2E2DE))
    static let progressTint = Tint(icon: progress, fill: Color(hex: 0xFFF4E0), text: Color(hex: 0x8A5300), border: Color(hex: 0xF3DDB0))
    static let doneTint = Tint(icon: done, fill: Color(hex: 0xEFECFD), text: Color(hex: 0x4B3BB8), border: Color(hex: 0xD9D3F8))
    static let riskTint = Tint(icon: risk, fill: Color(hex: 0xFDECEC), text: Color(hex: 0xB91C1C), border: Color(hex: 0xF6CFCF))

    /// A light fill, border and darker text of any color (milestone chips).
    static func colorTint(_ hex: UInt32) -> Tint {
        let c = Color(hex: hex)
        return Tint(icon: c, fill: c.opacity(0.10), text: Color(hex: hex, darkenedBy: 0.35), border: c.opacity(0.30))
    }

    /// The tint of a status dropdown for a status color. The three signal tones keep their own
    /// tints; any other color gets a light fill and border of itself.
    static func statusTint(_ hex: UInt32) -> Tint {
        switch hex {
        case 0x6E6E78: return neutralTint
        case 0xB76E00: return progressTint
        case 0x6D5AE6: return doneTint
        case 0xDC2626: return riskTint
        default:
            let c = Color(hex: hex)
            return Tint(icon: c, fill: c.opacity(0.10), text: Color(hex: hex, darkenedBy: 0.35), border: c.opacity(0.30))
        }
    }

    /// Formats seconds as a clock: 1:38:08
    static func clockString(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// Formats minutes as an estimate: 45m, 2h, 2h 30m
    static func durationString(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

// MARK: - Status and priority (visual kinds; the task model maps onto these)

/// How a status icon is drawn, from its category: not started, started, done or canceled.
enum FocusStatusKind: CaseIterable {
    case todo, inProgress, done, canceled

    var tint: Focus.Tint {
        switch self {
        case .todo, .canceled: return Focus.neutralTint
        case .inProgress: return Focus.progressTint
        case .done: return Focus.doneTint
        }
    }

    /// The color when the status has none of its own
    var defaultColor: Color {
        switch self {
        case .todo, .canceled: return Focus.text3
        case .inProgress: return Focus.progress
        case .done: return Focus.done
        }
    }
}

enum FocusPriorityLevel: CaseIterable {
    case low, medium, high

    var bars: Int {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    var tint: Focus.Tint {
        switch self {
        case .low: return Focus.neutralTint
        case .medium: return Focus.progressTint
        case .high: return Focus.riskTint
        }
    }
}

/// Open circle, half-filled circle, filled circle with a check, or filled circle with an ×,
/// in the status's color (the category's signal color when nil).
struct FocusStatusIcon: View {
    let kind: FocusStatusKind
    var color: Color?
    var size: CGFloat = 16

    init(kind: FocusStatusKind, color: Color? = nil, size: CGFloat = 16) {
        self.kind = kind
        self.color = color
        self.size = size
    }

    var body: some View {
        let tone = color ?? kind.defaultColor
        ZStack {
            switch kind {
            case .todo:
                Circle().strokeBorder(tone, lineWidth: size * 0.14)
            case .inProgress:
                Circle().strokeBorder(tone, lineWidth: size * 0.14)
                HalfDisc().fill(tone).padding(size * 0.25)
            case .done:
                Circle().fill(tone)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundColor(.white)
            case .canceled:
                Circle().fill(tone.opacity(0.75))
                Image(systemName: "xmark")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private struct HalfDisc: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                     startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            p.closeSubpath()
            return p
        }
    }
}

/// Three bars; the unused ones fade to 25%
struct FocusPriorityBars: View {
    let level: FocusPriorityLevel
    var colored = true

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(colored ? level.tint.icon : Focus.text2)
                    .frame(width: 3, height: [5, 8, 12][i])
                    .opacity(i < level.bars ? 1 : 0.25)
            }
        }
        .frame(width: 15, height: 12, alignment: .bottomLeading)
        .accessibilityHidden(true)
    }
}

// MARK: - Project tile

struct FocusProjectTile: View {
    let name: String
    let colorHex: UInt32
    var size: CGFloat = 18

    var body: some View {
        let color = Color(hex: colorHex)
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.56, weight: .bold))
            .foregroundColor(color)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28).fill(color.opacity(0.18)))
            .accessibilityHidden(true)
    }
}

/// Pulsing dot next to anything with a running timer
struct FocusLiveDot: View {
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(Focus.live)
            .frame(width: 6, height: 6)
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityLabel("Running")
    }
}

// MARK: - Timer ring

/// The signature control: a play/pause button whose ring fills toward the expected time
struct FocusTimerRing: View {
    /// Spent ÷ expected; above 1 means over the estimate
    let progress: Double
    let isRunning: Bool
    var size: CGFloat = 32
    var label: String = "Timer"
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                ring(lineWidth: 2.5)
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundColor(isRunning ? Focus.live : Focus.text2)
                    .offset(x: isRunning ? 0 : size * 0.03)
            }
            .frame(width: size, height: size)
            .background(Circle().fill(hovering ? Focus.hover : .clear))
            .shadow(color: isRunning ? Focus.liveGlow : .clear, radius: 5)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(isRunning ? "Pause \(label)" : "Start \(label)")
    }

    @ViewBuilder
    private func ring(lineWidth: CGFloat) -> some View {
        let over = progress > 1 && !isRunning
        Circle()
            .inset(by: size * 0.094)
            .stroke(over ? Focus.risk : Focus.ringTrack, lineWidth: lineWidth)
        Circle()
            .inset(by: size * 0.094)
            .trim(from: 0, to: min(1, max(0, progress)))
            .stroke(isRunning ? Focus.live : Focus.text2, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .opacity(over ? 0 : 1)
    }
}

/// The 150pt ring in the task panel: clock inside, big pause or play overlay on hover, click to toggle
struct FocusLargeTimerRing: View {
    let progress: Double
    let isRunning: Bool
    let clock: String
    let caption: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().inset(by: 8).stroke(Focus.ringTrack, lineWidth: 8)
                Circle()
                    .inset(by: 8)
                    .trim(from: 0, to: min(1, max(0, progress)))
                    .stroke(isRunning ? Focus.live : (progress > 1 ? Focus.risk : Focus.text2),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(clock)
                        .font(Focus.clockLarge)
                        .tracking(-0.8)
                        .foregroundColor(isRunning ? Focus.liveText : Focus.text)
                    Text(caption).font(.system(size: 12)).foregroundColor(Focus.text3)
                }
                Circle()
                    .inset(by: 12)
                    .fill(Color.white.opacity(0.88))
                    .overlay(
                        Image(systemName: isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 46, weight: .bold))
                            .foregroundColor(isRunning ? Focus.live : Focus.text)
                    )
                    .opacity(hovering ? 1 : 0)
            }
            .frame(width: 150, height: 150)
            .shadow(color: isRunning ? Focus.liveGlow : .clear, radius: 10)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Focus.hoverAnimation) { hovering = h } }
        .accessibilityLabel(isRunning ? "Pause timer" : "Start timer")
    }
}

// MARK: - Buttons

struct FocusButtonStyle: ButtonStyle {
    enum Variant { case standard, primary, ghost }

    var variant: Variant = .standard
    var fullWidth = false
    /// 8pt side padding instead of 12, for rows of short buttons in narrow popovers (−15m, +5m)
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        FocusButtonBody(configuration: configuration, variant: variant, fullWidth: fullWidth, compact: compact)
    }
}

private struct FocusButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let variant: FocusButtonStyle.Variant
    let fullWidth: Bool
    let compact: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(variant == .primary ? Focus.control.weight(.semibold) : Focus.control)
            .foregroundColor(variant == .primary ? Focus.onLive : Focus.text)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, compact ? 8 : 12)
            .frame(height: Focus.controlHeight)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: Focus.radiusControl)
                    .strokeBorder(variant == .standard ? Focus.lineStrong : .clear, lineWidth: 1)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }

    private var fill: Color {
        switch variant {
        case .primary: return hovering ? Focus.live.opacity(0.9) : Focus.live
        case .standard: return hovering ? Focus.hover : Focus.raised
        case .ghost: return hovering ? Focus.hover : .clear
        }
    }
}

extension ButtonStyle where Self == FocusButtonStyle {
    static func focus(_ variant: FocusButtonStyle.Variant = .standard, fullWidth: Bool = false,
                      compact: Bool = false) -> FocusButtonStyle {
        FocusButtonStyle(variant: variant, fullWidth: fullWidth, compact: compact)
    }
}

/// A borderless 20–30pt icon button
struct FocusIconButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = 28
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundColor(Focus.text2)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(hovering ? Focus.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Fields

extension View {
    /// 30pt field look for text fields and pickers
    func focusField(focused: Bool = false) -> some View {
        self
            .textFieldStyle(.plain)
            .font(Focus.control)
            .foregroundColor(Focus.text)
            .padding(.horizontal, 8)
            .frame(height: Focus.controlHeight)
            .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(Focus.raised))
            .overlay(
                RoundedRectangle(cornerRadius: Focus.radiusControl)
                    .strokeBorder(focused ? Focus.lineStrong : Focus.hairline, lineWidth: 1)
            )
    }

    /// Raised panel with a hairline border and 12 radius
    func focusPanel(radius: CGFloat = Focus.radiusPanel) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius).fill(Focus.raised))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Focus.hairline, lineWidth: 1))
    }

    /// Floating menu surface
    func focusMenuSurface() -> some View {
        self
            .padding(4)
            .background(RoundedRectangle(cornerRadius: Focus.radiusCard).fill(Focus.raised))
            .overlay(RoundedRectangle(cornerRadius: Focus.radiusCard).strokeBorder(Focus.lineStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.14), radius: 14, y: 10)
            .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
    }
}

// MARK: - Pointer

extension View {
    /// Shows the pointing-hand cursor while hovering, for things that open on click (task titles).
    func focusPointerCursor() -> some View {
        modifier(FocusPointerCursor())
    }
}

private struct FocusPointerCursor: ViewModifier {
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside, !pushed {
                    NSCursor.pointingHand.push()
                    pushed = true
                } else if !inside, pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onDisappear {
                if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}

// MARK: - Calendar

/// A month calendar for date popovers, replacing the small system one: month and year with
/// ‹ › and Today, weekday initials, then 36×32 day cells. The selected day is filled, today has
/// a ring, days of the next and previous month are faint and still clickable.
struct FocusCalendar: View {
    /// The selected day, if any
    let selection: Date?
    let select: (Date) -> Void

    @State private var month: Date

    init(selection: Date?, select: @escaping (Date) -> Void) {
        self.selection = selection
        self.select = select
        _month = State(initialValue: Self.calendar.startOfMonth(selection ?? Date()))
    }

    private static var calendar: Calendar { Calendar.current }
    static let cellWidth: CGFloat = 36
    static let cellHeight: CGFloat = 32

    var body: some View {
        VStack(spacing: 6) {
            header
            HStack(spacing: 0) {
                ForEach(Self.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(Focus.caption)
                        .foregroundColor(Focus.text3)
                        .frame(width: Self.cellWidth, height: 20)
                }
            }
            VStack(spacing: 2) {
                ForEach(Self.weeks(of: month), id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(week, id: \.self) { day in
                            FocusCalendarDay(
                                day: day,
                                inMonth: Self.calendar.isDate(day, equalTo: month, toGranularity: .month),
                                isSelected: selection.map { Self.calendar.isDate($0, inSameDayAs: day) } ?? false,
                                isToday: Self.calendar.isDateInToday(day)
                            ) { select(day) }
                        }
                    }
                }
            }
        }
        .fixedSize()
    }

    private var header: some View {
        HStack(spacing: 2) {
            Text(Self.monthTitle(month))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Focus.text)
                .padding(.leading, 6)
            Spacer(minLength: 8)
            Button("Today") { withAnimation(Focus.hoverAnimation) { month = Self.calendar.startOfMonth(Date()) } }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Focus.text2)
                .padding(.horizontal, 6)
            stepButton("chevron.left", label: "Previous month", by: -1)
            stepButton("chevron.right", label: "Next month", by: 1)
        }
        .frame(height: 30)
    }

    private func stepButton(_ icon: String, label: String, by offset: Int) -> some View {
        FocusCalendarStepButton(icon: icon) {
            if let next = Self.calendar.date(byAdding: .month, value: offset, to: month) {
                month = Self.calendar.startOfMonth(next)
            }
        }
        .accessibilityLabel(label)
    }

    /// Weekday initials in the user's order (Su Mo … or Mo Tu …)
    static var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The month's weeks, each seven days, padded with the neighbouring months' days.
    static func weeks(of month: Date) -> [[Date]] {
        let cal = calendar
        let start = cal.startOfMonth(month)
        let lead = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -lead, to: start),
              let days = cal.range(of: .day, in: .month, for: start)?.count else { return [] }
        let weekCount = Int((Double(lead + days) / 7).rounded(.up))
        return (0..<weekCount).map { week in
            (0..<7).compactMap { cal.date(byAdding: .day, value: week * 7 + $0, to: gridStart) }
        }
    }

    static func monthTitle(_ month: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: month)
    }
}

private struct FocusCalendarDay: View {
    let day: Date
    let inMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(size: 13, weight: isSelected || isToday ? .semibold : .regular).monospacedDigit())
                .foregroundColor(isSelected ? .white : (inMonth ? Focus.text : Focus.text3.opacity(0.55)))
                .frame(width: FocusCalendar.cellWidth - 2, height: FocusCalendar.cellHeight)
                .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(fill))
                .overlay(
                    RoundedRectangle(cornerRadius: Focus.radiusControl)
                        .strokeBorder(isToday && !isSelected ? Focus.lineStrong : .clear, lineWidth: 1)
                )
                .frame(width: FocusCalendar.cellWidth)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(DateFormatter.localizedString(from: day, dateStyle: .full, timeStyle: .none))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fill: Color {
        if isSelected { return Focus.text }
        return hovering ? Focus.hover : .clear
    }
}

private struct FocusCalendarStepButton: View {
    let icon: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Focus.text2)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(hovering ? Focus.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private extension Calendar {
    func startOfMonth(_ date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}

// MARK: - Column header

/// One column label over a table of rows: caption type, text3, with a sort arrow when active.
/// Pass `action` to make it clickable (sorting); without it it's a plain label.
struct FocusColumnHeader: View {
    let title: String
    var alignment: Alignment = .leading
    /// nil: not sorted by this column; true/false: ascending/descending
    var sortAscending: Bool?
    var action: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .help("Sort by \(title.lowercased())")
                .accessibilityLabel("Sort by \(title)")
                .accessibilityValue(sortAscending.map { $0 ? "Ascending" : "Descending" } ?? "")
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 3) {
            Text(title.uppercased())
                .font(Focus.caption)
                .tracking(0.5)
                .lineLimit(1)
            if let sortAscending {
                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .foregroundColor(sortAscending != nil || hovering ? Focus.text : Focus.text3)
        .frame(maxWidth: .infinity, alignment: alignment)
        .frame(height: 28)
        .contentShape(Rectangle())
    }
}

/// Uppercase group label
struct FocusCaption: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Focus.caption)
            .tracking(0.5)
            .foregroundColor(Focus.text3)
    }
}

/// 22pt tag; risk turns it red
struct FocusTag: View {
    let text: String
    var systemImage: String?
    var risk = false

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
            }
            Text(text).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .foregroundColor(risk ? Focus.risk : Focus.text2)
        .padding(.horizontal, 7)
        .frame(height: Focus.tagHeight)
        .overlay(RoundedRectangle(cornerRadius: Focus.radiusTag).strokeBorder(risk ? Focus.risk : Focus.hairline, lineWidth: 1))
        .fixedSize()
    }
}

/// Keyboard hint chip, e.g. "esc"
struct FocusKey: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Focus.text3)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Focus.lineStrong, lineWidth: 1))
    }
}

// MARK: - Segmented tabs

/// Sidebar-colored track; the chosen tab is raised
struct FocusTabs<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(selected ? Focus.text : Focus.text2)
                        .padding(.horizontal, 11)
                        .frame(height: 24)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Focus.raised)
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Focus.hairline, lineWidth: 1))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Focus.sidebar))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Focus.hairline, lineWidth: 1))
    }
}

// MARK: - Tinted dropdown

/// Field-sized dropdown with an icon and a tint per value (status, priority)
struct FocusTintedPicker<Value: Hashable, Icon: View>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    let tint: (Value) -> Focus.Tint
    @ViewBuilder let icon: (Value) -> Icon
    var accessibilityName: String = ""

    @State private var open = false

    var body: some View {
        let t = tint(selection)
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 8) {
                icon(selection)
                Text(title(selection)).font(Focus.control).foregroundColor(t.text)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(t.text.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: Focus.controlHeight, maxHeight: Focus.controlHeight)
            .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(t.fill))
            .overlay(RoundedRectangle(cornerRadius: Focus.radiusControl).strokeBorder(t.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(accessibilityName): \(title(selection))")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                ForEach(options, id: \.self) { option in
                    FocusMenuItem(isSelected: option == selection) {
                        selection = option
                        open = false
                    } label: {
                        icon(option)
                        Text(title(option)).font(Focus.control).foregroundColor(Focus.text)
                    }
                }
            }
            .padding(4)
            .frame(width: 200)
            .background(Focus.raised)
        }
    }
}

/// One row in a Focus menu, with a check when selected
struct FocusMenuItem<Label: View>: View {
    var isSelected = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                label()
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Focus.text2)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(hovering ? Focus.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Plain field-sized dropdown for one value (milestone, sprint, expected time, model)
struct FocusPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

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
                Text(title(selection)).font(Focus.control).foregroundColor(Focus.text).lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Focus.text3)
            }
            .focusField()
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Switch

/// On/off switch: done-purple when on
struct FocusSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Focus.done : Focus.ringTrack)
                        .frame(width: 32, height: 18)
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                        .frame(width: 14, height: 14)
                        .padding(2)
                }
                .animation(Focus.hoverAnimation, value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

extension ToggleStyle where Self == FocusSwitchStyle {
    static var focus: FocusSwitchStyle { FocusSwitchStyle() }
}

// MARK: - Row

/// 46pt row with hover; place inside a focusPanel and separate with FocusDivider.
/// `highlighted` is the running tint; `selected` is the keyboard selection (a 2pt `text2` bar on the left).
struct FocusRow<Content: View>: View {
    var highlighted = false
    var selected = false
    @ViewBuilder let content: () -> Content

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) { content() }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .frame(height: Focus.rowHeight)
            .background(background)
            .overlay(alignment: .leading) {
                if selected { Rectangle().fill(Focus.text2).frame(width: 2) }
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }

    private var background: Color {
        if highlighted { return Focus.liveSoft }
        if selected { return Focus.selected }
        return hovering ? Focus.hover : .clear
    }
}

struct FocusDivider: View {
    var body: some View { Rectangle().fill(Focus.hairline).frame(height: 1) }
}

// MARK: - App chrome

/// The FlowMate app tile: an "F" on the live color
struct FocusAppTile: View {
    var size: CGFloat = 22

    var body: some View {
        Text("F")
            .font(.system(size: size * 0.55, weight: .bold))
            .foregroundColor(Focus.onLive)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27).fill(Focus.live))
            .accessibilityHidden(true)
    }
}

/// Sidebar navigation item: hover fill, raised with a hairline when selected
struct FocusSidebarItem<Label: View>: View {
    let selected: Bool
    /// The keyboard is on this item (⌘0 in the tasks window): a focus ring
    var focused = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { label() }
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(selected || hovering ? Focus.text : Focus.text2)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Focus.radiusControl)
                        .fill(selected ? Focus.raised : (hovering ? Focus.hover : .clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Focus.radiusControl)
                        .strokeBorder(focused ? Focus.text3 : (selected ? Focus.hairline : .clear), lineWidth: focused ? 1.5 : 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A quiet status: a small colored dot and a short meta label ("Ollama ready")
struct FocusStatusLabel: View {
    enum Tone { case ok, pending, risk }

    let text: String
    var tone: Tone = .ok

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 12)).foregroundColor(Focus.text3).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch tone {
        case .ok: return Focus.ok
        case .pending: return Focus.progress
        case .risk: return Focus.risk
        }
    }
}

/// A risk-tinted notice with an optional fix button
struct FocusNotice: View {
    let text: String
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Focus.risk)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundColor(Focus.riskTint.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.focus())
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Focus.radiusCard).fill(Focus.riskTint.fill))
        .overlay(RoundedRectangle(cornerRadius: Focus.radiusCard).strokeBorder(Focus.riskTint.border, lineWidth: 1))
    }
}

/// A label above a field, with an optional hint or error below
struct FocusLabeled<Content: View>: View {
    let label: String
    var hint: String?
    var error: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Focus.control).foregroundColor(Focus.text2)
            content()
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundColor(Focus.risk)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let hint {
                Text(hint).font(.system(size: 12)).foregroundColor(Focus.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A titled panel for settings-style pages: header row, then content, in a raised panel
struct FocusSection<Content: View, Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Focus.header).foregroundColor(Focus.text)
                    if let subtitle {
                        Text(subtitle).font(Focus.meta).foregroundColor(Focus.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                accessory()
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusPanel()
    }
}

extension FocusSection where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, subtitle: subtitle, accessory: { EmptyView() }, content: content)
    }
}

extension View {
    /// Multi-line text area look (TextEditor): raised, hairline, card radius
    func focusTextArea(focused: Bool = false) -> some View {
        self
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: Focus.radiusCard).fill(Focus.raised))
            .overlay(
                RoundedRectangle(cornerRadius: Focus.radiusCard)
                    .strokeBorder(focused ? Focus.lineStrong : Focus.hairline, lineWidth: 1)
            )
    }

    /// Forces the light Focus look on a window's content
    func focusLight() -> some View {
        preferredColorScheme(.light)
    }
}

// MARK: - Search field

/// 30pt search field with a magnifier, a clear × and an optional shortcut hint (⌘F).
/// Esc clears the text, then leaves the field.
struct FocusSearchField: View {
    let placeholder: String
    @Binding var text: String
    var shortcutHint: String?
    var focused: FocusState<Bool>.Binding
    /// Return in the field, e.g. to move to the results
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Focus.text3)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(Focus.text)
                .focused(focused)
                .onSubmit(onSubmit)
                .onExitCommand {
                    if text.isEmpty { focused.wrappedValue = false } else { text = "" }
                }
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Focus.text3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            } else if let shortcutHint, !focused.wrappedValue {
                FocusKey(text: shortcutHint)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 6)
        .frame(height: Focus.controlHeight)
        .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(Focus.raised))
        .overlay(
            RoundedRectangle(cornerRadius: Focus.radiusControl)
                .strokeBorder(focused.wrappedValue ? Focus.lineStrong : Focus.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Filter chip

/// A 30pt filter or menu button. Inactive: hairline, `text2`, a chevron.
/// Active: raised with `lineStrong`, `text`, and an × that clears it (`clear`).
struct FocusFilterChip: View {
    let title: String
    var value: String?
    var systemImage: String?
    var isActive = false
    let action: () -> Void
    var clear: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 6) {
                    if let systemImage {
                        Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                    }
                    // An empty title leaves just the icon and value (compact filter bar)
                    if !title.isEmpty {
                        Text(title).foregroundColor(Focus.text2)
                    }
                    if let value {
                        Text(value).foregroundColor(Focus.text).lineLimit(1)
                    }
                    if clear == nil || !isActive {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Focus.text3)
                    }
                }
                .font(Focus.control)
                .foregroundColor(Focus.text2)
                .padding(.leading, 10)
                .padding(.trailing, isActive && clear != nil ? 4 : 10)
                .frame(height: Focus.controlHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isActive, let clear {
                Button(action: clear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(Focus.text3)
                        .frame(width: 22, height: Focus.controlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove \(title.lowercased()) filter")
                .accessibilityLabel("Remove \(title) filter")
            }
        }
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: Focus.radiusControl)
                .fill(isActive ? Focus.raised : (hovering ? Focus.hover : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Focus.radiusControl)
                .strokeBorder(isActive ? Focus.lineStrong : Focus.hairline, lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }
}

// MARK: - Popover menus

/// A Focus menu inside a popover: 4pt padding on the raised fill. Put FocusMenuItems in it,
/// with FocusMenuSection headers between groups.
struct FocusPopoverMenu<Content: View>: View {
    var width: CGFloat = 220
    var maxHeight: CGFloat?
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if let maxHeight {
                ScrollView { VStack(alignment: .leading, spacing: 0) { content() }.padding(4) }
                    .frame(maxHeight: maxHeight)
            } else {
                VStack(alignment: .leading, spacing: 0) { content() }.padding(4)
            }
        }
        .frame(width: width)
        .background(Focus.raised)
        .focusLight()
    }
}

/// A caption above a group of menu items, with a hairline above when not first.
struct FocusMenuSection: View {
    let title: String
    var first = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !first { FocusDivider().padding(.vertical, 4) }
            FocusCaption(text: title)
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 4)
        }
    }
}

// MARK: - Editable cell

/// A table cell that opens a small editor on click: no chrome at rest, a hairline box on hover.
struct FocusCellButton<Label: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Focus.radiusTag)
                        .fill(hovering ? Focus.raised : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Focus.radiusTag)
                        .strokeBorder(hovering ? Focus.lineStrong : .clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -5)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - Toast

/// A bottom toast: raised, `lineStrong`, menu shadow. One message, an optional action
/// ("Undo") with its key hint, and a close ×. The caller places and times it.
struct FocusToast: View {
    let message: String
    var actionTitle: String?
    var actionKey: String?
    var action: () -> Void = {}
    /// A second action before the first, e.g. "Open" next to "Undo"
    var secondaryTitle: String?
    var secondaryAction: () -> Void = {}
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(message)
                .font(Focus.body)
                .foregroundColor(Focus.text)
                .lineLimit(1)
            if let secondaryTitle {
                Rectangle().fill(Focus.hairline).frame(width: 1, height: 16)
                Button(action: secondaryAction) {
                    Text(secondaryTitle).font(Focus.control).foregroundColor(Focus.text)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FocusToastButtonStyle())
            }
            if let actionTitle {
                Rectangle().fill(Focus.hairline).frame(width: 1, height: 16)
                Button(action: action) {
                    HStack(spacing: 6) {
                        Text(actionTitle).font(Focus.control).foregroundColor(Focus.text)
                        if let actionKey { FocusKey(text: actionKey) }
                    }
                    // The actions never truncate; a long message does instead
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(FocusToastButtonStyle())
            }
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Focus.text3)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: Focus.radiusCard).fill(Focus.raised))
        .overlay(RoundedRectangle(cornerRadius: Focus.radiusCard).strokeBorder(Focus.lineStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 10)
        .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Action bar

/// A floating bar at the bottom center for actions on a selection ("3 selected · Status · … · Delete"):
/// raised, `lineStrong`, radius 10, the menu shadow, 44 tall. Holds FocusBarButtons.
struct FocusActionBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 2) { content() }
            .padding(.horizontal, 6)
            .frame(height: Focus.actionBarHeight)
            .background(RoundedRectangle(cornerRadius: Focus.radiusCard).fill(Focus.raised))
            .overlay(RoundedRectangle(cornerRadius: Focus.radiusCard).strokeBorder(Focus.lineStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.14), radius: 14, y: 10)
            .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
            .accessibilityElement(children: .contain)
    }
}

/// A 30pt ghost button for FocusActionBar: an optional icon, control type, a hover fill, and an
/// optional chevron when it opens a menu. `risk` colors it for Delete.
struct FocusBarButton: View {
    let title: String
    var systemImage: String?
    var menu = false
    var risk = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                if menu {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Focus.text3)
                }
            }
            .font(Focus.control)
            .foregroundColor(risk ? Focus.risk : Focus.text)
            .padding(.horizontal, 9)
            .frame(height: Focus.controlHeight)
            .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(hovering ? Focus.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
    }
}

/// A 1px hairline between groups in a FocusActionBar or toast.
struct FocusBarSeparator: View {
    var body: some View {
        Rectangle().fill(Focus.hairline).frame(width: 1, height: 18).padding(.horizontal, 4)
    }
}

private struct FocusToastButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FocusToastButtonBody(configuration: configuration)
    }

    private struct FocusToastButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(hovering ? Focus.hover : .clear))
                .opacity(configuration.isPressed ? 0.8 : 1)
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - Shortcut row

/// One line of a shortcuts list: a label and its keys as FocusKey chips.
struct FocusShortcutRow: View {
    let label: String
    let keys: [String]

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(Focus.body).foregroundColor(Focus.text2)
            Spacer(minLength: 12)
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { FocusKey(text: $0) }
            }
        }
        .frame(height: 26)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Breadcrumbs

/// A clickable breadcrumb in a side panel header: `text2`, and a hover fill with `text` when hovered.
/// `muted` (`text3`) is for an empty value such as "No milestone".
/// "‹ Atlas": returns to the panel the current one was opened from. Same look as a crumb.
struct FocusBackButton: View {
    let title: String
    var help: String = ""
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                Text(title).font(Focus.body).lineLimit(1)
            }
            .foregroundColor(hovering ? Focus.text : Focus.text2)
            .padding(.horizontal, 7)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: Focus.radiusTag).fill(hovering ? Focus.hover : Focus.sidebar))
            .overlay(RoundedRectangle(cornerRadius: Focus.radiusTag).strokeBorder(Focus.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .focusPointerCursor()
        .help(help)
        .accessibilityLabel(help.isEmpty ? "Back to \(title)" : help)
    }
}

struct FocusCrumb: View {
    let text: String
    var help: String = ""
    var muted = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(Focus.body)
                .foregroundColor(hovering ? Focus.text : (muted ? Focus.text3 : Focus.text2))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: Focus.radiusTag).fill(hovering ? Focus.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .focusPointerCursor()
        .help(help)
        .accessibilityLabel(help.isEmpty ? text : "\(text). \(help)")
    }
}

/// The current (last) breadcrumb: plain `text`, not clickable.
struct FocusCrumbCurrent: View {
    let text: String

    var body: some View {
        Text(text).font(Focus.body.weight(.medium)).foregroundColor(Focus.text).lineLimit(1).padding(.horizontal, 6)
    }
}

/// "›" between breadcrumbs
struct FocusCrumbSeparator: View {
    var body: some View {
        Text("›").font(Focus.body).foregroundColor(Focus.text3).accessibilityHidden(true)
    }
}

// MARK: - Progress bar

/// A 4pt progress bar on `ringTrack`, filled with `done` (milestones, past sprints).
struct FocusProgressBar: View {
    /// 0…1
    let fraction: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Focus.ringTrack)
                Capsule().fill(Focus.done)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
                    .opacity(fraction > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((max(0, min(1, fraction)) * 100).rounded())) percent")
    }
}

// MARK: - Color swatches

/// The project palette (or another, such as Focus.statusPalette) as 20pt circles; the chosen one
/// has a `text` ring.
struct FocusColorSwatches: View {
    let selection: UInt32
    var palette: [UInt32] = Focus.projectPalette
    let choose: (UInt32) -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(palette, id: \.self) { hex in
                Button { choose(hex) } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 18, height: 18)
                        .padding(2)
                        .overlay(Circle().strokeBorder(hex == selection ? Focus.text : .clear, lineWidth: 1.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(Focus.colorName(hex))
                .accessibilityLabel(Focus.colorName(hex))
                .accessibilityAddTraits(hex == selection ? .isSelected : [])
            }
        }
    }
}

extension Focus {
    /// Name of a palette color ("Coral"), or its hex
    static func colorName(_ hex: UInt32) -> String {
        switch hex {
        case 0xFF6B4A: return "Coral"
        case 0x4EA1F5: return "Blue"
        case 0x2DBE7A: return "Green"
        case 0xE0A020: return "Amber"
        case 0x8B5CF6: return "Violet"
        case 0xEC4899: return "Pink"
        case 0x14B8A6: return "Teal"
        case 0x64748B: return "Slate"
        case 0x6E6E78: return "Gray"
        case 0xB76E00: return "Ochre"
        case 0x6D5AE6: return "Indigo"
        case 0xDC2626: return "Red"
        default: return String(format: "#%06X", hex)
        }
    }
}

// MARK: - Stepper

/// A field-sized number with − and + buttons (sprint number).
struct FocusStepper: View {
    let value: Int
    var minimum = 1
    var label: String = ""
    let set: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            step("minus", value - 1).disabled(value <= minimum)
            Text("\(value)")
                .font(Focus.control.monospacedDigit())
                .foregroundColor(Focus.text)
                .frame(maxWidth: .infinity)
            step("plus", value + 1)
        }
        .frame(height: Focus.controlHeight)
        .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(Focus.raised))
        .overlay(RoundedRectangle(cornerRadius: Focus.radiusControl).strokeBorder(Focus.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(value + 1)
            case .decrement: if value > minimum { set(value - 1) }
            @unknown default: break
            }
        }
    }

    private func step(_ icon: String, _ newValue: Int) -> some View {
        Button { set(newValue) } label: {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Focus.text2)
                .frame(width: 28, height: Focus.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Choice row

/// A radio choice: a 16pt circle (filled `text` dot when chosen), a title and an optional hint.
struct FocusChoiceRow: View {
    let title: String
    var hint: String?
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle().strokeBorder(selected ? Focus.text : Focus.lineStrong, lineWidth: 1.5)
                    if selected { Circle().fill(Focus.text).frame(width: 7, height: 7) }
                }
                .frame(width: 16, height: 16)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Focus.body).foregroundColor(Focus.text)
                    if let hint {
                        Text(hint).font(Focus.meta).foregroundColor(Focus.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(hovering ? Focus.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Banner

/// A full-width notice card under the filter bar: an icon, a title with one line of explanation,
/// and up to two buttons plus an optional ×. `.info` is raised with `lineStrong` (sample data);
/// `.risk` uses the risk tint (a save or load problem). Radius 10, 14 side padding, min 50 tall.
struct FocusBanner: View {
    enum Tone { case info, risk }

    var tone: Tone = .info
    var systemImage = "info.circle"
    let title: String
    var message: String?
    var primaryTitle: String?
    var primaryAction: () -> Void = {}
    var secondaryTitle: String?
    var secondaryAction: () -> Void = {}
    /// Shows the × when set
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tone == .risk ? Focus.risk : Focus.text3)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tone == .risk ? Focus.riskTint.text : Focus.text)
                if let message {
                    Text(message)
                        .font(Focus.meta)
                        .foregroundColor(tone == .risk ? Focus.riskTint.text.opacity(0.85) : Focus.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let secondaryTitle {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(.focus(.ghost))
                    .fixedSize()
            }
            if let primaryTitle {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.focus())
                    .fixedSize()
            }
            if let dismiss {
                FocusIconButton(systemName: "xmark", label: "Dismiss", size: 24, action: dismiss)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 50)
        .background(RoundedRectangle(cornerRadius: Focus.radiusCard).fill(tone == .risk ? Focus.riskTint.fill : Focus.raised))
        .overlay(
            RoundedRectangle(cornerRadius: Focus.radiusCard)
                .strokeBorder(tone == .risk ? Focus.riskTint.border : Focus.lineStrong, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Empty state

/// Says why a view is empty and offers the next step: a 15pt semibold title, one or two lines of
/// text2 explanation and up to two buttons (the first standard, the second ghost). Left aligned,
/// 20 padding, inside the view's own panel or on the canvas.
struct FocusEmptyState<Accessory: View>: View {
    var systemImage: String?
    let title: String
    let message: String
    var actionTitle: String?
    var action: () -> Void = {}
    var secondaryTitle: String?
    var secondaryAction: () -> Void = {}
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Focus.text3)
                }
                Text(title).font(Focus.header).foregroundColor(Focus.text)
            }
            Text(message)
                .font(Focus.body)
                .foregroundColor(Focus.text2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520, alignment: .leading)
            accessory()
            if actionTitle != nil || secondaryTitle != nil {
                HStack(spacing: 8) {
                    if let actionTitle {
                        Button(actionTitle, action: action).buttonStyle(.focus())
                    }
                    if let secondaryTitle {
                        Button(secondaryTitle, action: secondaryAction).buttonStyle(.focus(.ghost))
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension FocusEmptyState where Accessory == EmptyView {
    init(systemImage: String? = nil, title: String, message: String,
         actionTitle: String? = nil, action: @escaping () -> Void = {},
         secondaryTitle: String? = nil, secondaryAction: @escaping () -> Void = {}) {
        self.init(systemImage: systemImage, title: title, message: message,
                  actionTitle: actionTitle, action: action,
                  secondaryTitle: secondaryTitle, secondaryAction: secondaryAction) { EmptyView() }
    }
}

// MARK: - Hex colors

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

extension Color {
    /// The color mixed toward black by `amount` (0–1), for readable text in a tinted control.
    init(hex: UInt32, darkenedBy amount: CGFloat) {
        let k = 1 - max(0, min(1, amount))
        self.init(nsColor: NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255 * k,
            green: CGFloat((hex >> 8) & 0xFF) / 255 * k,
            blue: CGFloat(hex & 0xFF) / 255 * k,
            alpha: 1
        ))
    }
}
