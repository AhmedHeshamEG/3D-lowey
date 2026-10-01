import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LoweyWidgets: WidgetBundle {
    var body: some Widget {
        ExportActivityWidget()
    }
}

/// An export in progress: the Lock Screen banner and the Dynamic Island.
struct ExportActivityWidget: Widget {
    private static let accent = Color(red: 1, green: 0.722, blue: 0.278)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ExportActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: context.state.finished ? "checkmark.circle.fill" : "square.and.arrow.up")
                        .foregroundStyle(Self.accent)
                    Text(context.attributes.title).font(.headline)
                    Spacer()
                    Text(status(context.state)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                ProgressView(value: context.state.fraction).tint(Self.accent)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "square.and.arrow.up").foregroundStyle(Self.accent) }
                DynamicIslandExpandedRegion(.trailing) { Text(status(context.state)).monospacedDigit() }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading) {
                        Text(context.attributes.title).font(.headline)
                        ProgressView(value: context.state.fraction).tint(Self.accent)
                    }
                }
            } compactLeading: {
                Image(systemName: "square.and.arrow.up").foregroundStyle(Self.accent)
            } compactTrailing: {
                Text("\(Int(context.state.fraction * 100))%").monospacedDigit()
            } minimal: {
                ProgressView(value: context.state.fraction).progressViewStyle(.circular).tint(Self.accent)
            }
        }
    }

    private func status(_ state: ExportActivityAttributes.ContentState) -> String {
        if state.finished { return "Done" }
        if state.waiting { return "Paused" }
        return "\(Int(state.fraction * 100))%"
    }
}
