import SwiftUI

/// Circular initials avatar.
struct AvatarView: View {
    let initials: String
    var size: CGFloat = 44

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.accentColor.gradient))
            .accessibilityHidden(true)
    }
}

/// Small rounded label used for tags and statuses.
struct TagChip: View {
    let text: String
    var color: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

extension TimeInterval {
    /// "1h 05m" / "12m" / "45s".
    var compactDuration: String {
        let total = Int(self.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}

extension RecordingStatus {
    var color: Color {
        switch self {
        case .recording: .red
        case .interrupted: .orange
        case .failed: .red
        case .processed: .green
        default: .blue
        }
    }
}
