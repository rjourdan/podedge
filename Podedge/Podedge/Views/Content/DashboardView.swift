import SwiftUI
import SwiftData
import PodedgeCore

/// Default content view when no show or episode is selected.
struct DashboardView: View {
    @Query(sort: \Show.title) private var shows: [Show]
    @Query private var allEpisodes: [Episode]
    @Query(sort: \Job.createdAt, order: .reverse) private var recentJobs: [Job]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statsGrid
                recentActivity
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Welcome to Podedge")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Select a show or episode from the sidebar to get started.")
                .foregroundStyle(.secondary)
        }
    }

    private var statsGrid: some View {
        let publishedCount = allEpisodes.filter { $0.status == .published }.count

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            StatCard(title: "Shows", value: "\(shows.count)", icon: "mic.fill")
            StatCard(title: "Episodes", value: "\(allEpisodes.count)", icon: "waveform")
            StatCard(title: "Published", value: "\(publishedCount)", icon: "antenna.radiowaves.left.and.right")
        }
    }

    @ViewBuilder
    private var recentActivity: some View {
        let activeJobs = recentJobs.filter { $0.state == .running || $0.state == .pending }
        if !activeJobs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Active Jobs")
                    .font(.headline)
                ForEach(activeJobs.prefix(5)) { job in
                    HStack {
                        Image(systemName: job.state == .running ? "arrow.triangle.2.circlepath" : "clock")
                            .foregroundStyle(job.state == .running ? .blue : .secondary)
                        Text(job.kind.rawValue.capitalized)
                        Spacer()
                        Text(job.state.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
            Text(value)
                .font(.title)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}
