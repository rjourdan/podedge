import SwiftUI
import PodedgeCore

/// Small colored dot indicating episode lifecycle status.
struct StatusDot: View {
    let status: EpisodeStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(status.rawValue)
    }

    private var color: Color {
        switch status {
        case .draft: .gray
        case .processing: .blue
        case .ready: .green
        case .scheduled: .orange
        case .published: .teal
        case .failed: .red
        }
    }
}
