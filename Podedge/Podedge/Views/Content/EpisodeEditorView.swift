import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PodedgeCore

/// Tabbed editor for an episode: Metadata, Transcript/Chapters, Promotion, Publish.
struct EpisodeEditorView: View {
    let episodeID: PersistentIdentifier

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
                Picker(selection: $selectedTab) {
                    ForEach(EditorTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                } label: {
                    EmptyView()
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

            if episode.status == .draft {
                Button {
                    episode.status = .processing
                    // TODO: Enqueue IngestService job via JobScheduler for full pipeline
                    // (validate → hash → probe → waveform → ID3 → transcribe → metadata).
                    // For now, mark as ready after a brief delay to simulate processing.
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        episode.status = .ready
                    }
                } label: {
                    Label("Process", systemImage: "waveform.badge.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Start processing this episode")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Metadata Tab

private struct MetadataTab: View {
    @Bindable var episode: Episode
    @Environment(\.modelContext) private var modelContext

    @State private var showingCoverPicker = false

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

                VStack(alignment: .leading, spacing: 4) {
                    Text("Show Notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $episode.summary)
                        .frame(height: 100)
                        .border(.separator)
                    Text("Appears as the episode description in podcast apps. Can be generated with AI from the transcript.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Cover Art
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cover Art")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        coverArtPreview
                        VStack(alignment: .leading, spacing: 4) {
                            Button("Choose Image…") {
                                showingCoverPicker = true
                            }
                            .accessibilityLabel("Choose episode cover art")
                            if episode.coverArtAssetID != nil {
                                Button("Use Show Default", role: .destructive) {
                                    episode.coverArtAssetID = nil
                                }
                                .font(.caption)
                            } else {
                                Text("Using show cover art")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .fileImporter(isPresented: $showingCoverPicker, allowedContentTypes: [.png, .jpeg]) { result in
                    if case .success(let url) = result {
                        importCoverArt(from: url)
                    }
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
                        .labelsHidden()
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

    @ViewBuilder
    private var coverArtPreview: some View {
        if let coverID = episode.coverArtAssetID,
           let asset = try? modelContext.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == coverID })).first,
           let image = NSImage(contentsOf: asset.localURL) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func importCoverArt(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let artDir = appSupport.appendingPathComponent("Podedge/CoverArt", isDirectory: true)
        try? FileManager.default.createDirectory(at: artDir, withIntermediateDirectories: true)

        let assetID = UUID()
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let destURL = artDir.appendingPathComponent("\(assetID.uuidString).\(ext)")

        do {
            try FileManager.default.copyItem(at: url, to: destURL)
        } catch { return }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: destURL.path(percentEncoded: false))[.size] as? Int64) ?? 0
        let contentType = ext == "png" ? "image/png" : "image/jpeg"

        let asset = Asset(
            id: assetID,
            kind: .coverArt,
            localURL: destURL,
            sha256: "",
            byteSize: fileSize,
            contentType: contentType
        )
        modelContext.insert(asset)
        episode.coverArtAssetID = assetID
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
                    Text("A transcript will be generated during processing.")
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

    private func publishEpisode() async {
        isPublishing = true
        defer { isPublishing = false }
        publishError = nil

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
