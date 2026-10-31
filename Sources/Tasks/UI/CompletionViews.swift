import Charts
import SwiftUI

/// "62%" with a bar, and "14h of 23h · 8 of 12 tasks" under it.
struct CompletionSummary: View {
    let title: String
    let completion: Completion
    var help: String = "Done time of the expected time of every task that isn't canceled"

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(Focus.meta).foregroundColor(Focus.text3)
                Spacer(minLength: 8)
                Text(completion.percentText)
                    .font(Focus.header.monospacedDigit())
                    .foregroundColor(Focus.text)
            }
            FocusProgressBar(fraction: completion.fraction, height: 6)
            Text(completion.detail)
                .font(Focus.meta.monospacedDigit())
                .foregroundColor(Focus.text3)
                .lineLimit(1)
        }
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(completion.percentText). \(completion.detail)")
    }
}

/// The Sprints view's progress chart: hours done climbing toward the hours planned, day by day since
/// the sprint began. The planned line steps up when work is added; the dashed line is the pace that
/// finishes everything on the last day.
struct SprintBurnupPanel: View {
    @EnvironmentObject private var store: TaskStore

    @State private var hovered: Date?

    var body: some View {
        let burnup = store.sprintBurnup()
        let completion = store.sprintCompletion()
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Progress").font(Focus.groupTitle).foregroundColor(Focus.text)
                Text("\(completion.percentText) · \(completion.detail)")
                    .font(Focus.meta.monospacedDigit())
                    .foregroundColor(Focus.text3)
                    .lineLimit(1)
                Spacer(minLength: 8)
                paceLabel(burnup)
                legend
            }
            chart(burnup)
                .frame(height: 140)
            Text(caption(burnup))
                .font(Focus.meta.monospacedDigit())
                .foregroundColor(Focus.text3)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Focus.radiusPanel).fill(Focus.raised))
        .overlay(RoundedRectangle(cornerRadius: Focus.radiusPanel).strokeBorder(Focus.hairline, lineWidth: 1))
        .padding(.top, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sprint progress")
        .accessibilityValue("\(completion.percentText) done. \(completion.detail)")
    }

    @ViewBuilder
    private func paceLabel(_ burnup: SprintBurnup) -> some View {
        let ahead = burnup.aheadHours
        if burnup.plannedHours > 0, burnup.today >= burnup.start {
            let text = abs(ahead) < 0.25 ? "On pace"
                : ahead > 0 ? "\(SprintPlanRules.hoursText((ahead * 2).rounded() / 2)) ahead" : "\(SprintPlanRules.hoursText((-ahead * 2).rounded() / 2)) behind"
            Text(text)
                .font(Focus.meta.weight(.semibold))
                .foregroundColor(ahead < -0.25 ? Focus.progress : Focus.text2)
                .help("Done so far against the pace that finishes the plan on the last day")
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            item("Done") { RoundedRectangle(cornerRadius: 2).fill(Focus.done).frame(width: 9, height: 9) }
            item("Planned") { Capsule().fill(Focus.text2).frame(width: 12, height: 2.5) }
            item("Ideal") {
                Path { p in p.move(to: CGPoint(x: 0, y: 1)); p.addLine(to: CGPoint(x: 14, y: 1)) }
                    .stroke(Focus.text3, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: 14, height: 2)
            }
        }
    }

    private func item<Mark: View>(_ title: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 5) {
            mark()
            Text(title).font(Focus.meta).foregroundColor(Focus.text3)
        }
    }

    private func chart(_ burnup: SprintBurnup) -> some View {
        Chart {
            ForEach(burnup.days) { day in
                AreaMark(x: .value("Day", day.date, unit: .day), y: .value("Done", day.doneHours))
                    .foregroundStyle(Focus.done.opacity(0.18))
                LineMark(x: .value("Day", day.date, unit: .day), y: .value("Done", day.doneHours), series: .value("Series", "Done"))
                    .foregroundStyle(Focus.done)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                LineMark(x: .value("Day", day.date, unit: .day), y: .value("Planned", day.plannedHours), series: .value("Series", "Planned"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Focus.text2)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            // The ideal pace across the whole sprint
            LineMark(x: .value("Day", burnup.start, unit: .day), y: .value("Ideal", burnup.idealHours(on: burnup.start)),
                     series: .value("Series", "Ideal"))
                .foregroundStyle(Focus.text3)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            LineMark(x: .value("Day", burnup.end, unit: .day), y: .value("Ideal", burnup.idealHours(on: burnup.end)),
                     series: .value("Series", "Ideal"))
                .foregroundStyle(Focus.text3)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            if let last = burnup.days.last {
                PointMark(x: .value("Day", last.date, unit: .day), y: .value("Done", last.doneHours))
                    .foregroundStyle(Focus.done)
                    .symbolSize(60)
            }
            if let hovered, let day = burnup.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: hovered) }) {
                RuleMark(x: .value("Day", day.date, unit: .day))
                    .foregroundStyle(Focus.hairline)
            }
        }
        .chartYScale(domain: 0...max(1, burnup.plannedHours, burnup.days.map(\.plannedHours).max() ?? 0))
        .chartXScale(domain: burnup.start...Calendar.current.date(byAdding: .day, value: 1, to: burnup.end)!)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Focus.hairline)
                AxisValueLabel {
                    if let hours = value.as(Double.self) { Text(SprintPlanRules.hoursText(hours)).font(.system(size: 10.5)) }
                }
                .foregroundStyle(Focus.text3)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: burnup.days.count > 14 ? 7 : 1)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.system(size: 10.5)).foregroundStyle(Focus.text3)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            let origin = geo[proxy.plotAreaFrame].origin
                            hovered = proxy.value(atX: location.x - origin.x) as Date?
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
    }

    /// The hovered day's numbers, or today's
    private func caption(_ burnup: SprintBurnup) -> String {
        let day = hovered.flatMap { h in burnup.days.first { Calendar.current.isDate($0.date, inSameDayAs: h) } } ?? burnup.days.last
        guard let day else { return "The sprint hasn't started." }
        let label = Calendar.current.isDateInToday(day.date) ? "Today" : SprintState.shortDate(day.date)
        return "\(label) · \(SprintPlanRules.hoursText(day.doneHours)) done of \(SprintPlanRules.hoursText(day.plannedHours)) planned"
            + " · ideal \(SprintPlanRules.hoursText(burnup.idealHours(on: day.date)))"
    }
}
