import SwiftUI
import SwiftData
import PodedgeCore

/// Tabbed editor for an episode: Metadata, Transcript/Chapters, Promotion, Publish.
struct EpisodeEditorView: View {
    let episodeID: PersistentIdentifier

    // NOTE: SwiftData @Query does not support filtering by PersistentIdentifier in predicates.
    // We fetch all episodes and filter in memory. For large datasets, consider a manual fetch.
    @Query private var episodes: [Episode]
    @State private var selectedTab: EditorTab = .metadata

    private var episode: Episode? {
        episodes.first { $0.persistentModelID == episodeID }
    }

    enum EditorTab: String, CaseIterable {
        case metadata = "Metadata"
        case transcript = "Transcript & Chapters"
        case promotion = "Promotion"
        case publish = "Publish"
    }

    var body: some View {
        if let episode {
            VStack(spacing: 0) {
                editorHeader(episode)
                Divider()
                Picker("Tab", selection: $selectedTab) {
                    ForEach(EditorTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()

                switch selectedTab {
                case .metadata:
                    MetadataTab(episode: episode)
                case .transcript:
                    TranscriptTab(episode: episode)
                case .promotion:
                    PromotionTabView(episode: episode)
                case .publish:
                    PublishTab(episode: episode)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
        } else {
            ContentUnavailableView("Episode Not Found", systemImage: "exclamationmark.triangle")
        }
    }

    private func editorHeader(_ episode: Episode) -> some View {
        HStack(spacing: 12) {
            StatusDot(status: episode.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                HStack(spacing: 8) {
                    if let number = episode.number {
                        Text("Episode \(number)")
                    }
                    Text(episode.status.rawValue.capitalized)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Metadata Tab

private struct MetadataTab: View {
    @Bindable var episode: Episode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LabeledContent("Title") {
                    TextField("Title", text: $episode.title)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Subtitle") {
                    TextField("Subtitle", text: Binding(
                        get: { episode.subtitle ?? "" },
                        set: { episode.subtitle = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Summary") {
                    TextEditor(text: $episode.summary)
                        .frame(height: 80)
                        .border(.separator)
                }
                HStack(spacing: 16) {
                    LabeledContent("Season") {
                        TextField("Season", value: $episode.season, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    LabeledContent("Episode #") {
                        TextField("Number", value: $episode.number, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    LabeledContent("Type") {
                        Picker("Type", selection: $episode.type) {
                            Text("Full").tag(EpisodeType.full)
                            Text("Trailer").tag(EpisodeType.trailer)
                            Text("Bonus").tag(EpisodeType.bonus)
                        }
                        .frame(width: 100)
                    }
                }
                LabeledContent("Scheduled For") {
                    HStack {
                        Toggle("Enable", isOn: Binding(
                            get: { episode.scheduledFor != nil },
                            set: { episode.scheduledFor = $0 ? Date() : nil }
                        ))
                        .labelsHidden()
                        if episode.scheduledFor != nil {
                            DatePicker("", selection: Binding(
                                get: { episode.scheduledFor ?? Date() },
                                set: { episode.scheduledFor = $0 }
                            ))
                            .labelsHidden()
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Transcript & Chapters Tab

private struct TranscriptTab: View {
    @Bindable var episode: Episode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Transcript")
                    .font(.headline)
                if episode.transcriptAssetID != nil {
                    Label("Transcript available", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("No transcript yet", systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
                    Text("A transcript will be generated automatically after ingest.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Divider()

                Text("Chapters")
                    .font(.headline)
                TextEditor(text: Binding(
                    get: { episode.chaptersJSON ?? "" },
                    set: { episode.chaptersJSON = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 120)
                .border(.separator)
                .font(.system(.body, design: .monospaced))
                .accessibilityLabel("Chapters JSON editor")

                Text("Paste JSON Chapters format or leave empty for auto-generation.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
    }
}

// MARK: - Publish Tab

private struct PublishTab: View {
    let episode: Episode

    @Environment(ConfirmationCoordinator.self) private var coordinator
    @State private var isPublishing = false
    @State private var publishError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Publish")
                    .font(.headline)

                statusSection

                if let publishError {
                    Text(publishError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                HStack(spacing: 12) {
                    Button {
                        // Dry run via PublishDryRun
                    } label: {
                        Label("Dry Run", systemImage: "eye")
                    }
                    .accessibilityLabel("Preview publish without uploading")

                    Button {
                        Task { await publishEpisode() }
                    } label: {
                        Label("Publish Now", systemImage: "arrow.up.circle.fill")
                    }
                    .disabled(episode.status != .ready && episode.status != .scheduled || isPublishing)
                    .accessibilityLabel("Publish episode")
                }

                if isPublishing {
                    ProgressView("Publishing…")
                }

                Divider()

                FeedPreviewView(showID: episode.show?.persistentModelID)
            }
            .padding(16)
        }
    }

    private var statusSection: some View {
        HStack(spacing: 8) {
            StatusDot(status: episode.status)
            Text("Status: \(episode.status.rawValue.capitalized)")
            if let pubDate = episode.pubDate {
                Text("• Published \(pubDate, style: .date)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Presents a confirmation dialog, then publishes via ToolBroker.
    private func publishEpisode() async {
        isPublishing = true
        defer { isPublishing = false }
        publishError = nil

        // TODO: Wire to ToolBroker publish tool once registered.
        // For now, route through ConfirmationCoordinator for the confirmation flow.
        coordinator.requestConfirmation(
            toolName: "publish_episode",
            input: Data(),
            broker: ToolBroker(registry: ToolRegistry()),
            caller: AppCaller()
        )
    }
}

/// Default app-level tool caller with full capability tier.
struct AppCaller: ToolCaller {
    var capabilityTier: CapabilityTier { .full }
}
