import SwiftUI
import SwiftData
import PodedgeCore

/// Content for the MenuBarExtra — shows job progress and quick actions.
struct MenuBarContentView: View {
    @Query(sort: \Job.createdAt, order: .reverse) private var jobs: [Job]
    @Query(sort: \Show.title) private var shows: [Show]

    private var activeJobs: [Job] {
        jobs.filter { $0.state == .running || $0.state == .pending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if activeJobs.isEmpty {
                Text("No active jobs")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(activeJobs.prefix(5)) { job in
                    jobRow(job)
                    Divider()
                }
            }

            Divider()

            Button {
                NSApp.activate()
                if let window = NSApp.windows.first(where: { $0.isKeyWindow || $0.canBecomeKey }) {
                    window.makeKeyAndOrderFront(nil)
                }
            } label: {
                Label("Open Podedge", systemImage: "macwindow")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit Podedge")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .keyboardShortcut("q")
        }
        .frame(width: 260)
    }

    private func jobRow(_ job: Job) -> some View {
        HStack(spacing: 8) {
            if job.state == .running {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(job.kind.rawValue.capitalized)
                    .font(.caption)
                Text(job.state.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
