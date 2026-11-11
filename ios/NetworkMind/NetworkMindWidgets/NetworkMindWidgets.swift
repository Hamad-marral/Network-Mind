import WidgetKit
import SwiftUI
import AppIntents
import ActivityKit

@main
struct NetworkMindWidgetsBundle: WidgetBundle {
    var body: some Widget {
        EventModeLiveActivity()
        if #available(iOSApplicationExtension 18.0, *) {
            EventModeControl()
        }
    }
}

/// Lock Screen / Dynamic Island Live Activity while Event Mode records.
struct EventModeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EventModeActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.state.isInterrupted ? "mic.slash.fill" : "mic.fill")
                    .font(.title2)
                    .foregroundStyle(context.state.isInterrupted ? Color.orange : Color.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Event Mode")
                        .font(.headline)
                    Text(context.state.isInterrupted ? "Paused (microphone in use)" : "Recording for notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ElapsedText(startedAt: context.attributes.startedAt)
                    .font(.title3.monospacedDigit())
                Button(intent: StopEventModeLiveActivityIntent()) {
                    Image(systemName: "stop.fill")
                        .accessibilityLabel("Stop Event Mode")
                }
                .tint(.red)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.75))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Event Mode", systemImage: "mic.fill")
                        .foregroundStyle(.red)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(startedAt: context.attributes.startedAt)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Button(intent: StopEventModeLiveActivityIntent()) {
                        Label("Stop recording", systemImage: "stop.fill")
                    }
                    .tint(.red)
                }
            } compactLeading: {
                Image(systemName: "mic.fill").foregroundStyle(.red)
            } compactTrailing: {
                ElapsedText(startedAt: context.attributes.startedAt)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "mic.fill").foregroundStyle(.red)
            }
        }
    }
}

private struct ElapsedText: View {
    let startedAt: Date

    var body: some View {
        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            .multilineTextAlignment(.trailing)
    }
}

/// Control Center / Lock Screen / Action Button control (iOS 18+). Opens the app to toggle:
/// stopping is immediate, starting shows the per-session consent confirmation.
@available(iOSApplicationExtension 18.0, *)
struct EventModeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.networkmind.app.event-mode-control") {
            ControlWidgetButton(action: ToggleEventModeIntent()) {
                Label("Event Mode", systemImage: "mic.badge.plus")
            }
        }
        .displayName("Event Mode")
        .description("Start or stop NetworkMind Event Mode.")
    }
}
