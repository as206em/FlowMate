import Charts
import SwiftUI

/// The Sprints view's velocity panel under "Past sprints": a bar per recent sprint (the last six)
/// for the hours of work done (expected time of done tasks), a dash for what was planned and,
/// when the project has a capacity, a dashed line for it. Hover a sprint for its numbers.
struct SprintVelocityPanel: View {
    @EnvironmentObject private var store: TaskStore

    @State private var hovered: Int?

    var body: some View {
        let points = store.velocityHistory()
        let velocity = store.recentVelocityMinutes()
        let hasCapacity = points.contains { $0.capacityHours != nil }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Velocity").font(Focus.groupTitle).foregroundColor(Focus.text)
                if let velocity {
                    Text("~\(Focus.durationString(minutes: velocity)) done per sprint, last \(min(points.count, SprintPlanRules.velocityWindow))")
                        .font(Focus.meta)
                        .foregroundColor(Focus.text3)
                }
                Spacer(minLength: 8)
                legend(hasCapacity: hasCapacity)
            }
            chart(points)
                .frame(height: 120)
            Text(caption(points))
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
        .accessibilityLabel("Velocity")
        .accessibilityValue(points.map { "\($0.shortName): \(SprintPlanRules.hoursText($0.doneHours)) done of \(SprintPlanRules.hoursText($0.plannedHours)) planned" }.joined(separator: ", "))
    }

    private func chart(_ points: [VelocityPoint]) -> some View {
        Chart {
            ForEach(points) { point in
                BarMark(x: .value("Sprint", point.shortName), y: .value("Done", point.doneHours), width: .fixed(18))
                    .foregroundStyle(Focus.done.opacity(hovered == nil || hovered == point.number ? 1 : 0.45))
                    .cornerRadius(4)
                PointMark(x: .value("Sprint", point.shortName), y: .value("Planned", point.plannedHours))
                    .symbol { Capsule().fill(Focus.text2).frame(width: 26, height: 2.5) }
                if let capacity = point.capacityHours {
                    LineMark(x: .value("Sprint", point.shortName), y: .value("Capacity", capacity))
                        .foregroundStyle(Focus.text3)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
        }
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
            AxisMarks { _ in
                AxisValueLabel().font(.system(size: 10.5)).foregroundStyle(Focus.text3)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            let origin = geo[proxy.plotAreaFrame].origin
                            let name: String? = proxy.value(atX: location.x - origin.x)
                            hovered = points.first { $0.shortName == name }?.number
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
    }

    /// The hovered sprint's numbers, or what the marks mean
    private func caption(_ points: [VelocityPoint]) -> String {
        guard let number = hovered, let point = points.first(where: { $0.number == number }) else {
            return "Hover a sprint for its numbers."
        }
        var parts = ["Sprint \(point.number)", "\(SprintPlanRules.hoursText(point.doneHours)) done",
                     "\(SprintPlanRules.hoursText(point.plannedHours)) planned"]
        if let capacity = point.capacityHours { parts.append("capacity \(SprintPlanRules.hoursText(capacity))") }
        if point.isApproximate { parts.append("worked out from today's tasks") }
        return parts.joined(separator: " · ")
    }

    private func legend(hasCapacity: Bool) -> some View {
        HStack(spacing: 12) {
            legendItem("Done") { RoundedRectangle(cornerRadius: 2).fill(Focus.done).frame(width: 9, height: 9) }
            legendItem("Planned") { Capsule().fill(Focus.text2).frame(width: 12, height: 2.5) }
            if hasCapacity {
                legendItem("Capacity") {
                    Path { p in p.move(to: CGPoint(x: 0, y: 1)); p.addLine(to: CGPoint(x: 14, y: 1)) }
                        .stroke(Focus.text3, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 14, height: 2)
                }
            }
        }
    }

    private func legendItem<Mark: View>(_ title: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 5) {
            mark()
            Text(title).font(Focus.meta).foregroundColor(Focus.text3)
        }
    }
}
