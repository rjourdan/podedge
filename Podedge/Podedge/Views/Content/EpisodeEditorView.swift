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
    @Environment(\.appServices) private var appServices

    @Query private var allSuggestions: [EpisodeSuggestions]
    @State private var showingCoverPicker = false

    private var suggestions: EpisodeSuggestions? {
        allSuggestions.first { $0.episodeID == episode.id }
    }

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

                // MARK: Suggestions

                if let suggestions {
                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Suggestions")
                            .font(.headline)

                        suggestionRow(
                            label: "Title",
                            current: episode.title,
                            suggested: suggestions.suggestedTitle
                        ) {
                            episode.title = suggestions.suggestedTitle
                        }

                        suggestionRow(
                            label: "Subtitle",
                            current: episode.subtitle ?? "",
                            suggested: suggestions.suggestedSubtitle
                        ) {
                            episode.subtitle = suggestions.suggestedSubtitle
                        }

                        suggestionRow(
                            label: "Description",
                            current: episode.summary,
                            suggested: suggestions.suggestedDescriptionHTML
                        ) {
                            episode.summary = suggestions.suggestedDescriptionHTML
                        }

                        // Keywords (informational only)
                        if !suggestions.keywords.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Keywords")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                FlowLayout(spacing: 6) {
                                    ForEach(suggestions.keywords, id: \.self) { keyword in
                                        Text(keyword)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.fill.tertiary)
                                            .clipShape(.capsule)
                                    }
                                }
                            }
                        }

                        Button("Regenerate") {
                            // TODO: Route through ToolBroker once Spec 08 (Tool Registry Wiring) is complete.
                            Task {
                                guard let services = appServices else { return }
                                let job = Job(kind: .generateMetadata, targetID: episode.id)
                                let context = services.modelContainer.mainContext
                                context.insert(job)
                                try? context.save()
                            }
                        }
                        .controlSize(.small)
                        .accessibilityLabel("Regenerate metadata suggestions")
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

    private func suggestionRow(
        label: String,
        current: String,
        suggested: String,
        onApply: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Apply") { onApply() }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Apply suggested \(label.lowercased())")
            }
            Text(suggested)
                .font(.callout)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.fill.tertiary)
                .clipShape(.rect(cornerRadius: 6))
        }
    }
}

// MARK: - Transcript & Chapters Tab

private struct TranscriptTab: View {
    @Bindable var episode: Episode
    @Environment(\.modelContext) private var modelContext

    @Query private var jobs: [Job]
    @Query private var allSuggestions: [EpisodeSuggestions]
    @State private var vttContent: String?

    private var suggestions: EpisodeSuggestions? {
        allSuggestions.first { $0.episodeID == episode.id }
    }

    private var isTranscribing: Bool {
        let epID = episode.id
        return jobs.contains { $0.kind == .transcribe && $0.targetID == epID && ($0.state == .running || $0.state == .pending) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Transcript")
                    .font(.headline)

                if episode.transcriptAssetID != nil {
                    if let vttContent {
                        Text(vttContent)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ProgressView()
                            .task { loadVTT() }
                    }
                } else if isTranscribing {
                    ProgressView("Transcribing…")
                } else if episode.status == .failed {
                    ContentUnavailableView {
                        Label("Transcription Failed", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("The transcription could not be completed. Check Settings → Models to verify your model is downloaded.")
                    }
                } else {
                    Label("No transcript available", systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
                    Text("Transcription runs automatically after ingest.")
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

                // MARK: Suggested Chapters

                if let chapters = suggestions?.chapters, !chapters.isEmpty {
                    Divider()
                    HStack {
                        Text("Suggested Chapters")
                            .font(.headline)
                        Spacer()
                        Button("Apply All") {
                            let encoder = JSONEncoder()
                            if let data = try? encoder.encode(chapters),
                               let json = String(data: data, encoding: .utf8) {
                                episode.chaptersJSON = json
                            }
                        }
                        .controlSize(.small)
                        .accessibilityLabel("Apply all suggested chapters")
                    }
                    ForEach(Array(chapters.enumerated()), id: \.offset) { _, chapter in
                        HStack {
                            Text(formatTime(chapter.startTime))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(chapter.title)
                                .font(.callout)
                            Spacer()
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func loadVTT() {
        guard let assetID = episode.transcriptAssetID,
              let asset = try? modelContext.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetID })).first else {
            return
        }
        vttContent = try? String(contentsOf: asset.localURL, encoding: .utf8)
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Publish Tab

private struct PublishTab: View {
    @Bindable var episode: Episode

    @Environment(\.appServices) private var appServices
    @Environment(\.modelContext) private var modelContext

    @State private var publishError: String?
    @State private var showingDryRun = false
    @State private var publishPlan: PublishPlan?
    @State private var dryRunError: String?
    @State private var scheduleError: String?
    @State private var showingPublishConfirmation = false
    @State private var showingUnpublishConfirmation = false

    private var canPublish: Bool {
        episode.status == .ready || episode.status == .scheduled
    }

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

                // Task 10.4 — Schedule DatePicker
                if episode.status == .ready {
                    schedulingSection
                }

                if let scheduleError {
                    Text(scheduleError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                HStack(spacing: 12) {
                    // Task 10.2 — Dry Run
                    Button {
                        Task { await performDryRun() }
                    } label: {
                        Label("Preview Publish", systemImage: "eye")
                    }
                    .disabled(!canPublish)
                    .accessibilityLabel("Preview publish without uploading")

                    // Task 10.1 — Publish
                    Button {
                        publishWithConfirmation()
                    } label: {
                        Label("Publish Now", systemImage: "arrow.up.circle.fill")
                    }
                    .disabled(!canPublish || episode.status == .processing)
                    .accessibilityLabel("Publish episode")

                    // Task 10.3 — Unpublish
                    if episode.status == .published {
                        Button(role: .destructive) {
                            unpublishWithConfirmation()
                        } label: {
                            Label("Unpublish", systemImage: "arrow.down.circle")
                        }
                        .accessibilityLabel("Unpublish episode")
                    }
                }

                if episode.status == .processing {
                    ProgressView("Publishing…")
                }

                Divider()

                FeedPreviewView(showID: episode.show?.persistentModelID)
            }
            .padding(16)
        }
        .sheet(isPresented: $showingDryRun) {
            dryRunSheet
        }
        .confirmationDialog(
            "Publish this episode?",
            isPresented: $showingPublishConfirmation,
            titleVisibility: .visible
        ) {
            Button("Publish") { performPublish() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will upload audio and update your RSS feed.")
        }
        .confirmationDialog(
            "Unpublish this episode?",
            isPresented: $showingUnpublishConfirmation,
            titleVisibility: .visible
        ) {
            Button("Unpublish", role: .destructive) { performUnpublish() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will be removed from your RSS feed.")
        }
    }

    // MARK: - Status

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

    // MARK: - Scheduling (Task 10.4)

    private var schedulingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule Publication")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            DatePicker(
                "Publish at",
                selection: Binding(
                    get: { episode.scheduledFor ?? Date().addingTimeInterval(3600) },
                    set: { newDate in
                        do {
                            try Episode.validateScheduledFor(newDate)
                            scheduleError = nil
                            episode.scheduledFor = newDate
                            episode.status = .scheduled
                            appServices?.bgTaskCoordinator.schedulePublish(for: episode)
                            try? modelContext.save()
                        } catch {
                            scheduleError = error.localizedDescription
                        }
                    }
                ),
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
        }
    }

    // MARK: - Publish (Task 10.1)

    private func publishWithConfirmation() {
        showingPublishConfirmation = true
    }

    private func performPublish() {
        guard let services = appServices else { return }
        episode.status = .processing
        let job = Job(kind: .publish, targetID: episode.id)
        do {
            try services.jobScheduler.enqueue(job)
            try modelContext.save()
        } catch {
            publishError = error.localizedDescription
        }
    }

    // MARK: - Dry Run (Task 10.2)

    private func performDryRun() async {
        guard let services = appServices, let show = episode.show else {
            dryRunError = "Missing show or services."
            showingDryRun = true
            return
        }
        dryRunError = nil
        do {
            publishPlan = try await services.publishDryRun.plan(show: show, episode: episode)
        } catch {
            dryRunError = error.localizedDescription
            publishPlan = nil
        }
        showingDryRun = true
    }

    @ViewBuilder
    private var dryRunSheet: some View {
        NavigationStack {
            Group {
                if let dryRunError {
                    ContentUnavailableView {
                        Label("Dry Run Failed", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(dryRunError)
                    }
                } else if let plan = publishPlan {
                    List {
                        Section("Files to Upload") {
                            ForEach(Array(plan.uploads.enumerated()), id: \.offset) { _, upload in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(upload.remotePath)
                                            .font(.caption.monospaced())
                                        Text(upload.contentType)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: upload.byteSize, countStyle: .file))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if upload.alreadyUploaded {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .help("Already uploaded")
                                    }
                                }
                            }
                        }

                        if !plan.feedValidationIssues.isEmpty {
                            Section("Feed Validation Issues") {
                                ForEach(plan.feedValidationIssues, id: \.self) { issue in
                                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                }
                            }
                        } else {
                            Section("Feed") {
                                Label("Feed is valid", systemImage: "checkmark.circle")
                                    .foregroundStyle(.green)
                            }
                        }

                        Section("Distribution Targets") {
                            if plan.distributionTargets.isEmpty {
                                Text("No distribution targets configured.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(plan.distributionTargets, id: \.self) { target in
                                    Text(target)
                                }
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Publish Preview")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingDryRun = false }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    // MARK: - Unpublish (Task 10.3)

    private func unpublishWithConfirmation() {
        showingUnpublishConfirmation = true
    }

    private func performUnpublish() {
        episode.status = .draft
        episode.pubDate = nil
        // TODO: Call publishService.regenerateFeed(for:excluding:) when available.
        // Feed regeneration will be handled when the next episode is published.
        try? modelContext.save()
    }
}

/// Default app-level tool caller with full capability tier.
struct AppCaller: ToolCaller {
    var capabilityTier: CapabilityTier { .full }
}

// MARK: - FlowLayout

/// A simple wrapping layout that arranges subviews left-to-right, wrapping to new lines.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
    }
}
