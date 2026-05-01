import SwiftUI
import SwiftData
import PodedgeCore

/// Displays a preview of the generated RSS XML with validation warnings.
struct FeedPreviewView: View {
    let showID: PersistentIdentifier?

    @Query private var shows: [Show]
    @State private var xmlPreview = ""
    @State private var validationIssues: [String] = []
    @State private var isGenerating = false

    private var show: Show? {
        guard let showID else { return nil }
        return shows.first { $0.persistentModelID == showID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Feed Preview")
                    .font(.headline)
                Spacer()
                Button {
                    generatePreview()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(show == nil || isGenerating)
                .accessibilityLabel("Regenerate feed preview")
            }

            if !validationIssues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(validationIssues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(8)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            if isGenerating {
                ProgressView("Generating feed…")
            } else if xmlPreview.isEmpty {
                Text("Press Refresh to generate a feed preview.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Text(xmlPreview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 300)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("RSS XML preview")
            }
        }
    }

    private func generatePreview() {
        guard let show else { return }
        isGenerating = true

        let showSnap = show.snapshot
        let episodeSnaps: [EpisodeSnapshot] = show.episodes
            .filter { $0.status == .published }
            .map { $0.snapshot }

        Task.detached(priority: .userInitiated) {
            let builder = FeedBuilder(resolveAsset: { _ in nil })
            let feedURL = URL(string: "https://example.com/\(showSnap.feedRemotePath)")!
            let feed = builder.build(show: showSnap, episodes: episodeSnaps, feedURL: feedURL)

            let validator = FeedValidator()
            let issues = validator.validate(feed)

            let serializer = FeedXMLSerializer()
            let data = serializer.serialize(feed)
            let xml = String(data: data, encoding: .utf8) ?? ""

            await MainActor.run {
                validationIssues = issues
                xmlPreview = xml
                isGenerating = false
            }
        }
    }
}
