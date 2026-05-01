import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PodedgeCore

/// Detail view for editing a show's metadata, cover art, and per-show settings.
struct ShowEditorView: View {
    let showID: PersistentIdentifier

    @Environment(\.modelContext) private var modelContext
    // NOTE: SwiftData @Query does not support filtering by PersistentIdentifier in predicates.
    // We fetch all shows and filter in memory. For large datasets, consider a manual fetch.
    @Query private var shows: [Show]

    private var show: Show? {
        shows.first { $0.persistentModelID == showID }
    }

    var body: some View {
        if let show {
            ShowEditorForm(show: show)
        } else {
            ContentUnavailableView("Show Not Found", systemImage: "exclamationmark.triangle")
        }
    }
}

// MARK: - Editor Form

private struct ShowEditorForm: View {
    @Bindable var show: Show
    @Environment(\.modelContext) private var modelContext
    @State private var showingCoverArtPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                Divider()
                metadataSection
                Divider()
                ownerSection
                Divider()
                podcastingSection
                Divider()
                feedSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .fileImporter(isPresented: $showingCoverArtPicker, allowedContentTypes: [.png, .jpeg]) { result in
            if case .success(let url) = result {
                // Cover art import — would create Asset via IngestService
                print("Selected cover art: \(url.lastPathComponent)")
            }
        }
    }

    private var headerSection: some View {
        HStack(spacing: 16) {
            coverArtButton
            VStack(alignment: .leading, spacing: 4) {
                Text(show.title)
                    .font(.title)
                    .fontWeight(.bold)
                Text("by \(show.author)")
                    .foregroundStyle(.secondary)
                Text("\(show.episodes.count) episode\(show.episodes.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private var coverArtButton: some View {
        Button {
            showingCoverArtPicker = true
        } label: {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change cover art")
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metadata")
                .font(.headline)
            LabeledContent("Title") {
                TextField("Title", text: $show.title)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Author") {
                TextField("Author", text: $show.author)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Category") {
                TextField("Category", text: $show.category)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Language") {
                TextField("Language", text: $show.language)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Summary") {
                TextEditor(text: $show.summary)
                    .frame(height: 80)
                    .border(.separator)
            }
            Toggle("Explicit Content", isOn: $show.explicit)
        }
    }

    private var ownerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Owner")
                .font(.headline)
            LabeledContent("Name") {
                TextField("Owner Name", text: $show.ownerName)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Email") {
                TextField("Owner Email", text: $show.ownerEmail)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var podcastingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Podcasting 2.0")
                .font(.headline)
            LabeledContent("Podcast GUID") {
                Text(show.podcastGUID.uuidString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Toggle("Locked", isOn: $show.podcastLocked)
        }
    }

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Feed")
                .font(.headline)
            LabeledContent("Remote Path") {
                TextField("Feed Path", text: $show.feedRemotePath)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}
